# homelab-ansible

Ansible voor een kleine thuisinfrastructuur: één Proxmox-host, een handvol
LXC-guests, een Docker-host en twee Macs. Alles is idempotent;
`playbooks/site.yml` mag altijd draaien.

## Snelstart

```bash
git clone git@github.com:rubenclaes/homelab-ansible.git
cd homelab-ansible

# Toolchain — versies gepind in .github/workflows/lint.yml
pipx install "ansible-core==2.21.4" "ansible-lint==26.8.0"
ansible-galaxy collection install -r collections/requirements.yml

# Vault-wachtwoorden (twee, zie onder)
install -m 600 /dev/null ~/.ansible/vault_pass_infra
install -m 600 /dev/null ~/.ansible/vault_pass_stacks
$EDITOR ~/.ansible/vault_pass_infra     # plakken, geen spaties achteraan
$EDITOR ~/.ansible/vault_pass_stacks

# Pre-commit hook — per clone, git doet dit niet zelf
git config core.hooksPath .githooks

# Controle
bin/check-vaulted && ansible-lint && ansible all -m ping
```

SSH-key: `~/.ssh/ansible_ed25519` (in `ansible.cfg`), geautoriseerd voor het
`ansible`-serviceaccount op elke Linux-host.

## Playbooks

| Playbook | Doel | Wat |
|---|---|---|
| `site.yml` | alles | **Master.** Baseline → Caddy → stacks → Semaphore → dotfiles. |
| `baseline.yml` | `linux` | Timezone, basispakketten, unattended upgrades, SSH-hardening. |
| `caddy.yml` | `caddy` | Rendert de Caddyfile uit `caddy_sites`. |
| `stacks.yml` | `docker` | Stacks-repo ophalen, vaulted `.env`s plaatsen, compose up. |
| `semaphore.yml` | `semaphore` | Semaphore UI, virtualenv, `known_hosts`. |
| `dotfiles.yml` | `mbp` | SSH-config, Git-config, `.zshrc`. |
| `report.yml` | alles → `caddy` | Health-rapport op `https://report.<domain>`. |
| `docs.yml` | alles → `caddy` | Rendert en publiceert de documentatiepagina. |
| `caddy-smoketest.yml` | localhost | Bevraagt elke site in `caddy_sites`. |
| `update.yml` | `linux` | Pakketupgrades en optionele reboots. **Zie onder.** |
| `cleanup.yml` | `linux` + `docker_hosts` | Maakt schijfruimte vrij. Rapporteert; ruimt pas met een schakelaar. **Zie onder.** |
| `bootstrap.yml` | nieuwe host | Maakt het `ansible`-serviceaccount. **Zie onder.** |
| `proxmox-info.yml` | `pve01` | Lijst alle guests via de API. |
| `proxmox-lxcs.yml` | `pve01` | Maakt ontbrekende LXCs uit `pve_lxcs`. |
| `proxmox-autostart.yml` | `pve01` | Zet `onboot=1` waar dat mist. |
| `proxmox-access.yml` | `pve01` | Zet de rechten van het API-token; verifieert zichzelf. |
| `proxmox-datacenter.yml` | `pve01` | Storage-definities en backup-jobs uit `pve_storages`/`pve_backup_jobs`. |
| `proxmox-network.yml` | `pve01` | Bridge-configuratie; alleen staging tenzij `-e proxmox_network_apply=true`. **Kan de host onbereikbaar maken — lees de kop van het playbook eerst.** |
| `recovery-drill.yml` | `pve01` | Bouwt, bootstrapt en vernietigt een wegwerp-LXC om het herstelpad te bewijzen. **Vernietigt een guest — alleen met `-e drill_confirm=true`.** |
| `tailscale-key.yml` | localhost | Maakt één eenmalige Tailscale-sleutel voor een toestel uit `devices.yml` en toont hem. **Zie onder.** |
| `devices.yml` | `unifi` + `adguard` | Richt de toestellen zonder SSH in: reservering op de gateway, naam en filterbeleid in AdGuard. **Zie onder.** |

```bash
ansible-playbook playbooks/site.yml
ansible-playbook playbooks/site.yml --check --diff      # droogloop
ansible-playbook playbooks/site.yml --limit docker      # één host
ansible-playbook playbooks/site.yml --tags dns          # één stuk
```

Tags per play, zodat je een deel kunt draaien zonder de rest te raken:
`baseline`, `macos`, `caddy`/`web`, `adguard`/`dns`, `tailscale`/`vpn`,
`pbs`/`backup`, `docker`, `semaphore`, `dotfiles`/`workstation`.

## Vault

Twee identiteiten, gesplitst op blast radius — elke helft roteert los.

| Identiteit | Dekt | Lek betekent |
|---|---|---|
| `infra` | `inventory/**/vault.yml`, `roles/semaphore/files/config.json` | Proxmox-, Cloudflare- en PBS-tokens, de AdGuard-login en de Tailscale OAuth-client roteren |
| `stacks` | `files/env/*.env` | applicatielogins in de stacks roteren |

Beide gaan via `bin/vault-pass-client` — Ansible geeft `--vault-id` door aan elk
executable dat op `-client` eindigt, dus één script bedient ze allebei. Volgorde
per identiteit `<id>`:

| Bron | Gebruikt door |
|---|---|
| `$ANSIBLE_VAULT_PASSWORD_<ID>` | CI en Semaphore |
| `~/.ansible/vault_pass_<id>` | werkstation, het normale geval |
| `~/.ansible/vault_pass` | oude gedeelde wachtwoord, fallback |
| *(placeholder)* | clone zonder secrets — lint en syntax-check blijven werken |

De placeholder is er zodat `ansible-lint` en `--syntax-check` slagen in een
verse clone. Wat écht moet decrypten faalt alsnog met `Decryption failed`.

```bash
# Een nieuw bestand: identiteit noemen, anders wordt het infra
ansible-vault encrypt --encrypt-vault-id stacks files/env/newstack.env
```

> **Semaphore heeft beide wachtwoorden nodig.** `infra` en `stacks` als aparte
> vault keys toevoegen (Key Store → Vault), anders faalt elke run.

## Secrets

Versleuteld at rest:

- `inventory/**/vault.yml` — API-tokens, per host of groep
- `files/env/*.env` — env-bestanden van de Docker-stacks
- `roles/semaphore/files/config.json` — DB- en encryptiesleutels van Semaphore

```bash
ansible-vault view    inventory/host_vars/pbs/vault.yml
ansible-vault edit    files/env/media.env
ansible-vault encrypt files/env/newstack.env    # vóór de eerste commit!
```

- `bin/check-vaulted` controleert al die paden.
- De pre-commit hook is de echte poort: die kijkt naar de *staged blob*, niet
  naar de working tree. Een bestand kan op schijf versleuteld zijn terwijl er
  plaintext in de index staat.
- CI draait dezelfde check, maar pas ná de push — dan is roteren nodig, geen
  revert.
- Noodgeval: `git commit --no-verify`.

Plaintext `vault_*`-variabelen worden aangeroepen vanuit `main.yml` en
gedefinieerd in de encrypted `vault.yml` ernaast: structuur leesbaar zonder
decrypten.

## Updates en reboots

`update.yml` draait bewust in twee plays — **eerst de guests, dan de
hypervisor.** In één play kan `pve01` midden in de run onder zijn eigen guests
vandaan rebooten.

```bash
ansible-playbook playbooks/update.yml                       # alleen patchen
ansible-playbook playbooks/update.yml -e allow_reboot=true  # guests rebooten

# pve01 ook — neemt elke guest mee
ansible-playbook playbooks/update.yml \
  -e allow_reboot=true -e allow_hypervisor_reboot=true
```

- Beide schakelaars staan standaard uit en worden gelezen met `| default(false)`
  in plaats van als play-vars, zodat `group_vars`/`host_vars` ze ook kunnen
  zetten. Een play-level `vars:` overstemt inventory stilletjes — ooit een echte
  bug hier.
- `baseline_held_packages` blijft gepind; `dist-upgrade` respecteert dpkg holds,
  dus de custom Caddy-build overleeft elke update.

## Opruimen

`cleanup.yml` maakt schijfruimte vrij. **Zonder schakelaar verandert het niets**:
dan rapporteert het per host wat er te halen valt — schijfgebruik, de grootte van
de journal, de namen van de pakketten die `autoremove` zou meenemen, en de
uitvoer van `docker system df`.

```bash
ansible-playbook playbooks/cleanup.yml                        # alleen rapport
ansible-playbook playbooks/cleanup.yml -e cleanup_apply=true  # echt opruimen

# eerst één host, voor je het op alles laat lopen
ansible-playbook playbooks/cleanup.yml -e cleanup_apply=true --limit docker
```

| Waar | Wat | Wat niet |
|---|---|---|
| `linux` | `apt autoremove` + `autoclean`, `journalctl --vacuum-time` | gepinde pakketten; dpkg holds blijven staan |
| `docker_hosts` | ongebruikte images (ouder dan `cleanup_docker_until`), *alle* build cache, losse networks | **volumes**, en containers — draaiend of gestopt |

- **Volumes nooit, op geen enkele instelling.** Daar staat de data van de stacks
  in; zo'n volume weggooien is een restore, geen opruiming.
- Een gestopte container houdt zijn image buiten de prune. Een stack die `down`
  staat overleeft dit dus; alleen een image waar geen enkele container meer naar
  wijst verdwijnt, en de prijs van een vergissing is een `pull`.
- `cleanup_docker_until` (720h) kijkt naar de *aanmaakdatum* van het image, niet
  naar wanneer het binnengehaald is. Een lang stabiel upstream-image geldt dus
  als oud, ook al is het gisteren gepulld.
- **Build cache valt met opzet niet onder dat venster.** Een image dat toch nog
  nodig blijkt moet over de lijn opnieuw gepulld worden; build cache hoeft
  alleen opnieuw gebouwd te worden. Daarom `builder_cache_all: true` en geen
  filter: op `docker` stond daar 5,2 GB in met nul actieve entries.
- `cleanup_apply` staat met opzet **niet** in `group_vars`. Dat is de schakelaar
  die een rapport in een verwijdering verandert, dus hij hoort per run of per
  Semaphore-template; een default daar zou elke run destructief maken. Hij wordt
  gelezen met `| default(false)`, om dezelfde reden als bij `update.yml`.
- Retentie staat in `inventory/group_vars/all/cleanup.yml`:
  `cleanup_journal_keep` en `cleanup_docker_until`.
- Niet in `site.yml`: dit playbook verwijdert.

> Een vacuum is een tredmolen — de journal groeit gewoon weer aan. De echte fix
> is een `SystemMaxUse`-cap in de baseline-rol. Staat in [TODO.md](TODO.md).

### In Semaphore

Templates staan niet in deze repo: de rol installeert Semaphore, de templates
maak je in de UI. Twee op hetzelfde playbook, en het verschil zit alleen in de
extra vars:

| Template | Extra vars | Schema |
|---|---|---|
| Cleanup (report) | *(geen)* | met de hand, of dagelijks |
| Cleanup (apply) | `cleanup_apply: true` | zaterdag 03:00 |

Niet zondag 04:00: daar zitten de updates en de PBS-backup al.

## Toestellen zonder SSH

`inventory/group_vars/all/devices.yml` is geen register maar de gewenste
toestand van elk toestel dat geen SSH heeft. `playbooks/devices.yml` zet het
door naar de twee systemen die zo'n toestel wél kunnen configureren.

```bash
# Nieuw toestel: één regel in devices.yml, dan dit.
ansible-playbook playbooks/devices.yml
ansible-playbook playbooks/devices.yml --check --diff     # eerst kijken
```

| Wat | Waar | Uit |
|---|---|---|
| Client-record op MAC, naam, bandbreedtegroep, vaste reservering | UniFi-gateway | `mac`, `ip`, `group` |
| `<toestel>.home.arpa` en `<host>.home.arpa` | AdGuard | `ip` en `ansible_host` |
| Client met filterbeleid | AdGuard | het `dns`-blok |
| `docs.<domain>/profielen/<toestel>.mobileconfig` | docs-site | `devices_profile_types` |
| Eenmalige Tailscale-sleutel | Tailscale | `tailscale-key.yml -e device=<naam>` |

- **Een toestel hoeft nog niet te bestaan.** De gateway maakt een client aan op
  een MAC-adres dat nooit verbonden heeft. Schrijf het nieuwe toestel op, draai
  het playbook, en naam, adres, limiet, DNS-naam en filterbeleid gelden zodra
  het voor het eerst op de wifi komt.
- **Niet in `site.yml`.** Dit schrijft DHCP-reserveringen, en dat is
  provisioning. De AdGuard-helft zit wél in de `adguard`-rol, zodat `site.yml`
  beleidsdrift terugdraait.
- **Geen van beide rollen verwijdert.** Haal je een toestel uit de lijst, dan
  blijven zijn client-records staan; de run noemt bij elke keer welke AdGuard-
  clients hij niet beheert. Vergeten doe je met de hand, in het scherm.
- **`dns.allowed` is een toestemming.** AdGuard bewaart een schema van
  ináctiviteit, dus het venster dat je opschrijft is precies het venster waarin
  de geblokkeerde diensten wél mogen. Een dag die ontbreekt is de hele dag
  dicht, en een venster loopt niet door middernacht. Daar staat een assert op.
- **Lokaal UniFi-account**, gemaakt in het scherm onder Settings, Admins. De
  Ubiquiti-cloudlogin vraagt een tweede factor en kan niet geautomatiseerd
  worden. In `inventory/host_vars/unifi/vault.yml` als `vault_unifi_user` en
  `vault_unifi_password`.
- **De AdGuard-rol bezit alleen de rewrite-lijst en de clients van toestellen
  uit de lijst.** `AdGuardHome.yaml` wordt één keer gelezen, voor de poort, en
  nooit geschreven; het scherm blijft eigenaar van al het andere.
- **Het telefoonprofiel** laat een toestel DNS-over-HTTPS spreken met
  `https://dns.<domain>/dns-query/<toestel>`. Dat laatste stuk is het client-ID,
  zodat AdGuard de telefoon bij naam kent wat zijn MAC-adres ook is. Caddy laat
  op `dns.<domain>` alleen `/dns-query` door. Eén schakelaar in AdGuard zelf:
  *Encryptie → Sta onversleutelde DNS-over-HTTPS toe*.

De gateway zelf wordt niet geconfigureerd. Netwerken, wifi en firewall blijven
handwerk in het scherm; dit raakt uitsluitend client-records.

## Tailnet

`roles/tailscale` meldt een node die niet op de tailnet staat zelf aan, als
de host een OAuth-client heeft (`inventory/host_vars/tailscale/vault.yml`,
`vault_tailscale_oauth_client_id` / `vault_tailscale_oauth_client_secret`,
scope `auth_keys`, tag `tag:homelab`). De rol maakt dan één eenmalige,
vooraf geautoriseerde sleutel via de API, draait `tailscale up` ermee en eist
daarna `Running`. Een node die al draait wordt nooit aangeraakt; zonder client
rapporteert de rol alleen, zoals voorheen.

```bash
# Een sleutel voor iets met een commandoregel: de pc van de ouders, een NAS.
ansible-playbook playbooks/tailscale-key.yml -e device=pc-ouders
```

- De sleutel wordt één keer getoond en nergens bewaard; de beschrijving
  (`ansible-<host>`, `device-<toestel>`) is het enige spoor in de console.
  Draai dit vanaf het werkstation, niet uit Semaphore — een takenlog bewaart
  de uitvoer.
- Niet voor telefoons: de apps melden aan via een browser en hebben geen plek
  voor een sleutel.
- Een node die al prefs had (`--advertise-routes`) weigert een kale
  `tailscale up`; zet wat hij adverteerde in `tailscale_up_extra_args`.

## Nieuwe host

Kip-en-ei: de inventory verbindt als `ansible`, maar dat account bestaat nog
niet. Eerste contact is root met wachtwoord (`-k`):

```bash
ssh-keyscan -H 192.168.0.99 >> ~/.ssh/known_hosts
ansible-playbook playbooks/bootstrap.yml --limit newhost -u root -k
```

Daarom forceert `ansible.cfg` géén `PreferredAuthentications=publickey`. Daarna
volstaat de key.

Volgorde bij een echt nieuwe host: `proxmox-lxcs.yml` → `bootstrap.yml` →
dienst handmatig installeren → rol neemt over.

Alles wat een host nodig heeft wordt geïnstalleerd door een rol. Twee gevallen
verdienen uitleg:

- **`caddy`** installeert het pakket uit de cloudsmith-repo en voegt daarna de
  Cloudflare DNS-module toe met `caddy add-package`. Dat vervangt `/usr/bin/caddy`
  door een build mét plugin — vandaar dat `dpkg --verify caddy` een checksum
  meldt en dat het pakket op hold staat. Een gewone `apt upgrade` zet het
  standaardbinary terug, en dat weigert te starten tegen een Caddyfile met de
  DNS-module. De stap draait alleen als de module ontbreekt, dus op een
  bestaande host raakt hij het binary nooit aan.
- **`docker_engine`** installeert de engine met `state: present`, nooit
  `latest`. Een onbewaakte upgrade herstart de daemon en elke stack; upgraden
  is een bewuste actie, zie de updates-runbook.

Beide repo's worden als `deb822` gedefinieerd en hun signing key zit in de rol
zelf, niet opgehaald tijdens de run: zo is hij leesbaar in Git en hangt
provisioning niet af van een bereikbare vendor.

## Inventory

`inventory/` is een map die Ansible samenvoegt, geen los bestand.

| Bron | Bevat |
|---|---|
| `00-static.yml` | `pve01`, `macmini`, `mbp` + de groepen (`linux`, `macs`, `appliances`) |
| `homelab.proxmox.yml` | de acht Proxmox-guests, live opgehaald; vaulted onder `infra` |

Guests staan nooit met de hand in een lijst. Maak er een in Proxmox en hij
staat er de volgende run in. `ansible_host` komt uit het *runtime*-adres, dus
de twee DHCP-containers kloppen ook — hun `net0` zegt alleen `ip=dhcp`.

Het plugin-bestand is versleuteld omdat het API-token erin staat: inventory
sources worden geparsed vóór `group_vars`, dus verwijzen naar een vaulted
variabele kan daar niet.

```bash
ansible-inventory --graph          # wat Ansible nu ziet
ansible-inventory --host docker    # variabelen van één host
```

`haos` valt in `appliances`, niet in `linux`: Home Assistant OS heeft geen apt
en geen standaard Python. `site.yml` slaat hem over, het rapport ziet hem wel.

Het token heeft `VM.GuestAgent.Audit` nodig, anders geeft het guest-agent
endpoint 403 en krijgen de QEMU-guests geen adres. PVE 8.2 verving daarmee het
oude `VM.Monitor`, dat PVE 9 botweg weigert. Beheerd door
`playbooks/proxmox-access.yml`, niet met de hand.

```bash
# Na een inventory-wijziging: faalt als een host verdwijnt of van adres wisselt
bin/check-inventory-parity <oude-inventory> inventory/
```

> **Semaphore wijst naar de map**, niet naar een bestand. Inventory `homelab`
> staat op `inventory/`; `inventory/hosts.yml` bestaat niet meer.

## Structuur

```
ansible.cfg                 config; pint ook de vault-resolver
bin/vault-pass-client       lost het vault-wachtwoord per identiteit op
bin/check-vaulted           faalt als een secret in plaintext staat
.githooks/pre-commit        blokkeert een commit die zou lekken
collections/                gepinde Galaxy-dependencies (niet gecommit)
inventory/
  00-static.yml             pve01, macmini, mbp + groepsdefinities
  homelab.proxmox.yml       vaulted; guests, live uit Proxmox
  group_vars/all/           gedeelde settings (report.*, cleanup.*)
  group_vars/proxmox/       Proxmox API-creds (main.yml + vault.yml)
  host_vars/<host>/         per host; vault.yml waar secrets spelen
files/env/                  vaulted .env's voor de Docker-stacks
playbooks/                  zie tabel hierboven
playbooks/tasks/            taakbestanden gedeeld tussen plays
bin/check-inventory-parity  vergelijkt twee inventories op ansible_host
roles/                      baseline, caddy, docker_engine, docker_stacks,
                            dotfiles, macos, proxmox_access, proxmox_lxc,
                            semaphore
```

## Het rapport

`report.yml` verzamelt openstaande upgrades, reboot-vlaggen, schijfgebruik,
Docker-containers, ZFS, SMART, Proxmox-guests en PBS-backupleeftijden, rendert
`playbooks/templates/report.html.j2` en publiceert naar de Caddy-host.

- Bereikbaar op `https://report.<domain>`, beperkt tot private ranges plus
  Tailscale's `100.64.0.0/10` — de rest krijgt 403.
- Rendert naar een privé tempfile, niet naar een voorspelbaar `/tmp`-pad: er
  staan interne hostnames en IP's in en de control node deelt ruimte met
  Semaphore.
- Paden staan in `inventory/group_vars/all/report.yml`; `report_publish_dir`
  wordt gelezen door zowel `report.yml` als `Caddyfile.j2`, dus die lopen niet
  uit elkaar.

## CI

`.github/workflows/lint.yml`, op pushes naar `master` en op PR's:

1. `bin/check-vaulted` — geen plaintext secrets
2. `ansible-lint` — schoon; geen `.ansible-lint`, dus de standaardregels
3. `ansible-playbook --syntax-check` op elke playbook

Versies zijn gepind in het `env:`-blok; bump ze samen met
`collections/requirements.yml`. Lokaal hetzelfde:

```bash
bin/check-vaulted && ansible-lint && \
  for p in playbooks/*.yml; do ansible-playbook --syntax-check "$p"; done
```

## Conventies

- **FQCN overal** — `ansible.builtin.copy`, niet `copy`.
- **`inject_facts_as_vars = False`** — facts alleen als
  `ansible_facts['kernel']`, nooit als kale `ansible_kernel`.
- **Rolvariabelen krijgen de rolnaam als prefix** — `baseline_*`, `caddy_*`.
- **`validate:` op alles wat je kan buitensluiten** — sudoers, sshd, Caddyfile.
  Dan faalt de taak in plaats van de host.
- **`no_log: true` en `diff: false`** op taken met secrets.
- **Niets met de hand geconfigureerd** — was het de moeite om twee keer te
  doen, dan zit het in een rol.
- **Elke Linux-host alleen met key** — het `ansible`-serviceaccount escaleert
  met sudo zonder wachtwoord, en geen enkele host accepteert een
  SSH-wachtwoord.
- **`site.yml` convergeert alles en mag op elk moment draaien** — wat
  provisioneert of herstart, zoals `proxmox-lxcs.yml`, `update.yml` en
  `recovery-drill.yml`, valt er bewust buiten. `mbp` is de control node en
  beheert zichzelf.
- **Upstreams hebben namen, geen nummers** — een `caddy_sites`-entry wijst naar
  host en poort (`{ name: photos, host: docker, port: 2283 }`), de Caddyfile
  haalt het IP uit `ansible_host`. Dat adres komt live uit Proxmox, dus
  verhuizen kost geen repo-wijziging meer.
  `upstream:` alleen voor targets buiten de inventory.
- Openstaand werk: [TODO.md](TODO.md).
