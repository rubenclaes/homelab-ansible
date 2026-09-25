# Backlog

## Lopend — thuis afwerken (gestart 24-09)

- [ ] **A1. Werk-pc `work-wsl` als beheerde host.** Ubuntu in WSL op de
      werk-pc, beheerd vanaf thuis over de tailnet.
  - [ ] SSH-server, alleen sleutels (`PasswordAuthentication no`), WSL in nat-modus.
  - [ ] Publieke `ansible@neodata`-sleutel in `~/.ssh/authorized_keys`.
  - [ ] Tag `tag:work` op de node in de Tailscale-console.
  - [ ] Vanaf de mbp: `ansible work-wsl -m ping` → groene pong.
  - [ ] `adguard.yml` draaien (zet `work-wsl.home.arpa`), dan `smoketest.yml`:
        die faalt tot dan op die ene naam.

- [ ] **A2. Tailscale-regels.** Afgesproken: `tag:work` krijgt geen enkele
      regel als bron. Hij hoeft nergens heen; thuis → work-wsl dekt mijn eigen `*:*`.
  - [ ] In de console: host `mac-mini` (`100.74.124.12`), regel
        `autogroup:member` → `mac-mini:32400`, en een test met een echt
        familie-account (accept Plex + Caddy, deny `:22` en Proxmox).
  - [ ] `nodeAttrs` → funnel weghalen, of beperken tot mijn eigen account.
        Funnel zet een dienst op het publieke internet.
  - [ ] Eenmalig nakijken dat de console gelijk is aan `policy.hujson`. In de
        repo staan al de `mac-mini:32400`-regel, de test met
        `maarten.claes95@gmail.com`, en funnel alleen voor mijn eigen account.
        Daarna loopt het andersom: git → Tailscale, via OpenTofu (zie B).

- [ ] **A3. Plex voor de familie.** Via Tailscale op de boxen (Apple TV /
      Google TV) aan de tv, geen port forward.
  - [ ] Plex → Network → Custom server access URLs: `http://100.74.124.12:32400`.
  - [ ] Plex → Relay uit.
  - [ ] Per box: Tailscale + Plex, aanmelden met het account van die persoon,
        kwaliteit op Original.
  - [ ] Eerste stream: Dashboard toont Direct Play, niet Relay.

- [ ] **A4. UniFi als gegevensbron (alleen lezen).** UniFi is een bron, geen
      inventory: de toestellen zelf beheert Ansible niet. Alles leest, niets
      schrijft naar UniFi.
  - [ ] Stap 3 — `unifi-watch.yml` draait elk kwartier in Semaphore. Nog:
        op de iPhones van het gezin Private Wi-Fi Address → Fixed.
  - [ ] **WireGuard: UniFi bewaart nog DNS `192.168.0.26`** (de oude AdGuard)
        voor Neodata VPN. Het veld staat niet in de UI; zetten via de API
        lukte niet (24-09). Een nieuw profiel krijgt dus `.26`: zet DNS in
        de WireGuard-app met de hand op `.29`. Opnieuw proberen na een
        UniFi-update, en dan de VPN terug in `unifi_expected_dns`.
  - [ ] De eerste iPhone (was `.171`) heet gewoon "iPhone": van wie? Alias
        geven zodra hij weer online is.

- [ ] **A5. Tweede AdGuard als DNS 2.** Sinds 25-09 deelt Home alleen
      `192.168.0.29` uit (`1.1.1.1` eruit: die brak `*.neodata.be`). Staat
      ct 107 of pve01 stil, dan heeft het hele huis geen DNS.
  - [ ] Tweede instantie op een andere machine dan pve01 (de Mac mini?),
        met dezelfde `roles/adguard`-instellingen, rewrites en blocklists.
  - [ ] In UniFi als DNS 2, en in `unifi_expected_dns`.

---

## B. Git is de bron — wat nog buiten git leeft

Regel: git beslist, de rest volgt. Wat nu alleen in een console of op een
machine staat, gaat naar git. Wie wat doet:

- **OpenTofu** voor wat er *bestaat*: guests, gebruikers en rechten, de
  Tailscale-policy. Het vergelijkt git met de werkelijkheid en toont het
  verschil (`tofu plan`) voor het iets verandert.
- **Ansible** voor wat er *in* een machine draait: pakketten, config,
  diensten, AdGuard-rewrites.
- **Met de hand**, maar beschreven in git: wat alleen in een app kan (Plex,
  de Semaphore-UI, Full Disk Access op de Mac).

Eerst wat het hele huis plat kan leggen:

- [ ] De `/dev/net/tun`-regels voor ct 107 en 108 staan met de hand in
      `/etc/pve/lxc/*.conf`. De API-token kan ze niet zetten; nakijken of
      OpenTofu dat via root@pam wel kan, anders blijft het een beschreven handstap.

Daarna OpenTofu opzetten, in een map `tofu/` in deze repo:

- [ ] State in een bucket buiten het huis: Cloudflare R2 (S3-compatibel,
      gratis voor dit formaat). Niet in git: git heeft geen slot, en twee runs
      tegelijk (mbp en Semaphore) overschrijven elkaar. Niet op de homelab zelf:
      ligt pve01 plat, dan is ook de kaart van wat er moet staan weg.
  - [ ] Backend `s3` met `use_lockfile = true` (OpenTofu ≥ 1.10): het slot
        staat als bestand naast de state, geen aparte database nodig.
  - [ ] State-versleuteling van OpenTofu aan (`encryption`-blok, pbkdf2).
        De state bevat geheimen; zo leest Cloudflare alleen onleesbare bytes.
        De passphrase in de `infra`-vault.
  - [ ] De R2-sleutel alleen voor die ene bucket, ook in de `infra`-vault.
- [ ] Tailscale eerst: klein, en een fout is snel hersteld. Provider
      `tailscale/tailscale`: de policy uit `policy.hujson`, de globale
      nameserver, de goedgekeurde subnet-route van ct 108, de tags. Vervangt
      A2's "console → git".
  - [ ] Een nieuwe OAuth-client alleen voor OpenTofu, met de scopes
        `policy_file`, `dns` en `devices`. De bestaande blijft enkel
        sleutels maken: twee clients, elk met zo weinig mogelijk rechten, en
        je kunt de ene intrekken zonder de andere. In de `infra`-vault.
  - [ ] `tofu import` van de bestaande policy, dan `tofu plan` → verwacht:
        geen wijziging. Pas daarna iets aanpassen.
  - [ ] Daarna in de console "edits beperken" aanzetten, zodat niemand er nog
        buiten git om iets verandert.
- [ ] Proxmox (provider `bpg/proxmox`): de VM's uit `vms.yml` en de LXC's
      uit `lxcs.yml`, eerst met `tofu import` zodat niets opnieuw gebouwd
      wordt. Dan verdwijnen "NOTHING READS THIS FILE" en "existing containers
      are never modified". Ook gebruikers en rechten uit `access.yml`.
  - [ ] Op elke bestaande guest `lifecycle { prevent_destroy = true }`. Na een
        import toont `tofu plan` soms "replace" voor een VM, en een replace is
        een lege schijf. Nooit een plan toepassen dat een bestaande guest
        vernietigt; eerst de config aanpassen tot het plan leeg is.
  - [ ] Zodra OpenTofu een ding beheert, de oude plek weghalen: `vms.yml`,
        `pve_lxcs` in `lxcs.yml` en `roles/proxmox_lxc`, `access.yml` en
        `roles/proxmox_access`. Blijven beide staan, dan zijn er weer twee
        bronnen, en dat is net wat we weg willen.
- [ ] PBS: datastore-, prune- en verify-jobs. Nakijken of daar een bruikbare
      provider voor is; zo niet, de Ansible-rol laten corrigeren in plaats van
      alleen toevoegen.
- [ ] AdGuard-versie: nu update je in de web-UI en kopieer je de versie naar
      git. Omdraaien: versie in git, rol installeert.

---

## Nu — hier kan iets misgaan

- [ ] **Een geplande job die faalt meldt zichzelf niet — voor Proxmox en PBS opgelost.**
      Sinds 23-09 sturen Proxmox en PBS waarschuwingen en fouten naar ntfy (ct
      109, topic `homelab`), dus een mislukte back-up komt op je telefoon. Getest
      met een vzdump die faalde. Nog open, en allemaal kunnen ze naar dezelfde
      ntfy:

      - **Een Alertmanager** naast Prometheus, Grafana, Loki en Alloy op VM
        102 dekt in één keer de schijven, de hosts en de certificaten.

      Waarom dit dringend was: de oude wekelijkse job naar `local` faalde
      maandenlang elke zondag zonder dat iemand het zag. `mail-to-root` blijft
      staan, maar dat is lokale post die niemand leest.

      Eén grens: ligt ntfy zelf plat, dan hoor je niets. Dat vang je pas af met
      een tweede kanaal, bv. een Alertmanager die ook mailt.

---

## Aanzetten — de code staat er, jij moet nog iets doen

- [ ] **Plex op de Mac mini staat buiten Homebrew.** Die moet je eerst met de
      hand overzetten voor je hem beschrijft. Het waarom staat in
      `host_vars/macmini.yml`. (OrbStack hoeft niet meer: sinds 25-09 draait er
      geen container meer op de Mini en staat OrbStack stil.)

---

## Grotere projecten

- [x] **Off-site back-up** (25-09). Elke nacht naar Cloudflare R2, alleen wat
      git niet kan herbouwen (app-data + foto's, Home Assistant, adguard,
      tailscale, ntfy), 3,1 GB, binnen de gratis laag; r2-guard stopt de sync
      voor het geld kost. Terugzetten getest. Zie runbook "Terughalen uit R2".
  - [ ] Foto's in Immich groeien: bij de melding "R2 bijna vol" kiezen tussen
        minder versies, foto's apart, of betalen.

- [ ] **Action1 voor de pc van de ouders**, en voor de Macs.

- [ ] **Apple MDM.** Komt eraan. Daarna een Homelab-pagina "Mac of iPhone
      klaarzetten" op de docs-site; tot dan is er geen vaste werkwijze om te
      beschrijven.

- [ ] **Een apart gastennetwerk in UniFi.** Nu komt een gast op het gewone
      wifi, naast pve01, de Macs en alle diensten. Staat zo op de
      Homelab-pagina "Gast op bezoek".

- [ ] **NeoGate haalt een Tailscale-lid niet weg.** Bij intrekken trekt de
      plugin alleen de uitnodiging in; wie ze al aanvaardde blijft op de
      tailnet. Nu een handstap in de Tailscale-console (Homelab-pagina
      "Toegang afnemen"). Beter: de Cleaner verwijdert de gebruiker via de API.

---

## Klein, wanneer het uitkomt

- [ ] **Vault-wachtwoorden roteren.** Tijdens het opzetten zijn de eerste
      tekens van beide in een sessielog terechtgekomen.
      `ansible-vault rekey --new-vault-id infra@<bestand>`.

- [ ] **Mac mini draait macOS 14.6.1** — updaten via Action1. Zolang dat zo is
      bouwt Homebrew daar alles vanaf broncode (Tier 3), en daarom staat
      `macos_brew_upgrade` op de Mini uit.
