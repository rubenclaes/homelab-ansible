# Backlog

Wat af is, staat hier niet: dat staat in git. Uitleg en keuzes staan in de
docs. Per punt: wat, en de volgende stap.

## Nu — hier kan iets misgaan

- [ ] **De 8 TB-schijf van de Mac mini op 94,5%** (gemeten op de oude Mini;
      de schijf gaat mee naar de M6). media01 en Time Machine delen die
      ruimte. Een limiet per Time Machine-share, en de back-up van de oude
      Intel-MacBook (131 GB) weg.
- [ ] **Tweede AdGuard als DNS 2.** Nu deelt Home alleen `192.168.0.29` uit:
      ligt ct 107 of pve01 plat, dan heeft het huis geen DNS. Een tweede op de
      Mac mini met `roles/adguard`, dan in UniFi als DNS 2 en in
      `unifi_expected_dns`.
- [ ] **Vault-wachtwoorden roteren**: de eerste tekens kwamen in een
      sessielog. `ansible-vault rekey --new-vault-id infra@<bestand>`. Haal
      dan ook `~/.ansible/vault_pass` weg: het oude ene wachtwoord van vóór
      de splitsing, dat niets meer leest.

## Lopend

- [ ] **Nieuwe Mac mini (M6, 16 GB).** De oude is gewist en staat in de
      groep `away`; `host_vars/macmini` is al voor de M6 (Ollama erbij, geen
      brew-blokkade). Volg [Een nieuwe Mac mini](docs-site/content/mac-mini.mdx).
      Daarna nog: Ollama op het LAN laten luisteren
      (`OLLAMA_HOST=0.0.0.0:11434`, de brew-dienst zet dat niet) voor de
      Ollama-plugin van NeoGate. NFS robuust maken: automount op `docker`
      (`x-systemd.automount`) en de media-stack laten wachten op de mounts,
      zodat een herstart van de Mini geen lege mappen meer geeft.

- [ ] **`work-wsl`**: op de werk-pc SSH aan (alleen sleutels, WSL in
      nat-modus), de `ansible@neodata`-sleutel erop, dan `ansible work-wsl -m
      ping`, `adguard.yml` en `smoketest.yml`.
- [ ] **Plex voor de familie via Tailscale.** Na de M6 (custom server access
      URL `http://100.74.124.12:32400`, Relay uit). Nog: per tv-box
      Tailscale + Plex, kwaliteit Original. Klaar als het Dashboard
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
- [ ] **Action1** voor de pc van de ouders en de Macs.
- [ ] **Gastennetwerk in UniFi**: nu zit een gast op hetzelfde wifi als pve01
      en de Macs.
- [ ] **Plex op de Mac mini in Homebrew** (cask `plex-media-server`), zodat
      `update.yml` hem bijwerkt. Op de M6 meteen zo installeren in plaats van
      van plex.tv, dan hoeft er later niets overgezet te worden.
- [ ] **Het certificaat van pve01 vertrouwen** in plaats van
      `validate_certs: false` (23 keer): de root-CA van pve01
      (`/etc/pve/pve-root-ca.pem`) op de laptop en Semaphore, en `ca_path`
      in de taken. Dan valt ook de urllib3-filter in de dotfiles weg.
- [ ] **Next 16 voor de docs-site**: de overige `npm audit`-meldingen
      (next, katex, braces) zitten in Next 15 en Nextra 4.5. Nextra 4.6.1
      brak de build al (10-10-2026), dus eerst uitzoeken waarom.
- [ ] **`tag:device`** voor sleutel-toestellen (`tailscale-key.yml`), los van
      `tag:homelab`, met een tweede OAuth-client.
