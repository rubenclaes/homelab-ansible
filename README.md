# homelab-ansible

Deze repo beschrijft hoe de homelab eruitziet: welke servers er zijn en wat er
op draait. Ansible leest dat en zet de servers zo.

Uitleg per taak staat op [docs.neodata.be](https://docs.neodata.be).

---

## Eenmalig: je computer klaarzetten

1. Ansible installeren, met de versies uit `requirements.txt` (dezelfde als CI):

   ```bash
   uv tool install --with-requirements requirements.txt \
     --with-executables-from ansible-lint ansible-core
   ansible-galaxy collection install -r collections/requirements.yml
   ```

   Na een versie-bump in `requirements.txt`: hetzelfde commando met `--force`.

2. De SSH-sleutel kopiëren van de mbp. Maak geen nieuwe: de servers kennen
   alleen deze.

   ```bash
   scp <mac>:'~/.ssh/ansible_ed25519*' ~/.ssh/
   chmod 600 ~/.ssh/ansible_ed25519
   ```

3. De twee wachtwoorden voor de secrets neerzetten (staan in de
   wachtwoordkluis):

   ```bash
   install -m 600 /dev/null ~/.ansible/vault_pass_infra
   install -m 600 /dev/null ~/.ansible/vault_pass_stacks
   $EDITOR ~/.ansible/vault_pass_infra
   $EDITOR ~/.ansible/vault_pass_stacks
   ```

4. De controle vóór elke commit aanzetten:

   ```bash
   git config core.hooksPath .githooks
   ```

5. Testen of het werkt:

   ```bash
   ansible all -m ping
   ```

---

## Dagelijks gebruik

```bash
# Eerst kijken wat er zou veranderen (verandert zelf niets)
ansible-playbook playbooks/site.yml --check --diff

# Alles gelijkzetten
ansible-playbook playbooks/site.yml

# Alleen één server
ansible-playbook playbooks/site.yml --limit docker

# Updates installeren
ansible-playbook playbooks/update.yml
```

Voor je pusht: `hl check`, dezelfde controles als CI (zonder dotfiles: `bin/check-vaulted && ansible-lint`)

---

## Waar staat wat

OpenTofu beslist wat er *bestaat*, Ansible wat er *in* een machine draait.

| Map | Wat |
| --- | --- |
| `inventory/` | de servers en hun instellingen (hier pas je het meest aan); per host een map `host_vars/<host>/` met `main.yml` en `vault.yml` |
| `roles/` | per onderdeel de stappen (caddy, adguard, ...) |
| `playbooks/` | wat je uitvoert; `site.yml` zet alles gelijk |
| `files/` | versleutelde `.env` van de Docker-apps, en de Tailscale-regels |
| `tofu/` | OpenTofu: de machines op Proxmox, Tailscale en Pocket ID |
| `bin/` | hulpscripts (`tofu`, vault-wachtwoorden, `check-vaulted`) |
| `docs-site/` | de documentatie |

Meer uitleg: [Waar staat wat](https://docs.neodata.be/ansible/repo/).

Iets gewijzigd? Pas dan ook de uitleg aan in `docs-site/content/`, op de pagina van het onderwerp (Proxmox, Docker, Netwerk, ...).
