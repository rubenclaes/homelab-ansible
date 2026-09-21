# Rebuild path for the Proxmox layer

**Date:** 2026-09-21
**Status:** draft, awaiting review
**Scope:** the layer underneath the guests. Storage, backup jobs, access and
node networking on `pve01`, plus datastore and job configuration on `pbs`,
plus a repeatable drill that proves a guest can be rebuilt from nothing.
Notifications, `datacenter.cfg`, the firewall and off-site replication are
deliberately excluded and listed under "Out of scope".

## Why

Every guest in this estate has a role that installs it, and PBS holds a
restorable copy of each one. The machine underneath them has neither. If
`pve01` is lost, its storage definitions, backup jobs, users, roles, ACLs and
bridge configuration are reconstructed from memory, and the guests cannot be
restored until that reconstruction is correct.

`pbs` is in the same position for a different reason: its role installs the
package and stops there, on purpose, leaving the datastore and its prune and
verify jobs as UI state.

The third gap is confidence rather than data. `pve_lxcs` → `proxmox-lxcs.yml`
→ `bootstrap.yml` → `site.yml` is a complete path on paper that has never been
run end to end. An untested recovery path is an assumption.

## What the investigation established

Measured against the live estate on 2026-09-21, not assumed:

| Question | Finding |
|---|---|
| How large is `/etc/pve`? | 15K. Size is irrelevant; content is the only question. |
| Does it hold secrets? | Yes, all of them under `priv/`: `token.cfg`, `pve-root-ca.key`, `authkey.key`, `storage/`, `acme/`. Everything outside `priv/` is declarative and safe. |
| Is the network config in `/etc/pve`? | **No.** `/etc/network/interfaces` sits outside it and would have been missed by a naive `/etc/pve` backup. |
| Does `community.proxmox` cover this? | Partly, and less than the module names suggest. Measured against the pinned 2.0.0 rather than inferred: `proxmox_node_network` is complete (`cidr`, `gateway`, `bridge_ports`, `autostart`, `comments`). `proxmox_storage` covers `dir`, `zfspool` and `pbs` but **not `lvmthin`**, so `local-lvm` is out of its reach. `proxmox_backup_schedule` takes only `vm_name`, `vm_id`, `backup_id`, `state` — it moves a guest in or out of an **existing** job and cannot define one. `proxmox_access_acl` declares `check_mode: support: none`. No module exists for `notifications.cfg`, `datacenter.cfg`, or anything on the PBS side. |
| How does Ansible reach `pve01`? | Over `192.168.0.14`, which is **`vmbr1`**. The default gateway is on `vmbr0` (`192.168.0.10`). Two bridges, one subnet, and the control path is not the default-route interface. |
| Are the backup jobs healthy? | **No.** `backup-e6cc3e8b-ac39` lists vmid `109`, a guest that no longer exists. `backup-a6c792f3-ad6c` is `all` excluding only `100`, so `104` is in scope, yet PBS holds no group for `104`. The definitions are right and the execution is not. Nothing reports this. |
| Is the PBS storage encrypted? | Yes. `storage.cfg` carries the key's fingerprint; the key itself lives in `/etc/pve/priv/storage/`. |
| What does the API token actually reach? | Less than assumed. `proxmox_storage` calls `GET /storage/{name}` even in check mode, and that needs `Datastore.Allocate` — a privilege distinct from the `Datastore.AllocateSpace`, `.AllocateTemplate` and `.Audit` the `AnsibleAutomation` role holds. Measured after Task 1 failed with 403 on it. |
| Does PBS replicate anywhere? | No. `sync-job list` is empty. Every copy of every backup is in one building. |

## Decisions

1. **The repo becomes the owner of this configuration.** This reverses the
   line taken by the `adguard` and `pbs` roles, whose comments say they will
   not fight an appliance's UI for ownership. That reasoning still holds for
   `AdGuardHome.yaml`, which is large, hand-tuned runtime state. It does not
   hold for a handful of storage definitions and backup jobs that are small,
   stable, and worthless to reconstruct by hand under pressure. The `pbs`
   role's header comment is rewritten to record the reversal rather than
   left contradicting the code beneath it.

2. **Nothing under `/etc/pve/priv/` is captured.** A rebuilt node generates
   its own CA and authkeys, and `proxmox-access.yml` already reissues the API
   token. The backup therefore contains no secret at all and needs no special
   handling.

3. **Secrets required to *recreate* config come from the existing vault, not
   from a dump.** Recreating the `pbs` storage entry needs a PBS password;
   that credential belongs in the `infra` vault next to the Cloudflare and
   Proxmox tokens already there. This keeps decision 2 intact — we never copy
   `priv/`, we deliberately keep the few credentials we need.

4. **Reconciliation is additive, never exclusive.** Roles ensure the declared
   objects exist. They never delete an object that is present on the host but
   absent from inventory. `root@pam` and `rubenclaes@pam` are PAM accounts
   that predate this repo, and an exclusive reconcile would remove them and
   lock the estate out. Drift in the other direction is a reporting problem,
   handled by `report.yml`, not a deletion problem.

5. **Datacenter config goes through `pvesh`, not through the API modules.**
   This revises an earlier decision that had storage using `proxmox_storage`
   for its check mode and diff. That decision did not know the price:
   `proxmox_storage` calls `GET /storage/{name}` even in check mode, which
   needs `Datastore.Allocate` — the privilege that lets a token create,
   modify and **delete** storage definitions. The `ansible@pve` token secret
   lives in the `infra` vault, which sits on a laptop and on the Semaphore
   container, so widening it widens what a compromise of either reaches.
   Paying that for a module's convenience is the wrong trade when `pvesh`
   over SSH as root — which every other playbook here already does — costs
   nothing extra.

   The result is also more coherent than the original plan: storage and
   backup jobs now share one mechanism and one read-compare-act shape,
   rather than a module for one and `pvesh` for the other. `proxmox_access`
   stays on `pveum` for the same reason, matching the read-modify-write
   guard it already has — a guard `proxmox_role` does not offer, and which
   exists because setting an empty privilege list revokes API access for
   every playbook here.

6. **`local-lvm` and `vm-hdd`'s mountpoint come back into scope.** They were
   excluded because `proxmox_storage` has no `lvmthin` type and its
   `zfspool_options` takes only `pool` and `sparse`. `pvesh` has neither
   limit, so decision 5 closes two gaps this spec had accepted as costs.

   The `pbs` storage stays out, for a different and unresolved reason. Its
   API representation carries an `encryption-key` field, and telling a key
   apart from a key's fingerprint requires reading `/etc/pve/priv/storage/`,
   which decision 2 puts out of bounds. Rather than commit a value that
   might be a live secret, the entry is left unmanaged and documented. See
   Risk 1, which is the same key.

7. **Roles are split by blast radius, using Proxmox's own boundary.** Storage,
   backup jobs and access are Datacenter-level objects reached over the API,
   where a wrong value is a wrong value. Networking is node-level, where a
   wrong value ends the session. That split is visible in the role names, so
   the question "may this run in the nightly converge?" is answered by the
   name rather than by reading the tasks.

8. **The drill is a playbook, not a checklist.** Running it once answers the
   question once. Making it repeatable means it can run after any change to
   the provisioning path, which is when the answer is most likely to have
   changed.

## Design

### Role layout

```text
roles/proxmox_datacenter/   NEW    storage (module), jobs (pvesh) -> site.yml
roles/proxmox_access/       EXTEND users, groups, roles, ACLs     -> site.yml
roles/proxmox_network/      NEW    vmbr0/vmbr1                    -> NOT in site.yml
roles/pbs/                  EXTEND datastore, prune, verify       -> site.yml
playbooks/proxmox-datacenter.yml NEW imported by site.yml
playbooks/proxmox-network.yml   NEW  the only caller of proxmox_network
playbooks/recovery-drill.yml    NEW  throwaway LXC, built and destroyed
```

`proxmox-access.yml` exists already but is imported by neither `site.yml` nor
its documented list of hand-run playbooks. Since its tasks are idempotent API
calls, this work adds it to `site.yml` alongside the new
`proxmox-datacenter.yml`. That is a behaviour change to the nightly converge
and is called out here rather than slipped in.

`proxmox_datacenter` and `proxmox_access` reach the API with
`api_host` / `api_token_id` / `api_token_secret`, `delegate_to: localhost`,
`become: false` — the pattern `proxmox_lxc` already uses, so the credentials
and the failure modes are ones this repo already understands.

`proxmox_network` and the PBS tasks run on the host itself, because neither
has API module coverage.

### Inventory data model

Siblings of the existing `lxcs.yml`, one file per subject:

```text
inventory/group_vars/proxmox/storage.yml   pve_storages
inventory/group_vars/proxmox/backup.yml    pve_backup_jobs
inventory/group_vars/proxmox/access.yml    pve_roles, pve_users, pve_acls
inventory/group_vars/proxmox/network.yml   pve_node_interfaces
inventory/host_vars/pbs/main.yml           pbs_datastores, pbs_prune_jobs, pbs_verify_jobs
```

Each list is a transcription of what is live today, with two corrections made
deliberately and recorded in the commit message: vmid `109` is dropped from
the weekly job, and the two orphaned PBS groups (`ct/109`, `vm/110`) are noted
for manual removal since no role deletes anything.

The PBS storage entry references its password and encryption key by vault
lookup, not by literal value.

### Network: the part that can lock you out

The control path matters here. Ansible reaches `pve01` on `192.168.0.14`
(`vmbr1`), while the default route lives on `vmbr0`. A change that breaks
either bridge can end the session with the node unreachable and no console
short of physical access.

The role therefore never applies directly:

1. Write the desired configuration through the API with `state: present`.
   The module documents this explicitly: `present` and `absent` stage changes
   and do not apply them. Proxmox holds them in `/etc/network/interfaces.new`
   and the running config is untouched.
2. Stop there unless `-e network_apply=true` was passed. `site.yml` never
   passes it; `proxmox-network.yml` requires it.
3. Before applying, copy the running `/etc/network/interfaces` aside and arm
   a dead-man switch with `systemd-run --on-active=120`, which restores the
   copy and runs `ifreload -a` unless cancelled.
4. Apply, then verify from the controller that both `192.168.0.10` and
   `192.168.0.14` still answer.
5. Cancel the timer only after that verification passes. If the playbook dies
   at any point, the timer fires and the node returns to the working config.

Applying is the module's `state: apply`, not `ifreload -a`. Proxmox stages into
`/etc/network/interfaces.new` while `ifreload` reads `/etc/network/interfaces`,
so `ifreload` alone would reload the unchanged running config, leave the staged
file in place, and report success — after which the playbook would verify
connectivity against a config it had never applied and disarm the dead-man
switch.

The module also offers `state: revert`, which discards staged changes without
applying them. That is the escape hatch for a staging run you decide against.
It is not a rollback: once a config is applied, only the dead-man switch's copy
brings it back.

### PBS configuration

No modules exist, so this is `proxmox-backup-manager` wrapped for idempotency.
Each object type follows the same shape: list current state as JSON, compare
against the declared list, create or update only on a difference, and set
`changed_when` from that comparison rather than from the command's exit code.

Current state to transcribe: datastore `store1` at `/mnt/datastore/store1`
with `gc-schedule: daily`; one prune job, `keep-last: 7`, daily; one verify
job, `sat 05:00`, `outdated-after: 30`.

`keep-last: 7` against a daily schedule is one week of history, and the
PVE-side storage entry says `prune-backups keep-all=1`, which leaves all
pruning to the PBS side. Both are transcribed as they are. Whether one week
is enough is a separate decision, not one this spec makes silently.

### The recovery drill

`recovery-drill.yml` refuses to run without `-e drill_confirm=true`, and
asserts before anything else that its vmid — a single fixed value declared as
`drill_vmid` in inventory, not a guessed one — is absent from the live guest
list and is not claimed by any entry in `pve_lxcs`. It then creates a throwaway container
from `pve_lxc_defaults`, waits for SSH, runs the `bootstrap.yml` tasks and the
`baseline` role against it, asserts that the service account works and the
baseline packages are present, and destroys it.

The drill is not in `site.yml` and is not scheduled. It is run by hand after a
change to the provisioning path.

## How we know it worked

The acceptance test falls out of the data model. Because the inventory lists
are a transcription of what is live, a `--check` run of the new roles against the
unchanged estate must report `changed=0`. Any change reported is a
transcription error, not a pending fix. This is the same bar `site.yml` is
already held to.

That bar holds only where a module implements check mode. It does **not** hold
for anything driven by `ansible.builtin.command`, which Ansible skips outright
under `--check`: the task reports `skipped` whether its condition was true or
false, so `changed=0` is guaranteed and proves nothing. Decision 5 routes
storage, backup jobs and the whole PBS side through `pvesh` and
`proxmox-backup-manager`, which puts most of this work in that category.

Those roles therefore make their decision assertable rather than inferring it
from `changed`. Each accumulates the entries whose declared fields differ from
live into a drift list, and carries a final task that asserts the list is empty
when `<role>_require_clean` is passed. The acceptance test is that assertion
under `--check`, not the recap. `set_fact` and `assert` both run in check mode,
so the drift list is accurate there.

`proxmox_access_acl` declares no check-mode support for the same reason; ACLs
are verified by a real run followed by `pveum acl list`, compared against
`pve_acls`.

Beyond that: the drill completes and destroys its container, and
`ansible-lint` passes at the production profile.

## Out of scope

- **Notifications.** Chosen deliberately. The consequence is recorded here
  because the investigation made it concrete: backup job `backup-a6c792f3-ad6c`
  is failing for guest `104` right now and nothing reports it. Declaring the
  jobs in inventory does not fix that; it only makes the intended state
  legible.
- `datacenter.cfg` and the cluster firewall.
- Off-site replication. `sync-job list` is empty and stays empty.
- Anything under `/etc/pve/priv/`.

## Risks

1. **The PBS encryption key is not backed up, and without it the backups are
   unreadable.** This follows directly from decision 2 and is the single
   largest hole in the recovery story. The key must be exported once with
   `proxmox-backup-client key show` and stored outside this repo and outside
   this building — a password manager or paper. This is a manual step, it is
   not automated by this work, and the rebuild path is incomplete until it is
   done.
2. **Applying a network change can still lock the node out** if the dead-man
   switch itself fails to fire. Physical access remains the last resort.
3. **Additive reconciliation hides removals.** An object deleted from
   inventory stays on the host. `report.yml` is the intended place to surface
   that, and extending it is follow-on work, not part of this spec.
