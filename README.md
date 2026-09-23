# homelab-ansible

## 1. Opzetten


```bash
# === A. Werkstation =======================================================

# Toolchain, versies gepind in requirements.txt
pipx install "ansible-core==2.21.4" "ansible-lint==26.8.0"
pipx inject ansible-core proxmoxer requests   # voor de dynamische inventory
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

Na een herinstallatie van pve01, of als een sleutel kwijt is: zie
[Er is iets stuk](https://docs.neodata.be/runbooks/stuk/).

---

## 2. Waar staat wat

Elke taak heeft een runbook op [docs.neodata.be](https://docs.neodata.be),
stap voor stap en met het waarom erbij. De bron staat in
`docs-site/content/runbooks/`.

| Runbook | Dekt |
| --- | --- |
| Er is iets stuk | een back-up terugzetten, een container herbouwen, de Mac mini, pve01 van nul, `restore-drill.yml` |
| Iets toevoegen | een nieuwe container of VM (`new-guest.yml`), `new-service.yml`, een eigen rol, een route |
| Onderhoud | `update.yml`, `report.yml`, `drift.yml`, `smoketest.yml`, `cleanup.yml`, Semaphore, bridges en DNS |
| Toegang en werkplek | toestellen en mensen, een Tailscale-sleutel, laptop klaarzetten, `docs.yml` |

| Map | Wat |
| --- | --- |
| `inventory/` | de hosts en hun instellingen: hier verander je het meest |
| `roles/` | één rol per onderdeel (baseline, caddy, adguard, ...) |
| `playbooks/` | `site.yml` trekt alles gelijk; de rest draai je apart |
| `files/env/` | gevaulte `.env`-bestanden van de Docker-stacks |
| `docs-site/` | de documentatiesite |

Wijzig je iets, werk dan het bijbehorende runbook in dezelfde commit bij en
draai `ansible-playbook playbooks/docs.yml`.

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

Tags van `site.yml`, per play twee: een naam en een soort.

| Onderdeel | Tags |
| --- | --- |
| Linux-baseline | `baseline` `linux` |
| macOS-baseline | `macos` `workstation` |
| Caddy | `caddy` `web` |
| AdGuard | `adguard` `dns` |
| Tailscale | `tailscale` `vpn` |
| PBS | `pbs` `backup` |
| Proxmox-storage en back-upjobs | `proxmox` `datacenter` |
| Proxmox API-rechten | `proxmox` `access` |
| Docker-engine en stacks | `docker` |
| Semaphore | `semaphore` |
| Dotfiles | `dotfiles` `workstation` |

`proxmox-network.yml` heeft ook tags maar zit niet in `site.yml`, dus
`--tags network` doet daar niets.

`--tags semaphore` slaat de eerste play van `semaphore.yml` over — die
verzamelt facts van alle beheerde hosts en heeft met opzet geen tag. De rol
heeft die facts nodig voor `known_hosts` en stopt met een assert die precies
dat zegt. Draai `playbooks/semaphore.yml` in zijn geheel.

Drie playbooks lijken op elkaar en zijn het niet:

| Playbook | De vraag | Wat hij doet |
| --- | --- | --- |
| `site.yml` | staat alles er zoals beschreven? | zet neer, configureert, en haalt weg wat in een `*_absent`-lijst staat. Versies laat hij met rust. |
| `update.yml` | zijn de versies nog actueel? | `apt full-upgrade` en `brew upgrade`. Reboots alleen op verzoek. |
| `cleanup.yml` | valt er ruimte terug te winnen? | caches, oude images, verweesde pakketten. Rapporteert standaard alleen. |

Iets wat weg moet is dus `site.yml`, niet `cleanup.yml` — die gaat over
schijfruimte, niet over wat er hoort te staan.

`site.yml` is de converge en is veilig om te herhalen. Deze playbooks zitten
er bewust niet in, want ze provisionen, herstarten of verwijderen:
`bootstrap.yml`, `proxmox-lxcs.yml`, `proxmox-network.yml`,
`proxmox-autostart.yml`, `update.yml`, `cleanup.yml`, `restore-drill.yml`,
`report.yml`.

