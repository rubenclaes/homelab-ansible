# homelab-ansible

Eén Proxmox-host, een paar LXC-containers, een Docker-host en twee Macs.
Alles hier is herhaalbaar: `playbooks/site.yml` mag op elk moment draaien en
verandert alleen wat niet klopt.

Dit bestand gaat over **hoe je de repo gebruikt**. Hoe het in elkaar zit en
waarom staat op [docs.neodata.be](https://docs.neodata.be) (alleen vanaf het
thuisnetwerk of Tailscale).

---

## 1. Eenmalig opzetten

```bash
git clone git@github.com:rubenclaes/homelab-ansible.git
cd homelab-ansible

# Toolchain, versies gepind in requirements.txt
pipx install "ansible-core==2.21.4" "ansible-lint==26.8.0"
ansible-galaxy collection install -r collections/requirements.yml

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
Linux-host.

---

## 2. Wat wil je doen?

| Ik wil... | Doe dit |
| --- | --- |
| Alles gelijktrekken | `ansible-playbook playbooks/site.yml` |
| Een nieuwe machine op pve01 | [Runbook: Nieuwe machine](https://docs.neodata.be/technisch/runbooks/nieuwe-guest/) |
| Een nieuwe Docker-dienst | `ansible-playbook playbooks/new-service.yml -e svc_name=... -e svc_port=... -e svc_image=...` |
| Iets herstellen of een back-up terugzetten | [Runbook: Herstellen](https://docs.neodata.be/technisch/runbooks/disaster-recovery/) |
| Pakketten updaten | [Runbook: Updates](https://docs.neodata.be/technisch/runbooks/updates/) |
| Schijfruimte vrijmaken | `ansible-playbook playbooks/cleanup.yml` (rapporteert; ruimt pas op met `-e cleanup_apply=true`) |
| Een toestel of filterbeleid wijzigen | `inventory/group_vars/all/devices.yml`, dan `site.yml --tags dns` |
| Een route toevoegen | `caddy_sites` in `inventory/host_vars/caddy/main.yml`, dan `playbooks/caddy.yml` |
| Een Tailscale-sleutel voor een pc of NAS | `ansible-playbook playbooks/tailscale-key.yml -e device=<naam>` |
| Zien of alles gezond is | `ansible-playbook playbooks/report.yml`, dan `https://report.neodata.be` |
| De documentatiesite bijwerken | `ansible-playbook playbooks/docs.yml` |

Alle playbooks zien: `ls playbooks/`. Elk bestand begint met een kop die zegt
wat het doet en wanneer je het gebruikt.

---

## 3. Hoe je een wijziging doorvoert

Altijd deze vier stappen, in deze volgorde.

```bash
# 1. Wijzig iets in inventory/ of roles/

# 2. Kijk wat het zou doen. Dit verandert niets.
ansible-playbook playbooks/site.yml --check --diff

# 3. Voer het uit
ansible-playbook playbooks/site.yml

# 4. Commit en push
git add -A && git commit -m "..." && git push
```

Handige beperkingen bij stap 2 en 3:

```bash
ansible-playbook playbooks/site.yml --limit docker    # één host
ansible-playbook playbooks/site.yml --tags dns        # één onderdeel
```

Tags: `baseline`, `macos`, `caddy`/`web`, `adguard`/`dns`, `tailscale`/`vpn`,
`pbs`/`backup`, `docker`, `semaphore`, `dotfiles`/`workstation`.

> **Stap 4 is niet optioneel.** Semaphore draait de playbooks uit Git, niet
> van jouw laptop. Wat niet gecommit is bestaat voor de rest van het systeem
> niet, en een geplande run kan je wijziging terugdraaien.

---

## 4. Als het misgaat

| Wat je ziet | Wat het is |
| --- | --- |
| `Decryption failed` | Vault-wachtwoord ontbreekt of klopt niet. Zie stap 1 |
| `Host key verification failed` | De machine is herbouwd. `ssh-keygen -R <adres>` |
| Een playbook raakt meer hosts dan bedoeld | Je bent `--limit` vergeten |
| De pre-commit hook blokkeert je commit | Er staat een secret in plaintext. Versleutel het met `ansible-vault encrypt <bestand>` |
| CI is rood | `ansible-lint` lokaal draaien; dat is dezelfde controle |

Een half gelukte run is zelden erg. Alles hier mag opnieuw draaien.

---

## 5. Drie regels

1. **Niets met de hand configureren.** Was het de moeite om twee keer te doen,
   dan hoort het in een rol.
2. **Secrets zijn versleuteld.** `inventory/**/vault.yml`, `files/env/*.env` en
   `roles/semaphore/files/config.json`. `bin/check-vaulted` controleert het,
   de pre-commit hook blokkeert het, CI is het vangnet.
3. **Eerst `--check --diff`.** Elke keer.

Openstaand werk: [TODO.md](TODO.md).
