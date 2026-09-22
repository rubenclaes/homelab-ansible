# homelab-ansible



## 1. Setup

```bash

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

Sleutel echt kwijt? Nieuwe maken en elke host opnieuw bootstrappen, één voor
één, want `ansible` bestaat daar dan niet meer:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/ansible_ed25519 -C "ansible@homelab"
ansible-playbook playbooks/bootstrap.yml --limit <host> -u root -k
```

---

## 2. Wat wil je doen?

| Ik wil...                                  | Doe dit                                                                                          |
| ------------------------------------------ | ------------------------------------------------------------------------------------------------ |
| Alles gelijktrekken                        | `ansible-playbook playbooks/site.yml`                                                            |
| Een nieuwe machine op pve01                | [Runbook: Nieuwe machine](https://docs.neodata.be/technisch/runbooks/nieuwe-guest/)              |
| Een nieuwe Docker-dienst                   | `ansible-playbook playbooks/new-service.yml -e svc_name=... -e svc_port=... -e svc_image=...`    |
| Iets herstellen of een back-up terugzetten | [Runbook: Herstellen](https://docs.neodata.be/technisch/runbooks/disaster-recovery/)             |
| Pakketten updaten                          | [Runbook: Updates](https://docs.neodata.be/technisch/runbooks/updates/)                          |
| Schijfruimte vrijmaken                     | `ansible-playbook playbooks/cleanup.yml` (rapporteert; ruimt pas op met `-e cleanup_apply=true`) |
| Een route toevoegen                        | `caddy_sites` in `inventory/host_vars/caddy/main.yml`, dan `playbooks/caddy.yml`                 |
| Een Tailscale-sleutel voor een pc of NAS   | `ansible-playbook playbooks/tailscale-key.yml -e label=<naam>`                                  |
| Zien of alles gezond is                    | `ansible-playbook playbooks/report.yml`, dan `https://report.neodata.be`                         |
| De documentatiesite bijwerken              | `ansible-playbook playbooks/docs.yml`                                                            |

---

## 3. Hoe je een wijziging doorvoert


```bash
# 1. Wijzig iets in inventory/ of roles/

# 2. Kijk wat het zou doen. Dit verandert niets.
ansible-playbook playbooks/site.yml --check --diff

# 3. Voer het uit
ansible-playbook playbooks/site.yml

```

Handig:

```bash
ansible-playbook playbooks/site.yml --limit docker    # één host
ansible-playbook playbooks/site.yml --tags dns        # één onderdeel
```

Tags: `baseline`, `macos`, `caddy`/`web`, `adguard`/`dns`, `tailscale`/`vpn`,
`pbs`/`backup`, `docker`, `semaphore`, `dotfiles`/`workstation`.
