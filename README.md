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
| `bootstrap.yml` | nieuwe host | Maakt het `ansible`-serviceaccount. **Zie onder.** |
| `proxmox-info.yml` | `pve01` | Lijst alle guests via de API. |
| `proxmox-lxcs.yml` | `pve01` | Maakt ontbrekende LXCs uit `pve_lxcs`. |
| `proxmox-autostart.yml` | `pve01` | Zet `onboot=1` waar dat mist. |
| `proxmox-access.yml` | `pve01` | Zet de rechten van het API-token; verifieert zichzelf. |

```bash
ansible-playbook playbooks/site.yml
ansible-playbook playbooks/site.yml --check --diff      # droogloop
ansible-playbook playbooks/site.yml --limit docker    # één host
```

## Vault

Twee identiteiten, gesplitst op blast radius — elke helft roteert los.

| Identiteit | Dekt | Lek betekent |
|---|---|---|
| `infra` | `inventory/**/vault.yml`, `roles/semaphore/files/config.json` | Proxmox-, Cloudflare- en PBS-tokens roteren |
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

Twee rollen configureren software die ze bewust **niet** installeren:

- **`caddy`** — custom build met de Cloudflare DNS-module voor het DNS-01
  wildcard-cert. Het Debian-pakket heeft geen plugins en breekt TLS-uitgifte;
  vandaar de hold. Upgraden gaat met `sudo caddy upgrade` op de host, daarna
  `caddy.yml` + `caddy-smoketest.yml`.
- **`docker_stacks`** — de Docker-engine wordt out of band beheerd; een
  onbewaakte upgrade herstart elke stack.

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
  group_vars/all/           gedeelde settings (report.*)
  group_vars/proxmox/       Proxmox API-creds (main.yml + vault.yml)
  host_vars/<host>/         per host; vault.yml waar secrets spelen
files/env/                  vaulted .env's voor de Docker-stacks
playbooks/                  zie tabel hierboven
playbooks/tasks/            taakbestanden gedeeld tussen plays
bin/check-inventory-parity  vergelijkt twee inventories op ansible_host
roles/                      baseline, caddy, docker_stacks, dotfiles, macos,
                            proxmox_access, proxmox_lxc, semaphore
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
- **Upstreams hebben namen, geen nummers** — een `caddy_sites`-entry wijst naar
  host en poort (`{ name: photos, host: docker, port: 2283 }`), de Caddyfile
  haalt het IP uit `ansible_host`. Dat adres komt live uit Proxmox, dus
  verhuizen kost geen repo-wijziging meer.
  `upstream:` alleen voor targets buiten de inventory.
- Openstaand werk: [TODO.md](TODO.md).
