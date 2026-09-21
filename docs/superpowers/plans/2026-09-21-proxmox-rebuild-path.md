# Proxmox Rebuild Path Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Put the configuration of `pve01` and `pbs` under Ansible so the layer beneath the guests can be rebuilt from the repo, and prove the guest rebuild path works by running it.

**Architecture:** Four roles split by blast radius. `proxmox_datacenter` and `proxmox_access` make idempotent API and `pveum` calls and join the nightly converge. `proxmox_network` can end the session and therefore lives behind its own playbook and an explicit flag. The `pbs` role gains datastore and job management. A sixth deliverable, `recovery-drill.yml`, builds and destroys a throwaway container to prove the provisioning path.

**Tech Stack:** Ansible 2.17+, `community.proxmox` 2.0.0 (pinned), `pvesh` and `pveum` on `pve01`, `proxmox-backup-manager` on `pbs`.

**Spec:** [docs/superpowers/specs/2026-09-21-proxmox-rebuild-path-design.md](../specs/2026-09-21-proxmox-rebuild-path-design.md)

## Global Constraints

- **There is no unit test framework here.** `ansible-lint` at the production profile must pass for every task.
- **`changed=0` is NOT a valid test for anything driven by `ansible.builtin.command`.** Ansible skips command tasks entirely under `--check` — they report `skipped` whether their `when` was true or false — so `changed=0` is guaranteed and proves nothing. This was measured, not assumed: Task 1's first implementation transcribed two storages' `content` in the wrong order and still reported `changed=0 skipped=3`.
- **The drift-list pattern is therefore mandatory** for every role here that reconciles through `pvesh`, `pveum` or `proxmox-backup-manager` — Tasks 1, 2, 3 and 4. Each such role must:
  1. accumulate the id of every entry whose declared fields differ from live into a list named `<role>_drift`, using `set_fact`, which runs in check mode;
  2. print that list with `debug` on every run;
  3. end with an `assert` that the list is empty, guarded by `when: <role>_require_clean | default(false) | bool`.

  The acceptance test for those tasks is that assertion passing under
  `ansible-playbook <playbook> --check -e <role>_require_clean=true`, not the
  play recap. A failing assert means the transcription differs from live — fix
  the inventory file, not the role.
- **Where a module implements check mode** — Task 5's `proxmox_node_network` — the `--check` recap is meaningful and `changed=0` is the bar as usual.
- **Transcribe from the API, never from the config file.** `/etc/pve/storage.cfg` and `pvesh get /storage` disagree on list ordering, and the comparison is a string equality. Measured on this node: `local-lvm` is `images,rootdir` while `vm-hdd` is `rootdir,images`. Copy each value from the API output individually; do not assume two entries share an ordering, and do not trust a worked example in this plan over the live output.
- **Reconciliation is additive, never exclusive.** No task may delete a Proxmox object that exists on the host but is absent from inventory. `root@pam` and `rubenclaes@pam` predate this repo and must survive every run.
- **Nothing under `/etc/pve/priv/` is read or copied.** Credentials needed to recreate config come from the `infra` vault.
- **Collections are pinned.** Do not install or upgrade a collection. If a module is missing an option, use `pvesh` or `pveum` and say why in a comment.
- **Comment style:** comments explain *why*, in English, matching the surrounding roles. The README and the docs site are Dutch; code and specs are English.
- **Every commit message ends with:** `Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>`
- **API credentials** are `pve_api_host`, `pve_api_user`, `pve_api_token_id`, `pve_api_token_secret`, defined in `inventory/group_vars/proxmox/main.yml`. API tasks use `delegate_to: localhost`, `become: false`, `validate_certs: false` — the pattern `roles/proxmox_lxc/tasks/main.yml` already uses.

---

### Task 1: `proxmox_datacenter` role, storage only

**Files:**
- Create: `inventory/group_vars/proxmox/storage.yml`
- Create: `roles/proxmox_datacenter/defaults/main.yml`
- Create: `roles/proxmox_datacenter/meta/main.yml`
- Create: `roles/proxmox_datacenter/tasks/main.yml`
- Create: `roles/proxmox_datacenter/tasks/storage.yml`
- Create: `roles/proxmox_datacenter/tasks/storage_entry.yml`
- Create: `playbooks/proxmox-datacenter.yml`
- Modify: `playbooks/site.yml`

**Interfaces:**
- Consumes: SSH to `pve01` as the `ansible` service account with `become`, which `inventory/00-static.yml` already gives the `linux` group. This role needs no API credentials — `pvesh` runs locally on the node, the way `roles/proxmox_access` already drives `pveum`.
- Produces: `pve_storages`, a list of dicts with `id` (the storage ID) and `params` (a flat dict whose keys are the Proxmox API's own field names). Task 2 adds `pve_backup_jobs` in the same shape.

**Why `pvesh` and not `community.proxmox.proxmox_storage`:** the module calls
`GET /storage/{name}` even in check mode, which requires the `Datastore.Allocate`
privilege — the one that lets a token create, modify and **delete** storage
definitions. The `ansible@pve` token does not have it, and granting it widens a
credential that lives in the vault on a laptop and on the Semaphore container.
`pvesh` as root over SSH costs nothing extra and is what the rest of this repo
already does. See the design spec, decision 5.

- [ ] **Step 1: Record the live state you are transcribing against**

```bash
ansible pve01 -m ansible.builtin.command -a "pvesh get /storage --output-format json"
```

Expected: four entries — `local` (dir), `local-lvm` (lvmthin), `vm-hdd` (zfspool), `pbs` (pbs).

Read the output carefully, because three things in it will cost you a
`changed=0` run if you transcribe from `/etc/pve/storage.cfg` instead:

1. `content` comes back in the API's own order, not the config file's.
   `local` returns `"iso,import,vztmpl"` where the file says
   `import,vztmpl,iso`. Use the API's order.
2. `shared` is an integer, not a string or a bool.
3. `digest` appears on every entry. It is a checksum of the whole
   `storage.cfg`, not a property of one storage. Never declare it.

- [ ] **Step 2: Write the inventory transcription**

Create `inventory/group_vars/proxmox/storage.yml`:

```yaml
---
# Storage definitions for pve01, transcribed from `pvesh get /storage`.
#
# `params` keys are the Proxmox API's own names, passed through unchanged, and
# their VALUE TYPES matter: the reconcile compares a merged dict against the
# live one, so a string "0" where the API returns an integer 0 reports a
# difference on every run, forever. `content` must carry the API's ordering,
# which is not the ordering /etc/pve/storage.cfg shows.
#
# `digest` is never declared. It is a checksum of the whole storage.cfg and
# changes whenever any storage does, so declaring it would mean permanent
# drift on every entry.
pve_storages:
  - id: local
    params:
      type: dir
      path: /var/lib/vz
      content: iso,import,vztmpl
      shared: 0

  - id: local-lvm
    params:
      type: lvmthin
      vgname: pve
      thinpool: data
      content: rootdir,images

  - id: vm-hdd
    params:
      type: zfspool
      pool: vm-hdd
      mountpoint: /vm-hdd
      nodes: pve01
      content: rootdir,images

# The `pbs` storage is deliberately absent, and this is a real gap rather than
# a tidy exclusion.
#
# Its API representation carries an `encryption-key` field. Telling a key
# apart from a key's fingerprint requires reading /etc/pve/priv/storage/,
# which the spec puts out of bounds, so the value is not safe to commit on the
# assumption that it is harmless. Recreating the entry on a rebuilt node also
# needs the pve@pbs password, which lives only in the PBS UI.
#
# Consequence: after a rebuild of pve01 this storage is restored by hand, and
# the backups in it are unreadable without the encryption key. That key must
# be exported once with `proxmox-backup-client key show` and kept outside this
# repo and outside the building. See the design spec, Risk 1.
```

- [ ] **Step 3: Write the role**

`roles/proxmox_datacenter/defaults/main.yml`:

```yaml
---
# The storage and backup-job lists are inventory data, not role settings: they
# describe this estate. They live in inventory/group_vars/proxmox/ as
# `pve_storages` and `pve_backup_jobs`, and the tasks read them with
# `| default([])` so a host without them skips rather than failing.
#
# Shape of a pve_storages entry:
#   id:      local                     required, the storage ID
#   params:  {}                        required, Proxmox API field names
#
# Shape of a pve_backup_jobs entry:
#   id:      backup-e6cc3e8b-ac39      required, the Proxmox-generated job ID
#   params:  {}                        required, Proxmox API field names
#
# This file is comments only, deliberately. Defaulting either list here would
# let a typo'd inventory filename resolve to an empty list and report success
# while managing nothing.
```

`roles/proxmox_datacenter/meta/main.yml`:

```yaml
---
galaxy_info:
  role_name: proxmox_datacenter
  author: rubenclaes
  description: >-
    Datacenter-level Proxmox configuration: storage definitions and backup jobs.
  license: MIT
  min_ansible_version: "2.17"
  platforms:
    - name: Debian
      versions:
        - bookworm
        - trixie
  galaxy_tags:
    - system
    - virtualization

# These roles are composed by playbooks, not by role dependencies,
# so the run order stays visible in playbooks/site.yml.
dependencies: []
```

`roles/proxmox_datacenter/tasks/main.yml`:

```yaml
---
- name: Storage definitions
  ansible.builtin.import_tasks: storage.yml
```

`roles/proxmox_datacenter/tasks/storage.yml`:

```yaml
---
# pvesh on the node, not community.proxmox.proxmox_storage. The module calls
# GET /storage/{name} even in check mode, which needs Datastore.Allocate - the
# privilege that lets a token create, modify and DELETE storage definitions.
# That token's secret sits in the infra vault on a laptop and on the Semaphore
# container, and widening it to save a module call is the wrong trade when
# pvesh as root already works. See the design spec, decision 5.
- name: Read the current storage definitions
  ansible.builtin.command: pvesh get /storage --output-format json
  register: proxmox_datacenter_storage_raw
  changed_when: false
  # Must run under --check too: without it stdout is undefined and the
  # comparison below fails instead of reporting no drift.
  check_mode: false

- name: Reconcile each declared storage
  ansible.builtin.include_tasks: storage_entry.yml
  loop: "{{ pve_storages | default([]) }}"
  loop_control:
    loop_var: storage
    label: "{{ storage.id }}"
```

`roles/proxmox_datacenter/tasks/storage_entry.yml`:

```yaml
---
- name: Find the live definition of {{ storage.id }}
  ansible.builtin.set_fact:
    proxmox_datacenter_storage_live: >-
      {{ proxmox_datacenter_storage_raw.stdout | from_json
         | selectattr('storage', 'eq', storage.id) | list | first | default({}) }}

# Merging the declared params into the live entry and comparing against the
# live entry answers "is every declared field already correct?" in one
# expression, and treats a missing key exactly like a wrong value.
- name: Decide whether {{ storage.id }} needs updating
  ansible.builtin.set_fact:
    proxmox_datacenter_storage_matches: >-
      {{ (proxmox_datacenter_storage_live | combine(storage.params))
         == proxmox_datacenter_storage_live }}

- name: Refuse to touch a storage that does not exist
  ansible.builtin.assert:
    that: proxmox_datacenter_storage_live | length > 0
    fail_msg: >-
      No storage named {{ storage.id }} exists on this node. This role updates
      storage definitions, it does not create them: creating one points
      Proxmox at a disk, a pool or a remote server, which is a decision with
      data behind it and not one a converge run should take on its own. Create
      it once, then transcribe it into pve_storages.
    success_msg: "{{ storage.id }} exists"

# `type` is compared but never sent. It is the one field pvesh set rejects -
# a storage's type is fixed at creation - and leaving it in the comparison is
# what catches a transcription that named the wrong storage.
- name: Apply the declared fields to {{ storage.id }}
  ansible.builtin.command:
    argv: >-
      {{ ['pvesh', 'set', '/storage/' ~ storage.id]
         + (storage.params | dict2items | rejectattr('key', 'eq', 'type')
            | map(attribute='key') | map('regex_replace', '^', '--') | list
            | zip(storage.params | dict2items | rejectattr('key', 'eq', 'type')
                  | map(attribute='value') | map('string') | list)
            | flatten | list) }}
  when: not proxmox_datacenter_storage_matches
  changed_when: true
```

- [ ] **Step 4: Write the playbook and wire it into site.yml**

`playbooks/proxmox-datacenter.yml`:

```yaml
---
# Datacenter-level configuration for pve01: storage definitions and backup
# jobs. Safe to run repeatedly - every task is additive and nothing here
# removes a storage, a job, or the data behind them.
#
#   ansible-playbook playbooks/proxmox-datacenter.yml
#
# Node-level networking is deliberately NOT here. It can make the node
# unreachable, so it lives in playbooks/proxmox-network.yml behind a flag.
- name: Proxmox datacenter configuration
  hosts: proxmox
  gather_facts: false
  roles:
    - proxmox_datacenter
  tags: [proxmox, datacenter]
```

In `playbooks/site.yml`, add after the `Backup server` import:

```yaml
- name: Proxmox datacenter configuration
  ansible.builtin.import_playbook: proxmox-datacenter.yml
```

- [ ] **Step 5: Run the test**

```bash
ansible-lint playbooks/proxmox-datacenter.yml roles/proxmox_datacenter
ansible-playbook playbooks/proxmox-datacenter.yml --check --diff
```

Expected: lint passes at the production profile, and the play recap reports
`changed=0`.

If `changed` is non-zero, the debug output names the storage. Your
transcription differs from the live node — fix `storage.yml`, not the role.
The likely culprits are the three traps in Step 1: `content` ordering,
`shared` as an integer, and a stray `digest`.

- [ ] **Step 6: Commit**

```bash
git add inventory/group_vars/proxmox/storage.yml roles/proxmox_datacenter \
        playbooks/proxmox-datacenter.yml playbooks/site.yml
git commit -m "$(cat <<'MSG'
Bring pve01 storage definitions under Ansible

Through pvesh on the node rather than community.proxmox.proxmox_storage.
The module calls GET /storage/{name} even in check mode, which needs
Datastore.Allocate - the privilege to create, modify and DELETE storage
definitions. The ansible@pve token does not have it, and granting it
would widen a credential that sits in the vault on a laptop and on the
Semaphore container, to save one module call.

Going through pvesh also recovers what the module could not express:
local-lvm has no lvmthin type in proxmox_storage, and zfspool_options
has no mountpoint.

The pbs storage stays unmanaged. Its API form carries an encryption-key
field, and telling a key from a fingerprint means reading /etc/pve/priv,
which is out of bounds here.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
MSG
)"
```

---

### Task 2: Backup jobs, through `pvesh`

**Files:**
- Create: `inventory/group_vars/proxmox/backup.yml`
- Create: `roles/proxmox_datacenter/tasks/backup_jobs.yml`
- Create: `roles/proxmox_datacenter/tasks/backup_job.yml`
- Modify: `roles/proxmox_datacenter/tasks/main.yml`

**Interfaces:**
- Consumes: the `proxmox_datacenter` role skeleton from Task 1.
- Produces: `pve_backup_jobs`, a list of dicts with keys `id` (string, the Proxmox job ID) and `params` (flat dict, keys named exactly as the Proxmox API names them).

- [ ] **Step 1: Record the live state, including exact value types**

```bash
ansible pve01 -m ansible.builtin.command -a "pvesh get /cluster/backup --output-format json"
```

Read the types carefully. The comparison in Step 3 is an equality test on a merged dict, so a declared `"1"` against a live `1` is a permanent false difference. Transcribe integers as integers and strings as strings, exactly as this output shows them.

- [ ] **Step 2: Write the inventory transcription**

Create `inventory/group_vars/proxmox/backup.yml`:

```yaml
---
# Backup jobs on pve01, transcribed from `pvesh get /cluster/backup`.
#
# `params` keys are the Proxmox API's own names, passed through unchanged.
# That is deliberate: a translation layer here would mean maintaining a
# mapping that drifts from the API every time Proxmox adds a field.
#
# Value TYPES matter. The reconcile in backup_job.yml compares a merged dict
# against the live one, so a string "1" where the API returns an integer 1
# reports a difference on every run, forever.
#
# Two corrections to the live state are made here deliberately:
#   - vmid 109 is dropped from the weekly job. That guest no longer exists,
#     so the job has been failing on it.
#   - The orphaned PBS groups ct/109 and vm/110 are NOT touched. No role here
#     deletes anything; remove them by hand in the PBS UI.
pve_backup_jobs:
  - id: backup-e6cc3e8b-ac39
    params:
      schedule: "sun 01:00"
      storage: local
      vmid: "101,102,103,104,106,107,108"
      mode: snapshot
      compress: zstd
      enabled: 1
      # {{guestname}} is a Proxmox template, not a Jinja one. Without the raw
      # block Ansible tries to resolve it and fails with an undefined variable.
      notes-template: "{% raw %}{{guestname}}{% endraw %}"
      notification-mode: notification-system

  - id: backup-a6c792f3-ad6c
    params:
      schedule: "02:30"
      storage: pbs
      all: 1
      exclude: "100"
      mode: snapshot
      enabled: 1
      notes-template: "{% raw %}{{guestname}}{% endraw %}"
      notification-mode: notification-system
```

- [ ] **Step 3: Write the reconcile**

`roles/proxmox_datacenter/tasks/backup_jobs.yml`:

```yaml
---
# Backup jobs go through pvesh, not through community.proxmox. The collection
# has proxmox_backup_schedule, but its options are only vm_name, vm_id,
# backup_id and state: it moves a guest in or out of an EXISTING job and
# cannot define one. Using it for the vmid list while using pvesh for the
# schedule would leave two mechanisms owning one object.
- name: Read the current backup jobs
  ansible.builtin.command: pvesh get /cluster/backup --output-format json
  register: proxmox_datacenter_jobs_raw
  changed_when: false
  # Must run under --check too: without it stdout is undefined and the
  # comparison below fails instead of reporting no drift.
  check_mode: false

- name: Reconcile each declared backup job
  ansible.builtin.include_tasks: backup_job.yml
  loop: "{{ pve_backup_jobs | default([]) }}"
  loop_control:
    loop_var: job
    label: "{{ job.id }}"
```

`roles/proxmox_datacenter/tasks/backup_job.yml`:

```yaml
---
- name: Find the live definition of {{ job.id }}
  ansible.builtin.set_fact:
    proxmox_datacenter_job_live: >-
      {{ proxmox_datacenter_jobs_raw.stdout | from_json
         | selectattr('id', 'eq', job.id) | list | first | default({}) }}

# Merging the declared params into the live job and comparing against the live
# job answers "is every declared field already correct?" in one expression,
# and handles a missing key the same way it handles a wrong value.
- name: Decide whether {{ job.id }} needs updating
  ansible.builtin.set_fact:
    proxmox_datacenter_job_matches: >-
      {{ (proxmox_datacenter_job_live | combine(job.params)) == proxmox_datacenter_job_live }}

- name: Show what would change for {{ job.id }}
  ansible.builtin.debug:
    msg: >-
      {{ job.id }}:
      {{ 'matches' if proxmox_datacenter_job_matches else
         'differs in ' ~ (job.params | dict2items
           | rejectattr('key', 'in', proxmox_datacenter_job_live.keys() | list)
           | map(attribute='key') | list | join(', ') | default('a declared value', true)) }}

- name: Refuse to touch a job that does not exist
  ansible.builtin.assert:
    that: proxmox_datacenter_job_live | length > 0
    fail_msg: >-
      No backup job with id {{ job.id }} exists on this node. This role
      updates jobs, it does not create them: a job ID is generated by Proxmox
      and inventing one here would produce a second, competing job. Create it
      once in the UI, then transcribe its ID into pve_backup_jobs.
    success_msg: "{{ job.id }} exists"

- name: Apply the declared fields to {{ job.id }}
  ansible.builtin.command:
    argv: >-
      {{ ['pvesh', 'set', '/cluster/backup/' ~ job.id]
         + (job.params | dict2items
            | map(attribute='key') | map('regex_replace', '^', '--') | list
            | zip(job.params | dict2items | map(attribute='value') | map('string') | list)
            | flatten | list) }}
  when: not proxmox_datacenter_job_matches
  changed_when: true
```

- [ ] **Step 4: Include it from the role**

Replace `roles/proxmox_datacenter/tasks/main.yml` with:

```yaml
---
- name: Storage definitions
  ansible.builtin.import_tasks: storage.yml

- name: Backup jobs
  ansible.builtin.import_tasks: backup_jobs.yml
```

- [ ] **Step 5: Run the test**

```bash
ansible-lint roles/proxmox_datacenter
ansible-playbook playbooks/proxmox-datacenter.yml --check --diff
```

Expected: lint passes. The recap reports exactly one change — the weekly job, because you removed vmid 109 from it. Every other task reports `ok`.

That one change is the point of this task. Read the debug line to confirm it names the job you expect before you apply it.

- [ ] **Step 6: Apply, then verify against the node**

```bash
ansible-playbook playbooks/proxmox-datacenter.yml
ansible pve01 -m ansible.builtin.command -a "pvesh get /cluster/backup --output-format json"
```

Expected: the weekly job's `vmid` no longer contains `109`. Re-running `--check` now reports `changed=0`.

- [ ] **Step 7: Commit**

```bash
git add inventory/group_vars/proxmox/backup.yml roles/proxmox_datacenter
git commit -m "$(cat <<'MSG'
Declare the pve01 backup jobs in inventory

Through pvesh rather than community.proxmox: proxmox_backup_schedule
takes only vm_name/vm_id/backup_id/state and cannot define a job.

Drops vmid 109 from the weekly job. That guest no longer exists, so the
job has been failing on it with nobody watching. The orphaned PBS groups
ct/109 and vm/110 still need removing by hand - no role here deletes.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
MSG
)"
```

---

### Task 3: Users, groups and ACLs in `proxmox_access`

**Files:**
- Create: `inventory/group_vars/proxmox/access.yml`
- Create: `roles/proxmox_access/tasks/users.yml`
- Modify: `roles/proxmox_access/tasks/main.yml`
- Modify: `playbooks/site.yml`

**Interfaces:**
- Consumes: `proxmox_access_role` and `proxmox_access_privileges` from the existing `roles/proxmox_access/defaults/main.yml`. Do not change them.
- Produces: `pve_users` (list of dicts with `userid`, optional `comment`, `firstname`, `lastname`, `email`) and `pve_acls` (list of dicts with `path`, `roleid`, `type`, `ugid`).

- [ ] **Step 1: Record the live state**

```bash
ansible pve01 -m ansible.builtin.command -a "pveum user list --output-format json"
ansible pve01 -m ansible.builtin.command -a "pveum acl list --output-format json"
```

Expected: users `ansible@pve`, `root@pam`, `rubenclaes@pam`; one ACL granting `AnsibleAutomation` on `/` to `ansible@pve`.

- [ ] **Step 2: Write the inventory transcription**

Create `inventory/group_vars/proxmox/access.yml`:

```yaml
---
# Proxmox users and ACLs, transcribed from `pveum user list` and
# `pveum acl list`.
#
# ADDITIVE ONLY. Nothing here removes a user or an ACL. root@pam and
# rubenclaes@pam are PAM accounts that predate this repo, and an exclusive
# reconcile would delete them and lock the estate out of its own hypervisor.
#
# The PAM users are listed anyway, without passwords, so a rebuilt node gets
# them back. Their credentials live in /etc/pve/priv/shadow.cfg, which is out
# of scope: set them by hand after a rebuild.
#
# The AnsibleAutomation role itself is NOT here. It is managed by
# proxmox_access_privileges in this role's defaults, which carries a guard
# that refuses to revoke a privilege - see tasks/main.yml.
pve_users:
  - userid: ansible@pve
    comment: Ansible automation

  - userid: root@pam
    email: rubenclaes@outlook.com

  - userid: rubenclaes@pam
    firstname: Ruben
    lastname: Claes
    email: rubenclaes@outlook.com

pve_acls:
  - path: /
    roleid: AnsibleAutomation
    type: user
    ugid: ansible@pve
```

- [ ] **Step 3: Write the tasks**

Create `roles/proxmox_access/tasks/users.yml`:

```yaml
---
# pveum rather than community.proxmox.proxmox_user, to match the rest of this
# role. tasks/main.yml already drives pveum directly because it needs a guard
# the module does not offer, and mixing a module with a CLI inside one role
# means two failure modes and two idempotency stories for one object.
- name: Read the current Proxmox users
  ansible.builtin.command: pveum user list --output-format json
  register: proxmox_access_users
  changed_when: false
  check_mode: false

- name: Create users that do not exist yet
  ansible.builtin.command:
    argv: >-
      {{ ['pveum', 'user', 'add', item.userid]
         + (['--comment', item.comment] if item.comment is defined else [])
         + (['--firstname', item.firstname] if item.firstname is defined else [])
         + (['--lastname', item.lastname] if item.lastname is defined else [])
         + (['--email', item.email] if item.email is defined else []) }}
  loop: "{{ pve_users | default([]) }}"
  loop_control:
    label: "{{ item.userid }}"
  when: item.userid not in (proxmox_access_users.stdout | from_json | map(attribute='userid') | list)
  changed_when: true

- name: Read the current ACLs
  ansible.builtin.command: pveum acl list --output-format json
  register: proxmox_access_acls
  changed_when: false
  check_mode: false

# proxmox_access_acl declares check_mode: support: none, so this stays on
# pveum as well - and the comparison below is what makes --check meaningful
# for ACLs anyway, since it is a read plus a conditional.
- name: Grant ACLs that are not in place yet
  ansible.builtin.command:
    argv:
      - pveum
      - acl
      - modify
      - "{{ item.path }}"
      - "--roles"
      - "{{ item.roleid }}"
      - "--{{ item.type }}s"
      - "{{ item.ugid }}"
  loop: "{{ pve_acls | default([]) }}"
  loop_control:
    label: "{{ item.path }} -> {{ item.ugid }} ({{ item.roleid }})"
  when: >-
    (proxmox_access_acls.stdout | from_json
     | selectattr('path', 'eq', item.path)
     | selectattr('roleid', 'eq', item.roleid)
     | selectattr('ugid', 'eq', item.ugid) | list | length) == 0
  changed_when: true
```

- [ ] **Step 4: Include it, after the role privileges**

Append to `roles/proxmox_access/tasks/main.yml`:

```yaml

- name: Users and ACLs
  ansible.builtin.import_tasks: users.yml
```

- [ ] **Step 5: Wire the playbook into site.yml**

`proxmox-access.yml` is currently in neither `site.yml` nor its documented list of hand-run playbooks. Add it after the datacenter import from Task 1:

```yaml
- name: Proxmox API access
  ansible.builtin.import_playbook: proxmox-access.yml
```

Then update the comment block at the top of `site.yml`. It lists what is deliberately excluded; `proxmox-access.yml` no longer belongs in that category, and nothing needs removing from the list because it was never in it. Add a line to the play list explaining the addition is safe:

```yaml
# Deliberately NOT included (run these by hand, they provision or reboot):
#   proxmox-lxcs.yml       creates missing LXC containers
#   proxmox-network.yml    can make the hypervisor unreachable
#   proxmox-autostart.yml  flips onboot on every guest
#   bootstrap.yml          first-contact root login, see README
#   update.yml             package upgrades and reboots
#   report.yml             read-only, but slow; scheduled separately
```

- [ ] **Step 6: Run the test**

```bash
ansible-lint playbooks/proxmox-access.yml roles/proxmox_access
ansible-playbook playbooks/proxmox-access.yml --check
```

Expected: lint passes, recap reports `changed=0`. Every user and ACL already exists, so every conditional is false.

- [ ] **Step 7: Verify against the node, since --check proves less here**

```bash
ansible-playbook playbooks/proxmox-access.yml
ansible pve01 -m ansible.builtin.command -a "pveum acl list --output-format json"
```

Expected: unchanged output, still exactly one ACL. If a second ACL appeared, the `when` comparison in Step 3 is wrong — fix the comparison, then remove the duplicate by hand with `pveum acl delete`.

- [ ] **Step 8: Commit**

```bash
git add inventory/group_vars/proxmox/access.yml roles/proxmox_access playbooks/site.yml
git commit -m "$(cat <<'MSG'
Declare Proxmox users and ACLs, and put access in the converge

Additive only: root@pam and rubenclaes@pam predate this repo and an
exclusive reconcile would delete them and lock the estate out.

proxmox-access.yml was in neither site.yml nor the hand-run list. Its
tasks are idempotent, so it joins the converge - a behaviour change to
the nightly run, called out rather than slipped in.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
MSG
)"
```

---

### Task 4: PBS datastore, prune and verify jobs

**Files:**
- Modify: `inventory/host_vars/pbs/main.yml`
- Create: `roles/pbs/tasks/config.yml`
- Modify: `roles/pbs/tasks/main.yml`

**Interfaces:**
- Consumes: nothing from earlier tasks. This runs on `pbs`, not through the PVE API.
- Produces: `pbs_datastores`, `pbs_prune_jobs`, `pbs_verify_jobs` — each a list of dicts whose keys match `proxmox-backup-manager`'s long flags with `-` replaced by `_`.

- [ ] **Step 1: Record the live state**

```bash
ansible pbs -m ansible.builtin.shell -a "proxmox-backup-manager datastore list --output-format json; proxmox-backup-manager prune-job list --output-format json; proxmox-backup-manager verify-job list --output-format json"
```

Expected: datastore `store1` at `/mnt/datastore/store1` with `gc-schedule: daily`; prune job `s-b173aef0-8cbf` with `keep-last: 7`, daily; verify job `v-5885e27b-efbc`, `sat 05:00`, `outdated-after: 30`.

- [ ] **Step 2: Write the inventory transcription**

Append to `inventory/host_vars/pbs/main.yml`:

```yaml

# Datastore and job configuration, transcribed from
# `proxmox-backup-manager <thing> list --output-format json`.
#
# ADDITIVE ONLY, like everything else in this repo's Proxmox layer. A
# datastore is a directory full of backups; nothing here removes one.
#
# keep-last: 7 against a daily schedule is one week of history, and the
# PVE-side storage entry says `prune-backups keep-all=1`, which leaves all
# pruning to this side. Both are transcribed as they are. Whether one week is
# enough is a decision to take deliberately, not to change here by accident.
pbs_datastores:
  - name: store1
    path: /mnt/datastore/store1
    gc_schedule: daily

pbs_prune_jobs:
  - id: s-b173aef0-8cbf
    store: store1
    schedule: daily
    keep_last: 7

pbs_verify_jobs:
  - id: v-5885e27b-efbc
    store: store1
    schedule: sat 05:00
    outdated_after: 30
    ignore_verified: true
```

- [ ] **Step 3: Write the tasks**

Create `roles/pbs/tasks/config.yml`:

```yaml
---
# No Ansible module covers PBS, so this is proxmox-backup-manager wrapped for
# idempotency: list current state as JSON, compare against what is declared,
# and act only on a difference. changed_when comes from that comparison, never
# from the command's exit code - `datastore create` on an existing store fails
# rather than no-ops, so a bare command would report changed on every run and
# fail on the second.
- name: Read the current PBS datastores
  ansible.builtin.command: proxmox-backup-manager datastore list --output-format json
  register: pbs_datastores_current
  changed_when: false
  check_mode: false

- name: Create datastores that do not exist yet
  ansible.builtin.command:
    argv:
      - proxmox-backup-manager
      - datastore
      - create
      - "{{ item.name }}"
      - "{{ item.path }}"
      - --gc-schedule
      - "{{ item.gc_schedule }}"
  loop: "{{ pbs_datastores | default([]) }}"
  loop_control:
    label: "{{ item.name }}"
  when: item.name not in (pbs_datastores_current.stdout | from_json | map(attribute='name') | list)
  changed_when: true

- name: Read the current prune jobs
  ansible.builtin.command: proxmox-backup-manager prune-job list --output-format json
  register: pbs_prune_current
  changed_when: false
  check_mode: false

- name: Create prune jobs that do not exist yet
  ansible.builtin.command:
    argv:
      - proxmox-backup-manager
      - prune-job
      - create
      - "{{ item.id }}"
      - --store
      - "{{ item.store }}"
      - --schedule
      - "{{ item.schedule }}"
      - --keep-last
      - "{{ item.keep_last }}"
  loop: "{{ pbs_prune_jobs | default([]) }}"
  loop_control:
    label: "{{ item.id }}"
  when: item.id not in (pbs_prune_current.stdout | from_json | map(attribute='id') | list)
  changed_when: true

- name: Read the current verify jobs
  ansible.builtin.command: proxmox-backup-manager verify-job list --output-format json
  register: pbs_verify_current
  changed_when: false
  check_mode: false

- name: Create verify jobs that do not exist yet
  ansible.builtin.command:
    argv:
      - proxmox-backup-manager
      - verify-job
      - create
      - "{{ item.id }}"
      - --store
      - "{{ item.store }}"
      - --schedule
      - "{{ item.schedule }}"
      - --outdated-after
      - "{{ item.outdated_after }}"
      - --ignore-verified
      - "{{ item.ignore_verified | string | lower }}"
  loop: "{{ pbs_verify_jobs | default([]) }}"
  loop_control:
    label: "{{ item.id }}"
  when: item.id not in (pbs_verify_current.stdout | from_json | map(attribute='id') | list)
  changed_when: true
```

- [ ] **Step 4: Rewrite the role's header and include the new tasks**

The comment at the top of `roles/pbs/tasks/main.yml` currently says the datastore and its jobs are deliberately NOT managed. That is now false. Replace that comment block with:

```yaml
---
# Installs Proxmox Backup Server and declares its datastore and jobs.
#
# The datastore and its prune and verify jobs WERE deliberately unmanaged
# here, on the grounds that recreating them from a playbook means fighting the
# appliance for ownership of its own state. That reasoning was reversed on
# 2026-09-21: it holds for large hand-tuned runtime state like
# AdGuardHome.yaml, but not for one datastore and two jobs that are small,
# stable, and worthless to reconstruct by hand during a rebuild. See
# docs/superpowers/specs/2026-09-21-proxmox-rebuild-path-design.md, decision 1.
#
# API tokens remain unmanaged. They are secrets, and nothing in this repo
# reads /etc/pve/priv or its PBS equivalent.
```

Append to the end of `roles/pbs/tasks/main.yml`:

```yaml

- name: Datastore and job configuration
  ansible.builtin.import_tasks: config.yml
```

- [ ] **Step 5: Run the test**

```bash
ansible-lint roles/pbs playbooks/pbs.yml
ansible-playbook playbooks/pbs.yml --check
```

Expected: lint passes, recap reports `changed=0`. The datastore and both jobs already exist, so every `when` is false.

- [ ] **Step 6: Commit**

```bash
git add inventory/host_vars/pbs/main.yml roles/pbs
git commit -m "$(cat <<'MSG'
Declare the PBS datastore and its prune and verify jobs

Reverses this role's stated position that the datastore is UI state. The
reasoning still holds for AdGuardHome.yaml; it does not hold for one
datastore and two jobs you would otherwise rebuild from memory.

Additive only - nothing here removes a datastore, which is a directory
full of backups.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
MSG
)"
```

---

### Task 5: `proxmox_network`, behind a flag and a dead-man switch

**Files:**
- Create: `inventory/group_vars/proxmox/network.yml`
- Create: `roles/proxmox_network/defaults/main.yml`
- Create: `roles/proxmox_network/meta/main.yml`
- Create: `roles/proxmox_network/tasks/main.yml`
- Create: `roles/proxmox_network/tasks/apply.yml`
- Create: `playbooks/proxmox-network.yml`

**Interfaces:**
- Consumes: the same API credentials as Task 1.
- Produces: `pve_node_interfaces`, a list of dicts with `iface`, `iface_type`, `cidr`, optional `gateway`, `bridge_ports`, `autostart`, `comments`.

**Read this before writing anything.** Ansible reaches `pve01` on `192.168.0.14`, which is `vmbr1`. The default gateway is on `vmbr0` (`192.168.0.10`). A change that breaks either bridge ends the session, and the node has no console short of physical access. The whole shape of this task exists because of that.

- [ ] **Step 1: Record the live state**

```bash
ansible pve01 -m ansible.builtin.command -a "cat /etc/network/interfaces"
```

Expected: `vmbr0` static `192.168.0.10/24` with gateway `192.168.0.1` and `bridge-ports enp3s0`; `vmbr1` static `192.168.0.14/24` with `bridge-ports nic0` and no gateway.

- [ ] **Step 2: Write the inventory transcription**

Create `inventory/group_vars/proxmox/network.yml`:

```yaml
---
# Node-level bridges on pve01, transcribed from /etc/network/interfaces.
#
# READ THIS BEFORE CHANGING A VALUE HERE. Ansible reaches this node on
# 192.168.0.14, which is vmbr1. The default route is on vmbr0. A wrong value
# in this file does not produce a failed task - it produces an unreachable
# hypervisor and a trip to wherever the machine physically is.
#
# Writing these values only stages them in /etc/network/interfaces.new.
# Applying them is a separate, flagged step: see playbooks/proxmox-network.yml.
#
# The physical ports enp3s0 and nic0 are not declared. They are `iface ... inet
# manual` entries with no configuration, and the bridges reference them by
# name; a rebuilt node with different NIC names needs this file edited anyway.
pve_node_interfaces:
  - iface: vmbr0
    iface_type: bridge
    cidr: 192.168.0.10/24
    gateway: 192.168.0.1
    bridge_ports: enp3s0
    autostart: true
    comments: "2,5 gbe"

  - iface: vmbr1
    iface_type: bridge
    cidr: 192.168.0.14/24
    bridge_ports: nic0
    autostart: true
    comments: "1 gbe"
```

- [ ] **Step 3: Write the role**

`roles/proxmox_network/defaults/main.yml`:

```yaml
---
# The interface list is inventory data and lives in
# inventory/group_vars/proxmox/network.yml as `pve_node_interfaces`.
#
# Applying a staged network change is off by default and must be turned on
# explicitly, per run, from the command line. There is no host or group where
# this may default to true: a converge run that can rewrite the hypervisor's
# bridges is a converge run that can end the estate.
proxmox_network_apply: false

# Seconds before the dead-man switch restores the previous configuration. Long
# enough for ifreload plus a reachability probe, short enough that a lockout
# is over before you have finished reading the traceback.
proxmox_network_revert_after: 120
```

`roles/proxmox_network/meta/main.yml`:

```yaml
---
galaxy_info:
  role_name: proxmox_network
  author: rubenclaes
  description: >-
    Node-level Proxmox bridge configuration, staged by default and applied
    only behind an explicit flag and a dead-man switch.
  license: MIT
  min_ansible_version: "2.17"
  platforms:
    - name: Debian
      versions:
        - bookworm
        - trixie
  galaxy_tags:
    - system
    - networking

dependencies: []
```

`roles/proxmox_network/tasks/main.yml`:

```yaml
---
# Writing an interface through the API stages it in
# /etc/network/interfaces.new and leaves the running configuration alone.
# That staging behaviour is Proxmox's, not ours, and it is the reason this
# role can be run safely without a flag: by itself it changes nothing that is
# live.
- name: Stage the declared interfaces
  community.proxmox.proxmox_node_network:
    api_host: "{{ pve_api_host }}"
    api_user: "{{ pve_api_user }}"
    api_token_id: "{{ pve_api_token_id }}"
    api_token_secret: "{{ pve_api_token_secret }}"
    validate_certs: false
    node: "{{ ansible_facts['hostname'] }}"
    iface: "{{ item.iface }}"
    iface_type: "{{ item.iface_type }}"
    cidr: "{{ item.cidr }}"
    gateway: "{{ item.gateway | default(omit) }}"
    bridge_ports: "{{ item.bridge_ports | default(omit) }}"
    autostart: "{{ item.autostart | default(omit) }}"
    comments: "{{ item.comments | default(omit) }}"
    state: present
  loop: "{{ pve_node_interfaces | default([]) }}"
  loop_control:
    label: "{{ item.iface }}"
  delegate_to: localhost
  become: false
  register: proxmox_network_staged

- name: Apply the staged configuration
  ansible.builtin.import_tasks: apply.yml
  when: proxmox_network_apply | bool
```

`roles/proxmox_network/tasks/apply.yml`:

```yaml
---
# Everything here runs on the node itself, because the sequence has to survive
# the controller losing its connection halfway through.
- name: Keep a copy of the running configuration
  ansible.builtin.copy:
    src: /etc/network/interfaces
    dest: /etc/network/interfaces.before-ansible
    remote_src: true
    mode: "0644"

# systemd-run, not `at`: it is already installed, it survives the SSH session
# dying, and `systemctl stop` on a named unit is an unambiguous cancel. If the
# playbook dies at any point after this, the node returns to a configuration
# that demonstrably worked.
- name: Arm the dead-man switch
  ansible.builtin.command:
    argv:
      - systemd-run
      - --unit=ansible-network-revert
      - "--on-active={{ proxmox_network_revert_after }}"
      - /bin/bash
      - -c
      - cp /etc/network/interfaces.before-ansible /etc/network/interfaces && ifreload -a
  changed_when: true

- name: Apply the staged interface configuration
  ansible.builtin.command: ifreload -a
  changed_when: true

- name: Check that both addresses still answer
  ansible.builtin.wait_for:
    host: "{{ item }}"
    port: 22
    timeout: 30
  loop:
    - 192.168.0.10
    - 192.168.0.14
  delegate_to: localhost
  become: false

- name: Disarm the dead-man switch
  ansible.builtin.command: systemctl stop ansible-network-revert.timer
  changed_when: true
```

- [ ] **Step 4: Write the playbook**

`playbooks/proxmox-network.yml`:

```yaml
---
# Node-level bridge configuration for pve01. NOT part of site.yml and never
# will be.
#
#   ansible-playbook playbooks/proxmox-network.yml                  # stage only
#   ansible-playbook playbooks/proxmox-network.yml -e proxmox_network_apply=true
#
# Without the flag this only writes /etc/network/interfaces.new and changes
# nothing that is running. With it, the node reloads its network while you are
# connected to it over that same network.
#
# Before using the flag, know where the machine physically is. The dead-man
# switch restores the previous configuration after 120 seconds if anything
# goes wrong, but it is a safety net, not a guarantee.
- name: Proxmox node networking
  hosts: proxmox
  gather_facts: true
  roles:
    - proxmox_network
  tags: [proxmox, network]
```

- [ ] **Step 5: Test the staging path only**

```bash
ansible-lint playbooks/proxmox-network.yml roles/proxmox_network
ansible-playbook playbooks/proxmox-network.yml --check --diff
```

Expected: lint passes, recap reports `changed=0`. The transcription matches the live bridges, so staging them is a no-op.

**Do not run the apply path as part of this task.** Staging correctly is the deliverable. Applying proves only that a no-op change reloads cleanly, and it risks the estate to prove it.

- [ ] **Step 6: Commit**

```bash
git add inventory/group_vars/proxmox/network.yml roles/proxmox_network playbooks/proxmox-network.yml
git commit -m "$(cat <<'MSG'
Declare pve01's bridges, staged and behind a flag

Ansible reaches this node on 192.168.0.14 (vmbr1) while the default
route is on vmbr0, so a bad write here is an unreachable hypervisor
rather than a failed task. The role only stages into interfaces.new
unless proxmox_network_apply is passed, and applying arms a systemd-run
dead-man switch that restores the previous config after 120 seconds.

Deliberately absent from site.yml.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
MSG
)"
```

---

### Task 6: `recovery-drill.yml`

**Files:**
- Create: `playbooks/tasks/bootstrap_host.yml`
- Create: `playbooks/recovery-drill.yml`
- Modify: `playbooks/bootstrap.yml`
- Modify: `inventory/group_vars/proxmox/lxcs.yml`
- Modify: `TODO.md`

**Interfaces:**
- Consumes: `pve_lxc_defaults` and `pve_lxcs` from `inventory/group_vars/proxmox/lxcs.yml`; the `baseline` role; `baseline_packages` from `roles/baseline/defaults/main.yml`.
- Produces: `playbooks/tasks/bootstrap_host.yml`, shared by `bootstrap.yml` and the drill so both provision a host identically. This mirrors `playbooks/tasks/update_host.yml`, which exists for the same reason.

**The point of this task is the proof, not the container.** A drill that creates
and destroys a container without bootstrapping or baselining it proves only that
the Proxmox API works. The assertions in play 4 are the deliverable.

- [ ] **Step 1: Declare the drill's vmid**

Append to `inventory/group_vars/proxmox/lxcs.yml`:

```yaml

# The vmid playbooks/recovery-drill.yml builds and destroys. It is declared
# here, not guessed at run time, so a glance at this file shows the one id a
# playbook is allowed to destroy. 199 sits well above the range pve_lxcs uses
# and is asserted free before every drill.
drill_vmid: 199
```

- [ ] **Step 2: Extract the bootstrap tasks so the drill can reuse them**

Create `playbooks/tasks/bootstrap_host.yml` with the tasks currently inline in
`bootstrap.yml`, everything after the one-host assert:

```yaml
---
# Shared by bootstrap.yml and recovery-drill.yml so a drill container is
# provisioned exactly the way a real new host is. If these drift apart, the
# drill stops proving anything about the real path.
- name: Ensure sudo is installed
  ansible.builtin.apt:
    name: sudo
    state: present
    update_cache: true
    cache_valid_time: 3600

- name: Create the service account
  ansible.builtin.user:
    name: "{{ svc_user }}"
    shell: /bin/bash
    create_home: true

- name: Authorize only the ansible key
  ansible.posix.authorized_key:
    user: "{{ svc_user }}"
    key: "{{ svc_pubkey }}"
    exclusive: true

- name: Passwordless sudo for the service account
  ansible.builtin.copy:
    dest: /etc/sudoers.d/ansible
    content: "{{ svc_user }} ALL=(ALL) NOPASSWD:ALL\n"
    owner: root
    group: root
    mode: "0440"
    validate: /usr/sbin/visudo -cf %s
```

In `playbooks/bootstrap.yml`, replace those same four tasks with:

```yaml
    - name: Provision the service account
      ansible.builtin.import_tasks: tasks/bootstrap_host.yml
```

Leave the assert and the `vars` block in `bootstrap.yml` exactly as they are.

- [ ] **Step 3: Prove the extraction changed nothing**

```bash
ansible-lint playbooks/bootstrap.yml
ansible-playbook playbooks/bootstrap.yml --syntax-check
```

Expected: both pass. Do not run `bootstrap.yml` against a real host to test
this — the drill in Step 5 exercises the same file against a throwaway one,
which is the whole point.

- [ ] **Step 4: Write the drill**

`playbooks/recovery-drill.yml`:

```yaml
---
# Proves the guest rebuild path by walking it end to end: create a container
# from pve_lxc_defaults, bootstrap it, baseline it, check the result, destroy
# it.
#
#   ansible-playbook playbooks/recovery-drill.yml -e drill_confirm=true
#
# This is the only playbook here that destroys a guest, and it reaches that
# play only if every earlier play passed. A FAILED DRILL LEAVES THE CONTAINER
# RUNNING, deliberately: the wreckage is the most useful thing a failed drill
# produces. Clean up with `pct destroy 199` when you are done reading it.
#
# Run it after any change to proxmox_lxc, bootstrap.yml or the baseline role.
# A recovery path that has not been run is an assumption.
- name: Create the drill container
  hosts: pve01
  gather_facts: true
  vars:
    drill_ip: 192.168.0.199/24
  tasks:
    - name: Require explicit confirmation
      ansible.builtin.assert:
        that: drill_confirm | default(false) | bool
        fail_msg: >-
          This playbook creates and then DESTROYS container {{ drill_vmid }}.
          Re-run with -e drill_confirm=true if that is what you want.
        success_msg: "Drill confirmed for vmid {{ drill_vmid }}"

    - name: Refuse to touch a vmid that inventory claims
      ansible.builtin.assert:
        that: drill_vmid not in (pve_lxcs | map(attribute='vmid') | list)
        fail_msg: >-
          vmid {{ drill_vmid }} is claimed by a real container in pve_lxcs.
          This playbook would destroy it. Change drill_vmid.
        success_msg: "vmid {{ drill_vmid }} is not claimed by pve_lxcs"

    - name: Read the existing guests
      community.proxmox.proxmox_vm_info:
        api_host: "{{ pve_api_host }}"
        api_user: "{{ pve_api_user }}"
        api_token_id: "{{ pve_api_token_id }}"
        api_token_secret: "{{ pve_api_token_secret }}"
        node: "{{ ansible_facts['hostname'] }}"
        validate_certs: false
      delegate_to: localhost
      become: false
      register: drill_existing

    - name: Refuse to touch a vmid that already exists on the node
      ansible.builtin.assert:
        that: drill_vmid not in (drill_existing.proxmox_vms | map(attribute='vmid') | list)
        fail_msg: >-
          vmid {{ drill_vmid }} already exists on {{ ansible_facts['hostname'] }}.
          Something is using it. Not touching it.
        success_msg: "vmid {{ drill_vmid }} is free"

    - name: Create the drill container
      community.proxmox.proxmox:
        api_host: "{{ pve_api_host }}"
        api_user: "{{ pve_api_user }}"
        api_token_id: "{{ pve_api_token_id }}"
        api_token_secret: "{{ pve_api_token_secret }}"
        validate_certs: false
        node: "{{ ansible_facts['hostname'] }}"
        vmid: "{{ drill_vmid }}"
        hostname: drill
        ostemplate: "{{ pve_lxc_defaults.template }}"
        disk_volume: { storage: local-lvm, size: 4 }
        cores: 1
        memory: 512
        swap: 512
        unprivileged: "{{ pve_lxc_defaults.unprivileged }}"
        netif:
          net0: "name=eth0,bridge={{ pve_lxc_defaults.bridge }},ip={{ drill_ip }},gw={{ pve_lxc_defaults.gateway }}"
        pubkey: "{{ pve_lxc_defaults.pubkey }}"
        onboot: false
        cmode: tty
        state: present
      delegate_to: localhost
      become: false

    - name: Start the drill container
      community.proxmox.proxmox:
        api_host: "{{ pve_api_host }}"
        api_user: "{{ pve_api_user }}"
        api_token_id: "{{ pve_api_token_id }}"
        api_token_secret: "{{ pve_api_token_secret }}"
        validate_certs: false
        node: "{{ ansible_facts['hostname'] }}"
        vmid: "{{ drill_vmid }}"
        hostname: drill
        state: started
      delegate_to: localhost
      become: false

    - name: Wait for SSH
      ansible.builtin.wait_for:
        host: "{{ drill_ip | split('/') | first }}"
        port: 22
        timeout: 180
      delegate_to: localhost
      become: false

    - name: Add the drill container to the in-memory inventory
      ansible.builtin.add_host:
        name: drill
        ansible_host: "{{ drill_ip | split('/') | first }}"
        groups: drill

# Root with a key, because pve_lxc_defaults.pubkey was injected at creation.
# This is the same first-contact position a genuinely new container is in.
- name: Bootstrap the drill container
  hosts: drill
  gather_facts: true
  remote_user: root
  vars:
    svc_user: ansible
    svc_pubkey: "{{ lookup('file', '~/.ssh/ansible_ed25519.pub') }}"
  tasks:
    - name: Provision the service account
      ansible.builtin.import_tasks: tasks/bootstrap_host.yml

- name: Baseline the drill container
  hosts: drill
  gather_facts: true
  vars:
    ansible_user: ansible
    ansible_become: true
  roles:
    - baseline

# The actual proof. Everything above this play is setup.
- name: Check that the drill container is usable
  hosts: drill
  gather_facts: false
  vars:
    ansible_user: ansible
    ansible_become: true
  tasks:
    - name: Confirm the service account can escalate
      ansible.builtin.command: id -un
      become: true
      register: drill_id
      changed_when: false
      failed_when: drill_id.stdout != 'root'

    - name: Read the installed packages
      ansible.builtin.package_facts:

    - name: Confirm every baseline package is installed
      ansible.builtin.assert:
        that: baseline_packages | difference(ansible_facts.packages.keys() | list) | length == 0
        fail_msg: >-
          Missing after a full bootstrap and baseline:
          {{ baseline_packages | difference(ansible_facts.packages.keys() | list) | join(', ') }}.
          The rebuild path does not produce a working host.
        success_msg: "All {{ baseline_packages | length }} baseline packages present"

    - name: Confirm SSH password authentication is off
      ansible.builtin.command: sshd -T
      become: true
      register: drill_sshd
      changed_when: false
      failed_when: "'passwordauthentication no' not in drill_sshd.stdout"

- name: Destroy the drill container
  hosts: pve01
  gather_facts: true
  tasks:
    - name: Destroy the drill container
      community.proxmox.proxmox:
        api_host: "{{ pve_api_host }}"
        api_user: "{{ pve_api_user }}"
        api_token_id: "{{ pve_api_token_id }}"
        api_token_secret: "{{ pve_api_token_secret }}"
        validate_certs: false
        node: "{{ ansible_facts['hostname'] }}"
        vmid: "{{ drill_vmid }}"
        state: absent
        force: true
      delegate_to: localhost
      become: false
```

- [ ] **Step 5: Run the drill**

```bash
ansible-lint playbooks/recovery-drill.yml playbooks/tasks/bootstrap_host.yml
ansible-playbook playbooks/recovery-drill.yml -e drill_confirm=true
```

Expected: five plays, no failed tasks, and a final recap in which the drill
host disappears because its container is gone.

If it fails, the container is still running at `192.168.0.199`. Log in and
find out why before destroying it — that failure is the most valuable output
this plan produces, because it means the real rebuild path was broken and you
now know it without having needed it.

- [ ] **Step 6: Verify it is really gone**

```bash
ansible pve01 -m ansible.builtin.command -a "pct list"
```

Expected: no container `199`.

- [ ] **Step 7: Tick the backlog item**

In `TODO.md`, remove the "Bouw één keer een wegwerp-LXC en gooi hem weg" item
from "Herstelpad testen" and add to "Done":

```markdown
- [x] Herstelpad bewezen: recovery-drill.yml bouwt, bootstrapt, baselinet en vernietigt een wegwerp-LXC
```

- [ ] **Step 8: Commit**

```bash
git add playbooks/recovery-drill.yml playbooks/tasks/bootstrap_host.yml \
        playbooks/bootstrap.yml inventory/group_vars/proxmox/lxcs.yml TODO.md
git commit -m "$(cat <<'MSG'
Prove the guest rebuild path with a repeatable drill

Creates container 199 from pve_lxc_defaults, bootstraps it, baselines
it, then asserts the service account can escalate, every baseline
package is installed and password auth is off. Only then destroys it.

A failed drill leaves the container running on purpose - the wreckage is
what you need when the rebuild path turns out to be broken.

bootstrap.yml's tasks move to playbooks/tasks/bootstrap_host.yml so the
drill provisions a host the same way a real one is, mirroring how
update_host.yml is already shared. If they drift, the drill proves
nothing.

Three assertions guard the destroy: -e drill_confirm=true, the vmid must
not be claimed by pve_lxcs, and it must not already exist on the node.

Closes the backlog item that said this path had never been run.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
MSG
)"
```

---

## What this plan does not do

Carried forward from the spec's "Out of scope", repeated here because an
executor reads the plan and not always the spec:

- **Notifications stay unbuilt.** Backup job `backup-a6c792f3-ad6c` covers
  guest `104` and PBS holds no group for it, which means it is failing right
  now and nothing reports it. Task 2 makes the intended state legible; it does
  not make the failure visible. That remains open.
- **The PBS encryption key is still not backed up anywhere.** Export it once
  with `proxmox-backup-client key show` and store it outside this repo and
  outside the building. Until that is done, the backups in `store1` are
  unreadable after the loss of `pve01`, and every task above is scaffolding
  around a hole.
- **Orphaned PBS groups `ct/109` and `vm/110`** need removing by hand. No role
  here deletes anything.
- `datacenter.cfg`, the cluster firewall, and off-site replication.
