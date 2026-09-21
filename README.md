# homelab-ansible

Ansible for a small home infrastructure: one Proxmox host, a handful of LXC
guests, a Docker host, and two Macs.

Everything is idempotent. `playbooks/site.yml` converges the whole estate and is
safe to run whenever.

---

## First-time setup

```bash
git clone git@github.com:rubenclaes/homelab-ansible.git
cd homelab-ansible

# 1. Toolchain. Versions are pinned in .github/workflows/lint.yml; match them.
pipx install "ansible-core==2.21.4" "ansible-lint==26.8.0"

# 2. Collections (pinned in collections/requirements.yml).
ansible-galaxy collection install -r collections/requirements.yml

# 3. Vault passwords - two of them, see below. Without these you can lint,
#    but not run anything real.
install -m 600 /dev/null ~/.ansible/vault_pass_infra
install -m 600 /dev/null ~/.ansible/vault_pass_stacks
$EDITOR ~/.ansible/vault_pass_infra    # paste, no trailing spaces
$EDITOR ~/.ansible/vault_pass_stacks

# 4. Enable the pre-commit guard. Per clone; git does not do this for you.
git config core.hooksPath .githooks

# 5. Check it works.
bin/check-vaulted
ansible-lint
ansible all -m ping
```

The SSH key is `~/.ssh/ansible_ed25519` (set in `ansible.cfg`). Every managed
Linux host authorises its public half for the `ansible` service account.

### The two vault identities

There is no single password. Secrets are split by **blast radius**, so either
half can be rotated without touching the other:

| Identity | Covers | A leak means |
|---|---|---|
| `infra` | `inventory/**/vault.yml`, `roles/semaphore/files/config.json` | rotating Proxmox, Cloudflare and PBS tokens — control of the estate |
| `stacks` | `files/env/*.env` | rotating application logins inside the stacks |

`ansible.cfg` sets `vault_identity_list` to **`bin/vault-pass-client`** for both.
Ansible passes `--vault-id` to any executable whose name ends in `-client`, so
one script serves both identities. Per identity `<id>` it tries, in order:

| Source | Used by |
|---|---|
| `$ANSIBLE_VAULT_PASSWORD_<ID>` | CI and Semaphore (inject as secrets) |
| `~/.ansible/vault_pass_<id>` | your workstation, the normal case |
| `~/.ansible/vault_pass` | the pre-split single password, kept as a fallback |
| *(placeholder)* | a clone with no secrets — lint and syntax-check still work |

That last row is the point: `ansible-lint` and `--syntax-check` must pass in a
fresh clone with no secrets at all. Anything that genuinely needs to decrypt
still fails loudly with `Decryption failed`.

Encrypting a **new** file requires naming the identity, or it picks `infra`:

```bash
ansible-vault encrypt --encrypt-vault-id stacks files/env/newstack.env
```

> **Semaphore needs both passwords.** It previously held one. Add `infra` and
> `stacks` as separate vault keys in its UI (Key Store → Vault), or its runs
> will fail with `Decryption failed`.

---

## Playbooks

| Playbook | Targets | What it does |
|---|---|---|
| `site.yml` | everything | **Master playbook.** Baseline → Caddy → stacks → Semaphore → dotfiles. |
| `baseline.yml` | `linux` | Timezone, base packages, unattended upgrades, SSH hardening. |
| `caddy.yml` | `caddy` | Renders the Caddyfile from `caddy_sites`. |
| `stacks.yml` | `docker01` | Pulls the stacks repo, deploys vaulted `.env`s, brings compose stacks up. |
| `semaphore.yml` | `semaphore` | Semaphore UI + its Ansible virtualenv and `known_hosts`. |
| `dotfiles.yml` | `mbp` | SSH config, Git config, `.zshrc`. |
| `report.yml` | all → `caddy` | Health report, published to `https://report.<domain>`. |
| `caddy-smoketest.yml` | localhost | Requests every site in `caddy_sites`, asserts none are broken. |
| `update.yml` | `linux` | Package upgrades and optional reboots. **See below.** |
| `bootstrap.yml` | a new host | Creates the `ansible` service account. **See below.** |
| `proxmox-info.yml` | `pve01` | Lists all guests via the API. |
| `proxmox-lxcs.yml` | `pve01` | Creates LXCs from `pve_lxcs` that don't exist yet. |
| `proxmox-autostart.yml` | `pve01` | Sets `onboot=1` on every guest that lacks it. |

Routine run:

```bash
ansible-playbook playbooks/site.yml
ansible-playbook playbooks/site.yml --check --diff     # dry run first
ansible-playbook playbooks/site.yml --limit docker01   # one host
```

### Updates and reboots

`update.yml` runs in two plays on purpose: **all guests first, then the
hypervisor.** In a single play, `pve01` could reboot out from under the guests
it hosts, mid-run.

Two independent switches, both off by default:

```bash
ansible-playbook playbooks/update.yml                      # patch only, no reboots
ansible-playbook playbooks/update.yml -e allow_reboot=true # reboot guests that need it

# Reboot pve01 too. This takes every guest down with it.
ansible-playbook playbooks/update.yml \
  -e allow_reboot=true -e allow_hypervisor_reboot=true
```

Both are read with `| default(false)`, not declared as play vars, so they can
also be set in `group_vars`/`host_vars`. (A play-level `vars:` would silently
outrank inventory — that was a real bug here once.)

Packages in `baseline_held_packages` stay pinned; `dist-upgrade` honours dpkg
holds, so the custom Caddy build is never replaced by an update run.

### Bootstrapping a new host

Chicken-and-egg: the inventory connects as `ansible`, but that account does not
exist yet. First contact is as root, with a password:

```bash
ssh-keyscan -H 192.168.0.99 >> ~/.ssh/known_hosts   # accept the host key
ansible-playbook playbooks/bootstrap.yml --limit newhost -u root -k
```

`-k` prompts for the root password. (This is why `ansible.cfg` does *not* force
`PreferredAuthentications=publickey` — that would make first contact
impossible.) After bootstrap, normal runs work with the key alone.

---

## Layout

```
ansible.cfg                 config; also pins the vault resolver
bin/vault-pass-client       resolves the vault password per identity
bin/check-vaulted           fails if any secret is committed in plaintext
.githooks/pre-commit        blocks a commit that would leak a secret
collections/                pinned Galaxy dependencies
inventory/
  hosts.yml                 all hosts and groups
  group_vars/all/           settings shared by everything (report.*)
  group_vars/proxmox/       Proxmox API creds (main.yml + vault.yml)
  host_vars/<host>/         per-host settings; vault.yml where secrets apply
files/env/                  vaulted .env files for the Docker stacks
playbooks/                  see the table above
playbooks/tasks/            task files shared between plays
roles/                      baseline, caddy, docker_stacks, dotfiles,
                            macos, proxmox_lxc, semaphore
```

Collections are installed from `collections/requirements.yml`, never committed.
`.ansible/` is gitignored.

---

## Secrets

Anything sensitive is `ansible-vault` encrypted at rest:

- `inventory/**/vault.yml` — API tokens, per host or group
- `files/env/*.env` — Docker stack environment files
- `roles/semaphore/files/config.json` — Semaphore's DB and encryption keys

```bash
ansible-vault view   inventory/host_vars/pbs/vault.yml
ansible-vault edit   files/env/media.env
ansible-vault encrypt files/env/newstack.env    # before the first commit!
```

`bin/check-vaulted` verifies every one of those paths is still encrypted.

It runs in two places. The **pre-commit hook** (`.githooks/pre-commit`) is the
real gate: it inspects the *staged blob*, not the working tree, because `git
add` snapshots content — a file can be encrypted on disk while a plaintext
version sits in the index. CI runs the same check as a backstop, but CI fires
*after* a push, by which point a leaked secret is already in GitHub's history
and needs a rotation rather than a revert.

Enable the hook once per clone:

```bash
git config core.hooksPath .githooks
```

Bypass in a genuine emergency with `git commit --no-verify`.

Plaintext `vault_*` variables are referenced from unencrypted files
(`main.yml`) and defined in the encrypted sibling (`vault.yml`), so you can read
the structure without decrypting anything.

---

## Host prerequisites

Two roles configure software they deliberately do **not** install. Both are
documented at the top of their `tasks/main.yml`:

- **`caddy`** — the running binary is a custom build with the Cloudflare DNS
  module, needed for the DNS-01 wildcard certificate. The stock Debian package
  has no plugins and would break TLS issuance, which is why `caddy` sits in
  `baseline_held_packages` for that host.
- **`docker_stacks`** — the Docker engine is managed out of band. An unattended
  engine upgrade would restart every stack on the host.

Provisioning a genuinely new host means: create the LXC
(`proxmox-lxcs.yml`) → `bootstrap.yml` → install the service by hand → then the
role takes over.

### Upgrading Caddy

Caddy is held, so `update.yml` will not touch it. To move it:

```bash
ssh caddy
sudo caddy upgrade          # rebuilds keeping the current plugin set
sudo systemctl restart caddy
```

Then re-run `ansible-playbook playbooks/caddy.yml` and
`ansible-playbook playbooks/caddy-smoketest.yml` to confirm nothing broke.

---

## The report

`report.yml` collects pending upgrades, reboot flags, disk usage, Docker
container state, ZFS pool health, SMART status, Proxmox guests and PBS backup
ages, renders `playbooks/templates/report.html.j2`, and publishes it to the
Caddy host.

It is served at `https://report.<domain>` and restricted in the Caddyfile to
private ranges plus Tailscale's `100.64.0.0/10` — everything else gets a 403.

The rendered file goes to a private temp file on the control node, not a
predictable `/tmp` path, because it lists internal hostnames and IPs and the
control node may be shared with Semaphore.

Paths and identities live in `inventory/group_vars/all/report.yml`;
`report_publish_dir` is consumed by both `report.yml` and `Caddyfile.j2`, so
they cannot drift apart.

---

## CI

`.github/workflows/lint.yml` runs on pushes to `master` and on pull requests:

1. `bin/check-vaulted` — no plaintext secrets
2. `ansible-lint` — currently clean at the **`production`** profile
3. `ansible-playbook --syntax-check` on every playbook

Ansible and ansible-lint versions are pinned in the workflow's `env:` block;
bump them together with `collections/requirements.yml`.

Run the same checks locally before pushing:

```bash
bin/check-vaulted && ansible-lint && \
  for p in playbooks/*.yml; do ansible-playbook --syntax-check "$p"; done
```

---

## Conventions

- **FQCN everywhere** (`ansible.builtin.copy`, not `copy`).
- **`inject_facts_as_vars = False`.** Facts are only reachable as
  `ansible_facts['kernel']`, never as bare `ansible_kernel`. Keep it that way.
- **Role variables are prefixed** with the role name (`baseline_*`, `caddy_*`).
- **`validate:` on anything that can lock you out** — sudoers, sshd config, the
  Caddyfile. A broken config fails the task instead of the host.
- **`no_log: true` and `diff: false`** on tasks handling secrets.
- **Upstreams are named, not numbered.** `caddy_sites` entries reference an
  inventory host and port (`{ name: photos, host: docker01, port: 2283 }`), and
  the Caddyfile resolves the IP from that host's `ansible_host`. Re-addressing a
  host is a one-line change in `inventory/hosts.yml`. Use `upstream:` only for a
  target that is not in the inventory.
- Open work lives in [TODO.md](TODO.md).
