# Backlog

## Next up
- [ ] Onboard media stack (`project: media-stack`, contains immich-postgres → pick a quiet moment)
- [ ] Pocket ID: two instances running (auth → Mac mini .26, id → docker01 .15). Find out which one apps use, migrate, retire the other
- [ ] evcc: stack exists on docker01 but isn't running, Caddy route still points to .15:7070. Run it or remove the route
- [ ] Semaphore: run "Update guests" once by hand, then schedule (limit `guests:!semaphore`)
- [ ] Semaphore: notifications for failed tasks (Telegram/email)
- [ ] PBS: check backup job includes semaphore (LXC 104) and doesn't overlap Sunday 04:00 updates

## Fixes
- [ ] Remove orphan network `portainer_default`, review other leftover networks on docker01
- [ ] Caddy is held: write a small playbook for controlled `caddy upgrade` (keeps plugins)
- [ ] Optional: vacuum caddy journal (old, now-worthless token)

## Cleanup
- [ ] Duplicate docker / docker-desktop casks (MBP + Mini), by hand
- [ ] Mini: brew leaves → host_vars/macmini.yml (the _extra pattern)
- [ ] Finder restart handler for macOS defaults
- [ ] Tidy ~/.ssh/config (pv01 typo, remove pve01-unifi-os, consolidate new hosts)
- [ ] Mac mini on macOS 14.6.1, update (via Action1)

## Next projects
- [ ] Action1 for parents' PC (+ Macs)
- [ ] Proxmox: turn create-lxc into a list-driven role (all LXCs as code)
- [ ] Caddyfile routes as variables instead of hand-edited blocks

## Done
- [x] docker_stacks role: `check_mode: false` on "Verify mount units exist"
- [x] Repo hygiene: .gitignore added, vendored collections untracked (5164 files)
- [x] Collections pinned to major versions in collections/requirements.yml
- [x] README written (setup, bootstrap, update switches, secrets, prerequisites)
- [x] Vault password resolved via bin/vault-pass; repo no longer needs the zshrc export
- [x] bin/check-vaulted guards against committing a plaintext secret; wired into CI
- [x] update.yml split: guests patched before the hypervisor, separate reboot switches
- [x] site.yml is now the real master playbook
- [x] caddy role creates its systemd drop-in dir instead of assuming it exists
- [x] dotfiles role no longer fails on a Mac with no ~/.ssh/config
- [x] semaphore role asserts its fact dependency instead of dying on undefined
- [x] Rotate Cloudflare token, store in Vault, deploy via caddy role
- [x] Remove --environ from caddy.service override
- [x] baseline_held_packages (caddy held)
- [x] ssh.socket vs ssh.service conflict fixed, enforced in baseline role
- [x] Onboard monitoring01, adguard, tailscale, semaphore
- [x] Caddyfile in Git + cleanup (unifi, downloads, automate removed)
- [x] Stacks under Ansible: utils, glance, homepage, metrics, rustdesk, portainer, neogate, infra, azuracast
- [x] All docker01 .env files backed up in Vault
- [x] Semaphore UI running at semaphore.neodata.be