# homelab-ansible

Deze repo beschrijft hoe de homelab eruitziet: welke servers er zijn en wat er
op draait. Ansible leest dat en zet de servers zo.

Uitleg per taak staat op [docs.neodata.be](https://docs.neodata.be).

---

## Eenmalig: je computer klaarzetten

1. Ansible installeren:

   ```bash
   pipx install "ansible-core==2.21.4" "ansible-lint==26.8.0"
   pipx inject ansible-core proxmoxer requests netaddr
   ansible-galaxy collection install -r collections/requirements.yml
   ```

2. De SSH-sleutel kopiëren van de mbp. Maak geen nieuwe: de servers kennen
   alleen deze.

   ```bash
   scp <mac>:'~/.ssh/ansible_ed25519*' ~/.ssh/
   chmod 600 ~/.ssh/ansible_ed25519
   ```

3. De twee wachtwoorden voor de geheimen neerzetten (staan in de
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

Voor je commit: `bin/check-vaulted && ansible-lint`

---

## Waar staat wat

| Map | Wat |
| --- | --- |
| `inventory/` | de servers en hun instellingen (hier pas je het meest aan) |
| `roles/` | per onderdeel de stappen (caddy, adguard, ...) |
| `playbooks/` | wat je uitvoert |
| `files/env/` | versleutelde instellingen van de Docker-apps |
| `docs-site/` | de documentatie |

Iets gewijzigd? Pas dan ook de uitleg aan in `docs-site/content/runbooks/`.
