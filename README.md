# homelab-ansible

## 1. Opzetten


```bash
# === A. Werkstation =======================================================

# Toolchain, versies gepind in requirements.txt
pipx install "ansible-core==2.21.4" "ansible-lint==26.8.0"
ansible-galaxy collection install -r collections/requirements.yml

# De ansible-sleutel. Niet opnieuw aanmaken: hij bestaat al, de hosts kennen
# hem. Staat op de mbp in ~/.ssh/ en in de wachtwoordkluis. Kopieer hem.
scp <mac>:'~/.ssh/ansible_ed25519*' ~/.ssh/
chmod 600 ~/.ssh/ansible_ed25519

# Twee vault-wachtwoorden, plakken zonder spaties achteraan
install -m 600 /dev/null ~/.ansible/vault_pass_infra
install -m 600 /dev/null ~/.ansible/vault_pass_stacks
$EDITOR ~/.ansible/vault_pass_infra
$EDITOR ~/.ansible/vault_pass_stacks

# Pre-commit hook aanzetten, git doet dit niet zelf
git config core.hooksPath .githooks

# Werkt het?
bin/check-vaulted && ansible-lint && ansible all -m ping
```

Verbinden gaat met `~/.ssh/ansible_ed25519`, als gebruiker `ansible`, op elke
Linux-host. Dat pad staat vast in `ansible.cfg`, hernoemen kan dus niet.

```bash
# === B. Van niets naar alles ==============================================
# Alleen na een herinstallatie van pve01. Draai blok A eerst; zonder sleutel
# en vault-wachtwoorden begint er hier niets.

# --- 1. pve01, met de hand op de console ----------------------------------
# Proxmox van USB, vast op 192.168.0.14. Dat adres staat hard in
# inventory/00-static.yml en in pve_api_host; een ander adres breekt alles.

zpool import vm-hdd     # Overleefde de pool, dan overleefden de VM-schijven
                        # én de PBS-datastore. Is hij weg, zijn je back-ups weg.

# Het API-token. Dit moet écht eerst: de dynamische inventory praat via dat
# token, dus zonder token ziet Ansible geen enkele guest. Geen playbook maakt
# dit aan — een playbook heeft het token al nodig om te kunnen draaien.
pveum role add AnsibleAutomation --privs "Datastore.AllocateSpace,Datastore.AllocateTemplate,Datastore.Audit,SDN.Use,Sys.Audit,VM.Allocate,VM.Audit,VM.Config.CPU,VM.Config.Disk,VM.Config.Memory,VM.Config.Network,VM.Config.Options,VM.PowerMgmt,VM.GuestAgent.Audit"
pveum user add ansible@pve
pveum acl modify / --user ansible@pve --role AnsibleAutomation
pveum user token add ansible@pve automation --privsep 0   # print het secret, één keer

# Dat secret in vault_pve_api_token_secret zetten, op het werkstation:
ansible-vault edit inventory/group_vars/proxmox/vault.yml

# --- 2. Ansible kan bij pve01 ---------------------------------------------
# Een verse Proxmox laat root nog met een wachtwoord binnen, dus hier werkt
# -u root -k wél. Na de baseline niet meer.
ansible-playbook playbooks/bootstrap.yml --limit pve01 -u root -k
ansible-playbook playbooks/proxmox-access.yml    # rechten gelijk, en bewijst het token
ansible-playbook playbooks/site.yml --limit pve01

# --- 3. Back-ups terug in beeld -------------------------------------------
# PBS is VM 100 en draait op pve01 zelf, dus hij moet bestaan vóór je zijn
# opslag kunt koppelen. Maak hem met de hand, exact volgens pve_vms in
# inventory/group_vars/proxmox/vms.yml: MAC overnemen, scsi1 ís de datastore.
# Daarna Datacenter -> Storage -> PBS toevoegen, ook met de hand: die
# definitie draagt de encryptiesleutel en hoort niet in git.
ansible-playbook playbooks/proxmox-datacenter.yml -e proxmox_datacenter_create=true

# --- 4. De containers -----------------------------------------------------
# Eén per keer, in deze volgorde: adguard is de DNS van het netwerk, caddy de
# voordeur. Elke run maakt de container, bootstrapt en baselinet hem.
ansible-playbook playbooks/new-guest.yml -e guest=adguard
ansible-playbook playbooks/new-guest.yml -e guest=caddy
ansible-playbook playbooks/new-guest.yml -e guest=tailscale
ansible-playbook playbooks/new-guest.yml -e guest=semaphore
# tailscale heeft daarna nog twee `pct set`-regels als root nodig; het token
# kan geen rauwe lxc-keys zetten. Ze staan bij vmid 108 in lxcs.yml.

# --- 5. De virtuele machines ----------------------------------------------
# Met de hand in het scherm, vorm uit vms.yml, MAC-adres overnemen (daar hangt
# de DHCP-reservering aan). Hun waarde is hun schijf, niet hun vorm: data komt
# daarna uit PBS, zie use case "Een back-up terugzetten".
#   100 pbs   101 haos   102 docker-grafana-stack   103 docker
#
# macmini en docker-grafana-stack draaien diensten die deze repo nog niet kan
# terugbouwen. Voor die twee is PBS het herstelpad, niet dit playbook. Wat ze
# draaien haal je op met playbooks/discover.yml; zie hun host_vars voor de
# volgorde waarin dat dichtgetrokken wordt.

# --- 6. Handwerk waar een rol op staat te wachten -------------------------
# adguard   loop de setup-wizard af op http://192.168.0.29:3000, anders stopt
#           de rol met precies die melding. Login daarna in
#           inventory/host_vars/adguard/vault.yml, identiteit infra.
# tailscale OAuth-client in inventory/host_vars/tailscale/vault.yml.
# docker    de docker_stacks-rol maakt een deploy-key aan en print de publieke
#           helft. Zet die in github.com/rubenclaes/containers -> Deploy keys.
#           Tot dan faalt de git-clone en komt geen enkele stack omhoog.

# --- 7. Alles gelijktrekken -----------------------------------------------
ansible-playbook playbooks/site.yml --check --diff
ansible-playbook playbooks/site.yml
ansible-playbook playbooks/docs.yml
ansible-playbook playbooks/report.yml
```

Sleutel kwijt? Nieuwe maken, en hem per host met de hand naar binnen brengen.
`-u root -k` werkt daarbij niet: de baseline zette `PasswordAuthentication
no`, dus een gebaselinede host neemt geen wachtwoord meer aan. Je komt er
alleen nog langs de hypervisor binnen.

```bash
ssh-keygen -t ed25519 -f ~/.ssh/ansible_ed25519 -C "ansible@homelab"

# Per container, als root op pve01. Voor een VM: via de console in het scherm.
pct exec <vmid> -- tee -a /home/ansible/.ssh/authorized_keys <<< "$(cat ~/.ssh/ansible_ed25519.pub)"

# De nieuwe publieke sleutel ook in pve_lxc_defaults.pubkey zetten, anders
# krijgt elke nieuw gebouwde container de oude mee.
$EDITOR inventory/group_vars/proxmox/lxcs.yml
```

---

## 2. Use cases

Alles wat hier staat is te draaien vanaf het werkstation.

```bash

# === Een nieuwe machine op pve01 ==========================================
$EDITOR inventory/group_vars/proxmox/lxcs.yml     # zet hem in pve_lxcs
ansible-playbook playbooks/new-guest.yml -e guest=<hostname>
# Maakt de container, wacht tot hij luistert, vertrouwt zijn hostkey,
# bootstrapt het ansible-account en baselinet hem. Daarna is het een gewone
# host. De dienst erop installeren is een eigen rol, of de use case hieronder.
ansible-playbook playbooks/site.yml --check --diff --limit <hostname>


# === Een nieuwe Docker-dienst =============================================
ansible-playbook playbooks/new-service.yml \
  -e svc_name=memos \
  -e svc_port=5230 \
  -e svc_image=ghcr.io/usememos/memos:0.24.4 \
  -e svc_volume=/var/opt/memos \
  -e '{"svc_desc": "Memos - snelle notities"}'    # waarde met spaties MOET JSON zijn
# Dit schrijft de compose-file, de .env (vaulted), en registreert de stack in
# docker_stacks_list en de route in caddy_sites. Daarna zelf:
cd ~/Development/containers && git add stacks/memos && git commit -m 'Add memos' && git push
ansible-playbook playbooks/stacks.yml
ansible-playbook playbooks/caddy.yml


# === Een route toevoegen of wijzigen ======================================
$EDITOR inventory/host_vars/caddy/main.yml        # caddy_sites
ansible-playbook playbooks/caddy.yml
ansible-playbook playbooks/caddy-smoketest.yml    # vraagt elke site op, faalt op een dode route
ansible-playbook playbooks/docs.yml               # servicepagina's volgen caddy_sites
# Wie hier woont vindt de dienst via NeoGate, niet via deze site.


# === Pakketten updaten ====================================================
ansible-playbook playbooks/report.yml             # eerst kijken wat er openstaat
ansible-playbook playbooks/update.yml                          # patchen, niet herstarten
ansible-playbook playbooks/update.yml -e allow_reboot=true     # guests mogen herstarten
ansible-playbook playbooks/update.yml -e allow_reboot=true -e allow_hypervisor_reboot=true
# Guests gaan eerst, één voor één, dan pas pve01: anders herstart de
# hypervisor onder zijn eigen guests vandaan.


# === Uitzoeken wat er op een host draait ==================================
ansible-playbook playbooks/discover.yml --limit macmini
# Leest de host uit en schrijft een voorstel in .discovered/<host>.yml:
# compose-projecten met hun paden, gepubliceerde poorten, en op een Mac ook
# `brew leaves` en de casks. Verandert niets, op geen enkele host.
# Voor de hosts die nog niet beschreven staan. Wat je overneemt hoort in
# inventory/host_vars/<host>.yml; een host met een docker_stacks_list wordt
# vanaf dan door stacks.yml beheerd.


# === Caddy upgraden =======================================================
ansible-playbook playbooks/caddy-upgrade.yml
# Niet met apt. De draaiende binary is de pakketversie met caddy-dns/cloudflare
# erin; apt zet de kale terug en die weigert te starten op deze Caddyfile.
ansible-playbook playbooks/caddy-smoketest.yml


# === Schijfruimte vrijmaken ===============================================
ansible-playbook playbooks/cleanup.yml                          # rapporteert alleen
ansible-playbook playbooks/cleanup.yml -e cleanup_apply=true    # ruimt echt op
# Raakt nooit: docker volumes, containers, vastgehouden pakketten.


# === Een Tailscale-sleutel voor een pc of NAS =============================
ansible-playbook playbooks/tailscale-key.yml -e label=pc-ouders
# Print de sleutel één keer. Draai dit vanaf het werkstation, niet vanuit
# Semaphore: daar blijft hij in het tasklog staan. Niet voor telefoons, die
# melden zich via de browser aan.


# === Zien of alles gezond is ==============================================
ansible-playbook playbooks/report.yml     # pending updates, reboots, schijf, drift
open https://report.neodata.be
ansible-playbook playbooks/proxmox-info.yml   # welke guests draaien er nu echt


# === De documentatiesite bijwerken ========================================
ansible-playbook playbooks/docs.yml
# Genereert hosts, containers, stacks en één pagina per service uit de
# inventory, en publiceert naar docs.neodata.be. De servicepagina's worden
# gewist en opnieuw gebouwd, dus een geschrapte route laat geen pagina achter.


# === Een back-up terugzetten ==============================================
# Op pve01:
pvesm list pbs                                            # welke back-ups zijn er
pct restore 107 pbs:backup/ct/107/2026-09-20T01:00:00Z --storage vm-hdd   # container
qmrestore pbs:backup/vm/103/2026-09-20T02:30:00Z 103 --storage vm-hdd     # VM
# Let op: bij pct restore komt het nummer eerst, bij qmrestore de back-up.
pct start 107
ssh-keygen -R <adres>                                     # nieuwe hostkey
ansible-playbook playbooks/site.yml --limit adguard       # terug naar wat de repo zegt
# Twijfel je over een back-up? Zet hem op vmid 199 en kijk, dan `pct destroy 199`.
# Volledige uitleg: docs-site/content/technisch/runbooks/disaster-recovery.mdx


# === Bewijzen dat het herstelpad nog werkt ================================
ansible-playbook playbooks/recovery-drill.yml -e drill_confirm=true
# Bouwt een wegwerpcontainer, bootstrapt, baselinet, controleert, sloopt.
# Faalt hij, dan blijft de container staan zodat je kunt kijken.
# Draai dit na elke wijziging aan proxmox_lxc, bootstrap.yml, baseline of
# new-guest.yml.


# === Guests moeten mee opstarten met pve01 ================================
ansible-playbook playbooks/proxmox-autostart.yml


# === De bridges van pve01 wijzigen ========================================
ansible-playbook playbooks/proxmox-network.yml                            # schrijft alleen
ansible-playbook playbooks/proxmox-network.yml -e proxmox_network_apply=true
# De node herlaadt zijn netwerk terwijl jij eroverheen verbonden bent. Weet
# waar de machine fysiek staat voordat je de vlag zet.
```

---

## 3. Ansible gebruiken

```bash
# --- Wat ga je raken? -----------------------------------------------------
ansible-playbook playbooks/site.yml --check --diff    # droogloop, verandert niets
ansible-playbook playbooks/site.yml --list-hosts      # welke hosts
ansible-playbook playbooks/site.yml --list-tags       # welke tags

# --- Inperken -------------------------------------------------------------
ansible-playbook playbooks/site.yml --limit docker       # één host
ansible-playbook playbooks/site.yml --limit 'linux:!proxmox'
ansible-playbook playbooks/site.yml --tags dns           # één onderdeel
ansible-playbook playbooks/site.yml --start-at-task "..."

# --- De inventory bekijken ------------------------------------------------
ansible-inventory --graph            # groepen en hun hosts
ansible-inventory --host docker      # alle vars van één host
ansible all -m ping                  # komt er overal verbinding
ansible <host> -m setup              # facts, bereikbaar als ansible_facts[...]

# --- Vault ----------------------------------------------------------------
# Twee identiteiten: `infra` (hypervisor, DNS, back-ups, Semaphore) en
# `stacks` (app-secrets in files/env/). Gescheiden naar blast radius.
ansible-vault edit inventory/host_vars/caddy/vault.yml
ansible-vault create --encrypt-vault-id infra inventory/host_vars/adguard/vault.yml
ansible-vault encrypt --encrypt-vault-id stacks files/env/<naam>.env
ansible-vault view files/env/media.env
ansible-vault rekey --new-vault-id infra@<bestand>

# --- Voor je commit -------------------------------------------------------
bin/check-vaulted      # geen geheim in platte tekst (draait ook als pre-commit hook)
ansible-lint
ansible-playbook playbooks/site.yml --syntax-check
```

Tags: `baseline`, `macos`, `caddy`/`web`, `adguard`/`dns`, `tailscale`/`vpn`,
`pbs`/`backup`, `docker`, `semaphore`, `dotfiles`/`workstation`,
`proxmox`/`datacenter`/`network`.

`site.yml` is de converge en is veilig om te herhalen. Deze playbooks zitten
er bewust niet in, want ze provisionen, herstarten of verwijderen:
`bootstrap.yml`, `proxmox-lxcs.yml`, `proxmox-network.yml`,
`proxmox-autostart.yml`, `update.yml`, `cleanup.yml`, `recovery-drill.yml`,
`report.yml`.

