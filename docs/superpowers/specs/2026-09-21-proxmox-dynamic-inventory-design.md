# Dynamic inventory from Proxmox

**Date:** 2026-09-21
**Status:** approved, not yet implemented
**Scope:** this spec covers only the inventory migration. Two follow-on pieces
are sequenced after it and get their own specs: generating Caddy routes from
`docker_stacks_list`, and closing the provisioning gap for the custom Caddy
build and the Docker engine.

## Why

`inventory/hosts.yml` is a hand-maintained list of hosts and IPs. Proxmox
already knows all of it for the eight guests, and knows it more accurately —
two containers run DHCP, so the file records addresses that nothing enforces.
Making Proxmox the source of truth removes the drift risk and means a newly
created guest appears in inventory without an edit.

This also serves disaster recovery: after a rebuild, inventory reflects what
actually exists rather than what someone remembered to write down.

## What the investigation established

Measured against the live cluster rather than assumed:

| Question | Finding |
|---|---|
| Can the plugin address DHCP containers? | **Yes.** `/nodes/{node}/lxc/{vmid}/interfaces` returns runtime IPs. All four LXCs resolved correctly, matching `hosts.yml` exactly. |
| Do the QEMU VMs need guest agents installed? | **No.** All four already have `agent=1`. |
| Why did the agent endpoint fail then? | HTTP 403 — *permission denied*, not agent-missing. The `AnsibleAutomation` role lacks `VM.Monitor`. |
| Can the plugin config stay encrypted? | **Yes.** A vault-encrypted `.proxmox.yml` decrypts through `bin/vault-pass-client`. Verified end to end. |
| Do names match? | **No.** Proxmox has `docker`, `docker-grafana-stack`, `haos`; inventory has `docker01`, `monitoring01`, and no haos. |

Two earlier assessments were wrong and are corrected here: the migration does
not need DHCP-to-static conversion, and it does not need agent installation.
The only Proxmox-side prerequisite is a single role privilege.

## Decisions

1. **Hybrid directory inventory.** `macmini`, `mbp` and `pve01` are not
   Proxmox guests, so a static file survives regardless. It shrinks to the
   things Proxmox genuinely does not know about.
2. **The repo adopts Proxmox names.** Chosen over renaming guests in Proxmox
   or maintaining a mapping layer. A mapping layer is indirection that lives
   outside git; renaming in Proxmox would leave the repo unable to explain
   its own history.
3. **The API token stays vault-encrypted** inside the plugin config, rather
   than moving to environment variables. Keeps the repo self-contained and
   reuses the `infra` identity Semaphore already holds.
4. **`haos` is included in inventory but excluded from `baseline`.** It is
   Home Assistant OS: no apt, no standard Python. It appears in inventory and
   reports, which is the useful part, without pretending it is a Debian host.

## Design

### Inventory layout

```text
inventory/
  00-static.yml            pve01, macmini, mbp, and all group definitions
  homelab.proxmox.yml      vault-encrypted; the eight Proxmox guests
  group_vars/              unchanged
  host_vars/               unchanged except the docker01 -> docker rename
```

Ansible merges a directory of sources alphabetically and skips `group_vars/`
and `host_vars/` when doing so. `00-static.yml` sorts before
`homelab.proxmox.yml`, so static definitions load first.

`ansible.cfg`:

```ini
[defaults]
inventory = inventory/

[inventory]
enable_plugins = community.proxmox.proxmox, yaml, ini, auto
```

### Group membership

Guests join `linux` through the plugin's `groups:` conditional rather than
Proxmox tags. Tags would move inventory logic into the PVE UI, where changes
leave no commit trail. `haos` is routed to `appliances` instead, and
`playbooks/site.yml` targets `linux` as it already does, so it is skipped
without a special case.

`00-static.yml` keeps the `linux` group's `ansible_user: ansible` and
`ansible_become: true`, and retains `macs`.

### ansible_host resolution

The plugin's `compose:` derives `ansible_host` from the LXC runtime interface
list, falling back to the QEMU agent interface list. Both paths were exercised
during investigation; the LXC path is confirmed working, the QEMU path is
gated behind the privilege grant below.

### Proxmox privilege

`VM.Monitor` is added to the `AnsibleAutomation` role. Implemented as an
idempotent task — read current privileges, modify only when absent — so the
grant is reproducible on a rebuilt cluster rather than remembered.

## Phases

Each phase is independently verifiable and leaves the repo working.

1. **Grant `VM.Monitor`.** Verify all four VMs then return an address.
2. **Add the dynamic inventory alongside `hosts.yml`.** `ansible.cfg` still
   points at the single file, so the new source is inert until phase 4; the
   parity check drives it explicitly with `-i inventory/homelab.proxmox.yml`.
3. **Rename in the repo.** `docker01` → `docker`, `monitoring01` →
   `docker-grafana-stack`, across roughly 26 references in seven files.
4. **Cut over, in one commit.** Add `00-static.yml`, delete `hosts.yml`, and
   flip `ansible.cfg` to the directory.

   `hosts.yml` must be *deleted*, not merely bypassed: once `inventory/` is a
   directory source, Ansible parses every file in it, so leaving `hosts.yml`
   in place would define `docker01` and `docker` as two separate hosts.
5. **Repoint Semaphore.** Its inventory is a `file` entry pointing at
   `inventory/hosts.yml` and must become the directory.

## Verification

The parity check is the safety story: **every host in the old inventory must
resolve to the same `ansible_host` in the new one.** Confirmed already for the
four LXCs; the four VMs depend on phase 1.

Then, in order:

- `ansible all -m ping` reaches every host
- `site.yml --check` introduces no changes beyond those already pending
- **the rendered Caddyfile is byte-identical** — renaming `docker01` to
  `docker` must resolve to the same upstream IP, so any diff is a real defect
- `ansible-lint` still passes at the `production` profile
- lint and `--syntax-check` still pass in a clone with no vault password

## Rollback

Phases 1-3 change nothing the old inventory depends on, so they are safe to
leave in place even if the cutover is abandoned.

Phase 4 is a single commit that adds `00-static.yml`, deletes `hosts.yml` and
flips `ansible.cfg` together, so rollback is `git revert` of that one commit —
not a one-line edit, because restoring the old inventory means restoring the
deleted file too. Phase 5 is a Semaphore UI change and reverts by hand.

## Risks

- **The QEMU path is unproven.** Phase 1 either produces four addresses or the
  migration stops there. This is why it is phase 1 and not phase 4.
- **Semaphore breaks between phases 4 and 5.** They should be done in one
  sitting, as with the vault split.
- **`docker-grafana-stack` is a worse name than `monitoring01`.** Accepted
  deliberately. Renaming that guest in Proxmox would avoid it and remains
  available later.
- **Phase 3 touches `playbooks/templates/docs.html.j2`,** which is in active
  development, and may conflict.
