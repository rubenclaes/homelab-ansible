# Backlog

Wat af is, staat hier niet: dat staat in git. Uitleg en keuzes staan in de
docs. Per punt: wat, en de volgende stap.

## Nu — hier kan iets misgaan

- [ ] **Mac mini-schijf (8 TB) op 94,5%**, `DiskAlmostFull` gaat af. media01
      en Time Machine delen die ruimte. Een limiet per Time Machine-share, en
      de back-up van de oude Intel-MacBook (131 GB) weg.
- [ ] **Tweede AdGuard als DNS 2.** Nu deelt Home alleen `192.168.0.29` uit:
      ligt ct 107 of pve01 plat, dan heeft het huis geen DNS. Een tweede op de
      Mac mini met `roles/adguard`, dan in UniFi als DNS 2 en in
      `unifi_expected_dns`.
- [ ] **Vault-wachtwoorden roteren**: de eerste tekens kwamen in een
      sessielog. `ansible-vault rekey --new-vault-id infra@<bestand>`.

## Lopend

- [ ] **`work-wsl`**: op de werk-pc SSH aan (alleen sleutels, WSL in
      nat-modus), de `ansible@neodata`-sleutel erop, dan `ansible work-wsl -m
      ping`, `adguard.yml` en `smoketest.yml`.
- [ ] **Plex voor de familie via Tailscale.** De Mac mini staat klaar
      (custom server access URL `http://100.74.124.12:32400`, Relay uit). Nog:
      per tv-box Tailscale + Plex, kwaliteit Original. Klaar als het Dashboard
      Direct Play toont.
- [ ] **Tailscale-regels testen** met een familie-account: Plex en Caddy
      werken, `:22` en Proxmox niet.

## Later

- [ ] **Cloudflare in OpenTofu** (`tofu/cloudflare/`): DNS van `neodata.be`
      (ook de mail) en de R2-bucket van PBS staan nu met de hand in de
      console. Eerst een API-token (*Zone → DNS → Edit*, *R2 → Edit*) in
      `tofu/secrets.env`; importeren tot de eerste `plan` leeg is; dan in
      `tofu-drift.yml`.
- [ ] **Home Assistant in Prometheus** (de prometheus-integratie van HA): nu
      ziet alleen de Smoketest dat `haos` wegvalt.
- [ ] **Action1** voor de pc van de ouders en de Macs. Daarmee ook de Mac
      mini van macOS 14.6.1 af; dan kan `macos_brew_upgrade` daar weer aan.
- [ ] **Gastennetwerk in UniFi**: nu zit een gast op hetzelfde wifi als pve01
      en de Macs.
- [ ] **Plex op de Mac mini in Homebrew**: eerst met de hand overzetten (zie
      `host_vars/macmini/main.yml`).
- [ ] **`tag:device`** voor sleutel-toestellen (`tailscale-key.yml`), los van
      `tag:homelab`, met een tweede OAuth-client.
