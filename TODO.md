# Backlog

## Urgent-ish
- [ ] Rotate Cloudflare API token (leaked in journal via --environ)
- [ ] Remove --environ from caddy.service override
- [ ] Add `baseline_held_packages` to role + host_vars/caddy.yml

## Cleanup
- [ ] Caddy LXC: both ssh.socket and ssh.service active, pick one
- [ ] Duplicate docker / docker-desktop casks (MBP + Mini), by hand
- [ ] Mini: brew leaves → host_vars/macmini.yml (the _extra pattern)
- [ ] Tidy ~/.ssh/config (old aliases, pv01 typo)
- [ ] Finder restart handler for macOS defaults

## Next hosts
- [ ] Bootstrap + baseline monitoring01 (192.168.0.17)