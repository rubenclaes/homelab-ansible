# Backlog

## Next up
- [ ] Onboard media stack (`project: media-stack`, contains immich-postgres → pick a quiet moment)
- [ ] Pocket ID: two instances running (auth → Mac mini .26, id → docker01 .15). Find out which one apps use, migrate, retire the other
- [ ] evcc: stack exists on docker01 but isn't running, Caddy route still points to .15:7070. Run it or remove the route
- [ ] Semaphore: run "Update guests" once by hand, then schedule (limit `guests:!semaphore`)
- [ ] Semaphore: notifications for failed tasks (Telegram/email)
- [ ] PBS: check backup job includes semaphore (LXC 104) and doesn't overlap Sunday 04:00 updates

## Fixes
- [ ] docker_stack role: add `check_mode: false` to "Verify mount units exist"
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
- [x] Rotate Cloudflare token, store in Vault, deploy via caddy role
- [x] Remove --environ from caddy.service override
- [x] baseline_held_packages (caddy held)
- [x] ssh.socket vs ssh.service conflict fixed, enforced in baseline role
- [x] Onboard monitoring01, adguard, tailscale, semaphore
- [x] Caddyfile in Git + cleanup (unifi, downloads, automate removed)
- [x] Stacks under Ansible: utils, glance, homepage, metrics, rustdesk, portainer, neogate, infra, azuracast
- [x] All docker01 .env files backed up in Vault
- [x] Semaphore UI running at semaphore.neodata.be