# Dynamic Inventory from Proxmox — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Proxmox the source of truth for guest inventory, replacing the hand-maintained host list in `inventory/hosts.yml`.

**Architecture:** `inventory/` becomes a merged directory: a small static file for the three non-Proxmox hosts plus all group definitions, and a vault-encrypted `community.proxmox.proxmox` plugin config for the eight guests. `ansible_host` is composed from the LXC runtime-interface API and the QEMU guest-agent API, so DHCP containers resolve correctly and nothing needs converting to static.

**Tech Stack:** ansible-core 2.21.4, `community.proxmox` 2.0.0, Proxmox VE API with token auth, ansible-vault (identity `infra`).

**Spec:** `docs/superpowers/specs/2026-09-21-proxmox-dynamic-inventory-design.md`

## Global Constraints

- `ansible-lint` must pass at the **`production`** profile after every task.
- All 14 vaulted files stay encrypted; `bin/check-vaulted` must pass.
- Lint and `--syntax-check` must still pass in a clone with **no vault password** (the `bin/vault-pass-client` placeholder path).
- Facts are reached only via `ansible_facts['x']` — `inject_facts_as_vars = False`.
- FQCN for every module. Every task named, starting with a capital letter.
- Vault identities: `infra` for inventory/Semaphore credentials, `stacks` for `files/env/*.env`.
- **Never run a bare `pveum role modify <roleid>`.** With no `--privs` it sets the privilege list to empty. Always read-modify-write the full list.
- The `AnsibleAutomation` role's 13 current privileges, verbatim, are the baseline that must survive every change:
  `Datastore.AllocateSpace,Datastore.AllocateTemplate,Datastore.Audit,SDN.Use,Sys.Audit,VM.Allocate,VM.Audit,VM.Config.CPU,VM.Config.Disk,VM.Config.Memory,VM.Config.Network,VM.Config.Options,VM.PowerMgmt`

---

## File Structure

| File | Responsibility |
|---|---|
| `roles/proxmox_access/tasks/main.yml` (create) | Idempotent management of the `AnsibleAutomation` role's privileges |
| `roles/proxmox_access/defaults/main.yml` (create) | The required privilege list, as data |
| `roles/proxmox_access/meta/main.yml` (create) | Role metadata, matching the other seven roles |
| `playbooks/proxmox-access.yml` (create) | Entry point for the role |
| `bin/check-inventory-parity` (create) | Compares two inventory sources host-by-host on `ansible_host`; the test for Task 2 and Task 4 |
| `inventory/homelab.proxmox.yml` (create, vault-encrypted) | Plugin config: the eight Proxmox guests |
| `inventory/00-static.yml` (create) | `pve01`, `macmini`, `mbp` and all group definitions |
| `inventory/hosts.yml` (delete, Task 4) | Superseded |
| `ansible.cfg` (modify) | `inventory = inventory/`, `enable_plugins` |
| `inventory/host_vars/docker01.yml` → `docker.yml` (rename) | Follows the guest's Proxmox name |
| `inventory/host_vars/caddy/main.yml` (modify) | 16 `host:` references |
| `playbooks/stacks.yml`, `playbooks/report.yml` (modify) | `hosts:` and `hostvars[]` references |
| `playbooks/templates/report.html.j2`, `docs.html.j2` (modify) | `hostvars['docker01']` references |
| `README.md` (modify) | Inventory section, Semaphore step |

---

### Task 1: Codify the `VM.Monitor` grant

The QEMU agent endpoint returns HTTP 403 without `VM.Monitor`, so four of eight
guests get no `ansible_host`. This is the gate for everything else.

**Files:**
- Create: `roles/proxmox_access/defaults/main.yml`
- Create: `roles/proxmox_access/tasks/main.yml`
- Create: `roles/proxmox_access/meta/main.yml`
- Create: `playbooks/proxmox-access.yml`

**Interfaces:**
- Consumes: `pve_api_*` vars from `inventory/group_vars/proxmox/`.
- Produces: the `AnsibleAutomation` role gains `VM.Monitor`. Task 2's `compose:` fallback depends on this; nothing else does.

- [ ] **Step 1: Capture the current state as the failing test**

Run this and save the output — it is the "before" and must show `403`:

```bash
ansible pve01 -m command -a "pveum role list --output-format json" --become \
  | tail -n +2 \
  | python3 -c "import json,sys; print([r['privs'] for r in json.load(sys.stdin) if r['roleid']=='AnsibleAutomation'][0])"
```

Expected: a 13-item list **without** `VM.Monitor`.

- [ ] **Step 2: Write the role defaults**

`roles/proxmox_access/defaults/main.yml`:

```yaml
---
# The Proxmox role used by the ansible@pve API token, and the full privilege
# list it must have. This list is authoritative: the task below sets exactly
# these privileges, so removing an entry here revokes it on the next run.
proxmox_access_role: AnsibleAutomation

proxmox_access_privileges:
  - Datastore.AllocateSpace
  - Datastore.AllocateTemplate
  - Datastore.Audit
  - SDN.Use
  - Sys.Audit
  - VM.Allocate
  - VM.Audit
  - VM.Config.CPU
  - VM.Config.Disk
  - VM.Config.Memory
  - VM.Config.Network
  - VM.Config.Options
  - VM.PowerMgmt
  # Required by /nodes/{node}/qemu/{vmid}/agent/network-get-interfaces, which
  # the dynamic inventory uses to resolve ansible_host for QEMU guests.
  # Without it that endpoint returns 403 and those hosts get no address.
  - VM.Monitor
```

- [ ] **Step 3: Write the tasks**

`roles/proxmox_access/tasks/main.yml`:

```yaml
---
# Manages the privileges of the Proxmox role behind the ansible@pve API token.
#
# Read-modify-write on the FULL list, deliberately. `pveum role modify <id>`
# with no --privs sets the privilege list to empty, which revokes API access
# for every playbook in this repo. Passing the complete list every time makes
# that failure mode unreachable.
- name: Read current Proxmox roles
  ansible.builtin.command: pveum role list --output-format json
  register: proxmox_access_roles
  changed_when: false
  check_mode: false

- name: Extract the current privileges of the managed role
  ansible.builtin.set_fact:
    proxmox_access_current: >-
      {{ (proxmox_access_roles.stdout | from_json
          | selectattr('roleid', 'eq', proxmox_access_role)
          | map(attribute='privs') | first | default(''))
         | split(',') | select() | sort | list }}

- name: Show the difference this run would apply
  ansible.builtin.debug:
    msg: >-
      {{ proxmox_access_role }}:
      adding {{ (proxmox_access_privileges | sort | difference(proxmox_access_current)) | default([]) }},
      removing {{ (proxmox_access_current | difference(proxmox_access_privileges | sort)) | default([]) }}

- name: Set the role's privileges
  ansible.builtin.command:
    argv:
      - pveum
      - role
      - modify
      - "{{ proxmox_access_role }}"
      - --privs
      - "{{ proxmox_access_privileges | sort | join(',') }}"
  when: proxmox_access_current != (proxmox_access_privileges | sort | list)
  changed_when: true
```

`roles/proxmox_access/meta/main.yml`:

```yaml
---
galaxy_info:
  role_name: proxmox_access
  author: rubenclaes
  description: >-
    Manages the privileges of the Proxmox role behind the ansible@pve API token.
  license: MIT
  min_ansible_version: "2.17"
  platforms:
    - name: Debian
      versions:
        - bookworm
        - trixie
  galaxy_tags:
    - cloud
    - security

# These roles are composed by playbooks, not by role dependencies,
# so the run order stays visible in playbooks/site.yml.
dependencies: []
```

`playbooks/proxmox-access.yml`:

```yaml
---
# Grants the Proxmox API token the privileges this repo needs.
# Run after rebuilding a node, or after changing proxmox_access_privileges.
- name: Proxmox API access
  hosts: proxmox
  roles:
    - proxmox_access
```

- [ ] **Step 4: Dry-run it and read the diff line**

Run: `ansible-playbook playbooks/proxmox-access.yml --check --diff`
Expected: the debug task prints `adding ['VM.Monitor'], removing []`. If it
prints anything under `removing`, **stop** — the defaults list has drifted
from reality and applying it would revoke access.

- [ ] **Step 5: Apply, then verify the agent endpoint**

```bash
ansible-playbook playbooks/proxmox-access.yml
```

Then confirm all four VMs answer, where they previously returned 403:

```bash
ansible pve01 -m shell -a 'for id in 100 101 102 103; do \
  pvesh get /nodes/$(hostname)/qemu/$id/agent/network-get-interfaces --output-format json >/dev/null 2>&1 \
  && echo "$id OK" || echo "$id FAIL"; done' --become
```

Expected: `100 OK`, `101 OK`, `102 OK`, `103 OK`.

- [ ] **Step 6: Verify idempotence**

Run: `ansible-playbook playbooks/proxmox-access.yml`
Expected: `changed=0`. A second run that still reports changed is a bug in the
comparison, not a cosmetic issue — fix it before continuing.

- [ ] **Step 7: Lint and commit**

```bash
ansible-lint
git add roles/proxmox_access playbooks/proxmox-access.yml
git commit -m "Grant VM.Monitor to the Proxmox API role

The dynamic inventory resolves ansible_host for QEMU guests through
/nodes/{node}/qemu/{vmid}/agent/network-get-interfaces, which requires
VM.Monitor. Without it the endpoint returns 403 and those hosts get no
address.

The role sets the full privilege list rather than appending: pveum role
modify with no --privs empties the list and revokes API access for every
playbook here, so the complete list is passed every time."
```

---

### Task 2: Dynamic inventory config and the parity checker

**Files:**
- Create: `bin/check-inventory-parity`
- Create: `inventory/homelab.proxmox.yml` (vault-encrypted with identity `infra`)

**Interfaces:**
- Consumes: `VM.Monitor` from Task 1.
- Produces: `bin/check-inventory-parity OLD NEW` exits 0 when every host in
  OLD exists in NEW with an identical `ansible_host`; Task 4 reuses it.
  `inventory/homelab.proxmox.yml` defines the eight guests, group `linux`
  (seven of them) and group `appliances` (`haos`).

- [ ] **Step 1: Write the parity checker — the test for this task**

`bin/check-inventory-parity`:

```bash
#!/usr/bin/env bash
# Compares two Ansible inventory sources host-by-host on ansible_host.
#
#   bin/check-inventory-parity inventory/hosts.yml inventory/homelab.proxmox.yml
#
# Exits non-zero if any host in OLD is missing from NEW, or resolves to a
# different address. Hosts present only in NEW are reported but not fatal:
# the dynamic source legitimately discovers guests the static file never had.
#
# This is the safety story for the migration. A silent address change would
# point playbooks at the wrong machine.
set -euo pipefail

if [[ $# -ne 2 ]]; then
	echo "usage: $0 OLD_INVENTORY NEW_INVENTORY" >&2
	exit 2
fi

old="$1"
new="$2"

dump() {
	ansible-inventory -i "$1" --list 2>/dev/null |
		python3 -c '
import json, sys
d = json.load(sys.stdin)
hv = d.get("_meta", {}).get("hostvars", {})
for host in sorted(hv):
    print(host, hv[host].get("ansible_host", "-"))
'
}

dump "$old" > /tmp/.parity-old.$$
dump "$new" > /tmp/.parity-new.$$

fail=0
while read -r host addr; do
	newaddr=$(awk -v h="$host" '$1==h {print $2}' /tmp/.parity-new.$$)
	if [[ -z "$newaddr" ]]; then
		printf '  MISSING   %-24s was %s\n' "$host" "$addr" >&2
		fail=1
	elif [[ "$newaddr" != "$addr" ]]; then
		printf '  CHANGED   %-24s %s -> %s\n' "$host" "$addr" "$newaddr" >&2
		fail=1
	else
		printf '  ok        %-24s %s\n' "$host" "$addr"
	fi
done < /tmp/.parity-old.$$

while read -r host addr; do
	grep -q "^${host} " /tmp/.parity-old.$$ || printf '  new       %-24s %s\n' "$host" "$addr"
done < /tmp/.parity-new.$$

rm -f /tmp/.parity-old.$$ /tmp/.parity-new.$$

if [[ $fail -ne 0 ]]; then
	echo "check-inventory-parity: inventories do NOT match." >&2
	exit 1
fi
echo "check-inventory-parity: every host matches."
```

Then: `chmod +x bin/check-inventory-parity`

- [ ] **Step 2: Run it against the old inventory twice, to prove the tool works**

Run: `bin/check-inventory-parity inventory/hosts.yml inventory/hosts.yml`
Expected: every line `ok`, exit 0. A tool that cannot prove a file matches
itself cannot prove anything else.

- [ ] **Step 3: Write the plugin config in plaintext first**

Write `inventory/homelab.proxmox.yml`. The filename **must** end in
`.proxmox.yml` or the plugin will not claim it.

Substitute the real token secret for `REPLACE_ME` — read it with
`ansible-vault view inventory/group_vars/proxmox/vault.yml`.

```yaml
---
# Dynamic inventory: the Proxmox guests.
#
# Encrypted with vault identity `infra`, because it carries the API token.
# Ansible decrypts inventory sources through bin/vault-pass-client, so this
# needs no environment variables.
#
# ansible_host comes from the guest's RUNTIME address, not its configured one:
# two containers run DHCP and their configured net0 says `ip=dhcp`.
plugin: community.proxmox.proxmox
url: https://192.168.0.14:8006
user: ansible@pve
token_id: automation
token_secret: REPLACE_ME
validate_certs: false

want_facts: true
want_proxmox_nodes_ansible_host: false

# Guests only. The PVE node is itself called pve01, so without this the
# plugin would define a second pve01 that collides with the one in
# 00-static.yml. The node's address is static and known; it does not need
# discovering.
exclude_nodes: true

compose:
  # LXC: runtime interfaces. QEMU: guest agent (needs VM.Monitor, Task 1).
  ansible_host: >-
    (proxmox_lxc_interfaces | default([]) | selectattr('name', 'ne', 'lo')
     | map(attribute='inet') | map('regex_replace', '/.*', '') | list | first)
    | default(proxmox_agent_interfaces | default([])
     | selectattr('name', 'ne', 'lo')
     | map(attribute='ip-addresses') | flatten
     | selectattr('ip-address-type', 'eq', 'ipv4')
     | map(attribute='ip-address') | list | first, true)

groups:
  # Everything Ansible manages as a Debian host. haos is excluded: it is
  # Home Assistant OS, with no apt and no standard Python.
  linux: proxmox_name != 'haos'
  appliances: proxmox_name == 'haos'
```

- [ ] **Step 4: Verify it resolves before encrypting**

```bash
ansible-inventory -i inventory/homelab.proxmox.yml --graph
for h in semaphore caddy adguard tailscale pbs docker docker-grafana-stack haos; do
  printf '%-22s %s\n' "$h" \
    "$(ansible-inventory -i inventory/homelab.proxmox.yml --host "$h" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("ansible_host","(none)"))')"
done
```

Expected: **exactly eight hosts, no `pve01` among them** (`exclude_nodes`),
and no address `(none)`. Known-good values —
`semaphore 192.168.0.30`, `caddy 192.168.0.25`, `adguard 192.168.0.29`,
`tailscale 192.168.0.50`. If any QEMU host is `(none)`, Task 1 did not take.

- [ ] **Step 5: Encrypt it**

```bash
ansible-vault encrypt --encrypt-vault-id infra inventory/homelab.proxmox.yml
head -c 33 inventory/homelab.proxmox.yml   # expect: $ANSIBLE_VAULT;1.2;AES256;infra
```

- [ ] **Step 6: Confirm it still resolves while encrypted**

Run Step 4's commands again, unchanged.
Expected: identical output. This is the claim the whole design rests on — a
vault-encrypted plugin config decrypting through `bin/vault-pass-client`.

- [ ] **Step 7: Run the parity check for real**

Run: `bin/check-inventory-parity inventory/hosts.yml inventory/homelab.proxmox.yml`

Expected: `MISSING` for `docker01` and `monitoring01` (they exist under their
Proxmox names — Task 3 fixes this), `MISSING` for `pve01`, `macmini`, `mbp`
(not Proxmox guests — Task 4 adds them), and `ok` for the other five. Record
this output; Task 4 must turn every line into `ok` or `new`.

- [ ] **Step 8: Lint, guard, commit**

```bash
ansible-lint
bin/check-vaulted
git add bin/check-inventory-parity inventory/homelab.proxmox.yml
git commit -m "Add Proxmox dynamic inventory and a parity checker

The plugin config is vault-encrypted under the infra identity: Ansible
decrypts inventory sources through bin/vault-pass-client, so the API token
needs no environment variables and Semaphore already holds the key.

ansible_host is composed from runtime addresses rather than configured ones,
because caddy and adguard run DHCP and their net0 says ip=dhcp.

bin/check-inventory-parity compares two inventories host-by-host and fails on
a missing host or a changed address. Nothing consumes the new source yet."
```

---

### Task 3: Adopt the Proxmox names in the repo

**Files:**
- Rename: `inventory/host_vars/docker01.yml` → `inventory/host_vars/docker.yml`
- Modify: `inventory/hosts.yml`, `inventory/host_vars/caddy/main.yml`, `playbooks/stacks.yml`, `playbooks/report.yml`, `playbooks/templates/report.html.j2`, `playbooks/templates/docs.html.j2`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `docker01` → `docker` and `monitoring01` → `docker-grafana-stack` everywhere. Task 4's parity check depends on this.

- [ ] **Step 1: Capture the rendered Caddyfile as the baseline**

The rename must not change a single byte of Caddy config. Capture first:

```bash
mkdir -p /tmp/rename-check
cat > playbooks/_render.yml <<'EOF'
---
- name: Render Caddyfile for comparison
  hosts: caddy
  connection: local
  gather_facts: false
  tasks:
    - name: Render
      ansible.builtin.template:
        src: "{{ playbook_dir }}/../roles/caddy/templates/Caddyfile.j2"
        dest: /tmp/rename-check/Caddyfile.BEFORE
        mode: "0644"
      delegate_to: localhost
EOF
ansible-playbook playbooks/_render.yml
shasum -a 256 /tmp/rename-check/Caddyfile.BEFORE
```

- [ ] **Step 2: Find every reference**

```bash
grep -rn 'docker01\|monitoring01' --include='*.yml' --include='*.j2' \
  inventory playbooks roles
```

Expected: about 26 hits across 7 files. Two in
`roles/docker_stacks/tasks/main.yml` are **prose in comments**, not
references — update the wording, but they are not functional.

- [ ] **Step 3: Rename the host_vars file**

```bash
git mv inventory/host_vars/docker01.yml inventory/host_vars/docker.yml
```

- [ ] **Step 4: Replace the references**

```bash
grep -rl 'docker01\|monitoring01' --include='*.yml' --include='*.j2' \
  inventory playbooks roles \
  | xargs sed -i '' -e 's/monitoring01/docker-grafana-stack/g' -e 's/docker01/docker/g'
```

Order matters: `monitoring01` is replaced first because neither substring
overlaps, but running `docker01` first would leave `docker-grafana-stack`
untouched and is only safe by luck. Then re-run the grep from Step 2 and
confirm zero hits.

- [ ] **Step 5: Re-render and require a byte-identical Caddyfile**

```bash
sed -i '' 's/Caddyfile.BEFORE/Caddyfile.AFTER/' playbooks/_render.yml
ansible-playbook playbooks/_render.yml
rm -f playbooks/_render.yml
diff -u /tmp/rename-check/Caddyfile.BEFORE /tmp/rename-check/Caddyfile.AFTER \
  && echo "BYTE-IDENTICAL"
```

Expected: `BYTE-IDENTICAL`. Any diff means a `host:` reference now resolves to
a different upstream — a real defect, not a cosmetic one. Stop and fix.

- [ ] **Step 6: Lint, syntax-check, commit**

```bash
ansible-lint
for p in playbooks/*.yml; do ansible-playbook --syntax-check "$p" >/dev/null || echo "FAIL $p"; done
git add -A
git commit -m "Adopt Proxmox guest names in the repo

Proxmox knows these guests as docker and docker-grafana-stack; the repo
called them docker01 and monitoring01. The dynamic inventory uses the
Proxmox name, so the repo moves rather than maintaining a mapping layer
that would live outside git.

Verified behaviour-preserving: the rendered Caddyfile is byte-identical,
so every upstream still resolves to the address it did before."
```

---

### Task 4: Cut over to the directory inventory

**Files:**
- Create: `inventory/00-static.yml`
- Delete: `inventory/hosts.yml`
- Modify: `ansible.cfg`

**Interfaces:**
- Consumes: `bin/check-inventory-parity` (Task 2), the renames (Task 3).
- Produces: `inventory/` as the inventory root. Task 5 documents it.

- [ ] **Step 1: Snapshot the current inventory as the comparison baseline**

`hosts.yml` disappears in this task, so capture it first:

```bash
cp inventory/hosts.yml /tmp/rename-check/hosts.SNAPSHOT.yml
```

- [ ] **Step 2: Write the static file**

`inventory/00-static.yml` — sorts before `homelab.proxmox.yml`, so these load
first:

```yaml
---
# The hosts Proxmox does not know about, and the group definitions the
# dynamic inventory attaches guests to.
#
# Guests are NOT listed here: they come from homelab.proxmox.yml. Adding one
# here would shadow the discovered host.
all:
  children:
    linux:
      vars:
        ansible_user: ansible
        ansible_become: true
      children:
        proxmox:
          hosts:
            pve01: { ansible_host: 192.168.0.14 }

    # Home Assistant OS and anything else that is not a Debian host.
    # Present in inventory and in reports, excluded from the baseline role.
    appliances:
      hosts: {}

    macs:
      hosts:
        macmini: { ansible_host: 192.168.0.26, ansible_user: rubenclaes }
        mbp: { ansible_connection: local }
```

- [ ] **Step 3: Delete the old inventory and point ansible.cfg at the directory**

`hosts.yml` must be deleted, not merely bypassed: once `inventory/` is a
directory source, Ansible parses every file in it.

```bash
git rm inventory/hosts.yml
```

In `ansible.cfg`, replace `inventory = inventory/hosts.yml` with:

```ini
inventory = inventory/
```

and add, after the `[defaults]` block:

```ini
[inventory]
# `auto` hands homelab.proxmox.yml to the Proxmox plugin; yaml handles
# 00-static.yml. Without this the plugin config is parsed as plain YAML
# and fails.
enable_plugins = community.proxmox.proxmox, yaml, ini, auto
```

- [ ] **Step 4: Parity against the snapshot — the gate for this task**

```bash
bin/check-inventory-parity /tmp/rename-check/hosts.SNAPSHOT.yml inventory/
```

Expected: every host `ok`, plus `new` lines for `haos`. **No `MISSING`, no
`CHANGED`.** A `CHANGED` line means a playbook would now target a different
machine — stop.

Note the snapshot still uses the old names, so this also proves Task 3's
rename mapped cleanly onto the same addresses.

- [ ] **Step 5: Confirm every host is reachable**

```bash
ansible all -m ping -o
```

Expected: `SUCCESS` for all 11 (8 guests + pve01 + macmini + mbp), except
`haos`, which is expected to fail — it has no Python. Confirm the failure is
`haos` and nothing else.

- [ ] **Step 6: Confirm no unexpected convergence changes**

```bash
ansible-playbook playbooks/site.yml --check --diff
```

Expected: `failed=0` everywhere, and no host reports changes beyond those
already pending before the migration. `haos` must not appear — it is in
`appliances`, and `site.yml` targets `linux`.

- [ ] **Step 7: Lint, no-secrets check, commit**

```bash
ansible-lint
bin/check-vaulted
env -u ANSIBLE_VAULT_PASSWORD HOME=/tmp/emptyhome ansible-lint   # fresh-clone path
git add -A
git commit -m "Cut over to the Proxmox directory inventory

inventory/ becomes a merged directory: 00-static.yml for the three hosts
Proxmox does not know about plus the group definitions, and the encrypted
homelab.proxmox.yml for the eight guests.

hosts.yml is deleted rather than bypassed: a directory source parses every
file in it, so leaving it would define each guest twice under two names.

Verified: bin/check-inventory-parity reports every previously-known host at
an unchanged address."
```

---

### Task 5: Documentation and the Semaphore repoint

Semaphore's inventory is a `file` entry pointing at `inventory/hosts.yml`,
which no longer exists. Until this is done its runs fail.

**Files:**
- Modify: `README.md`
- Modify: `TODO.md`

**Interfaces:**
- Consumes: the finished migration.
- Produces: nothing code depends on.

- [ ] **Step 1: Update the README layout block**

In `README.md`, replace the `inventory/` lines of the Layout section with:

```text
inventory/
  00-static.yml             pve01, macmini, mbp + group definitions
  homelab.proxmox.yml       vault-encrypted; guests, discovered from Proxmox
  group_vars/all/           settings shared by everything (report.*)
  group_vars/proxmox/       Proxmox API creds (main.yml + vault.yml)
  host_vars/<host>/         per-host settings; vault.yml where secrets apply
```

- [ ] **Step 2: Add an inventory section to the README**

Insert after the Layout section:

````markdown
## Inventory

`inventory/` is a directory Ansible merges, not a single file.

- **`00-static.yml`** — `pve01`, `macmini` and `mbp`, plus the group
  definitions (`linux`, `macs`, `appliances`). These are the hosts Proxmox
  does not know about.
- **`homelab.proxmox.yml`** — the eight Proxmox guests, discovered live.
  Vault-encrypted under the `infra` identity because it holds the API token.

Guests are never listed by hand. Creating one in Proxmox puts it in inventory
on the next run; `ansible_host` comes from its *runtime* address, so the two
DHCP containers resolve correctly.

```bash
ansible-inventory --graph          # what Ansible currently sees
ansible-inventory --host docker    # one host's variables
```

`haos` lands in `appliances` rather than `linux`: it is Home Assistant OS,
with no apt and no standard Python, so `site.yml` skips it while reports
still see it.

The API token needs `VM.Monitor` — without it the guest-agent endpoint
returns 403 and QEMU guests get no address. That privilege is managed by
`playbooks/proxmox-access.yml`, not by hand.

### Checking a change

```bash
bin/check-inventory-parity <old-inventory> inventory/
```

Fails if any host disappears or changes address.
````

- [ ] **Step 3: Repoint Semaphore, by hand**

In the Semaphore UI: **Ansible Homelab → Inventory → `homelab`**, change the
path from `inventory/hosts.yml` to `inventory/`. Save.

Semaphore already holds the `infra` vault key, so it can decrypt the plugin
config; no new credential is needed.

Then run the **Stacks** template and confirm it succeeds.

- [ ] **Step 4: Verify Semaphore's configuration took**

```bash
ansible semaphore -m shell -a "python3 - <<'PY'
import sqlite3
c = sqlite3.connect('file:/var/lib/semaphore/database.sqlite?mode=ro', uri=True)
for r in c.execute('select name, type, inventory from project__inventory'):
    print(r)
PY" --become --become-user=semaphore
```

Expected: `('homelab', 'file', 'inventory/')`.

- [ ] **Step 5: Move the TODO entry and commit**

In `TODO.md`, remove *"Proxmox: turn create-lxc into a list-driven role (all
LXCs as code)"* from **Next projects** only if this work completed it —
it did not, so leave it. Add to **Done**:

```markdown
- [x] Inventory comes from Proxmox; hosts.yml retired
```

```bash
git add README.md TODO.md
git commit -m "Document the Proxmox dynamic inventory

Covers the merged inventory directory, why guests are never listed by hand,
the VM.Monitor prerequisite, and the parity checker. Records that Semaphore's
inventory entry must point at the directory rather than the deleted file."
```

---

## Self-Review

**Spec coverage.** Every section of the spec maps to a task: hybrid layout →
Task 4 Step 2; repo adopts Proxmox names → Task 3; token stays encrypted →
Task 2 Step 5; `haos` included but not baselined → Task 2 Step 3 (`groups:`)
and Task 4 Step 2 (`appliances`); `VM.Monitor` → Task 1; all five spec phases
→ Tasks 1-5 in order; every verification item in the spec appears as a step
that can fail.

**Placeholders.** One deliberate token: `REPLACE_ME` in Task 2 Step 3, with
the command to obtain the real value on the adjacent line. It is not a gap —
a real API secret must not be written into a plan document committed to git.

**Naming consistency.** `proxmox_access_role`, `proxmox_access_privileges`,
`proxmox_access_current` are defined in Task 1 and used only there.
`bin/check-inventory-parity` takes `OLD NEW` in Task 2 and is called with that
signature in Task 4. `appliances` is created by the plugin's `groups:` in
Task 2 and declared in `00-static.yml` in Task 4 — both required, since a
group with no static members still needs declaring for `site.yml` to reason
about it.

**Known ordering hazard.** Task 4 deletes `hosts.yml`, which Task 5's
Semaphore step depends on having happened. Tasks 4 and 5 should run in one
sitting — between them, Semaphore is broken.
