# Backlog

Wat af is, staat hier niet meer: dat staat in git. Per punt: wat, waarom, en
de volgende stap.

## Nu — hier kan iets misgaan

- [ ] **Tweede AdGuard als DNS 2.** Sinds 25-09 deelt Home alleen
      `192.168.0.29` uit (`1.1.1.1` eruit: die brak `*.neodata.be`). Staat
      ct 107 of pve01 stil, dan heeft het hele huis geen DNS.
  - [ ] Tweede instantie op een andere machine dan pve01 (de Mac mini?),
        met dezelfde `roles/adguard`-instellingen, rewrites en blocklists.
  - [ ] In UniFi als DNS 2, en in `unifi_expected_dns`.

- [ ] **Alarmen: wat nog ontbreekt.** Alertmanager meldt sinds 05-10 aan
      ntfy (node_exporter op elke Linux-host, SMART op pve01, zeven alarmen).
  - [ ] Een dead man's switch: een altijd-afgaand alarm naar een dienst buiten
        huis, die mailt als het stil wordt. Nu hoor je niets als ntfy of de
        monitoring-VM zelf plat ligt.
  - [ ] Meten wat nu ontbreekt: de sites zelf (blackbox), de certificaten.
- [ ] **De 8 TB-schijf van de Mac mini zit op 94,5%** (06-10). media01 en de
      Time Machine-back-ups delen die ruimte; de netwerk-shares hebben geen
      limiet. Een limiet per Time Machine-share, en de back-up van de oude
      Intel-MacBook (131 GB, laatst 28-11-2025) weg als die Mac weg is.

---

## Lopend — thuis afwerken

- [ ] **Werk-pc `work-wsl` als beheerde host.** Ubuntu in WSL op de werk-pc,
      beheerd vanaf thuis over de tailnet.
  - [ ] SSH-server, alleen sleutels (`PasswordAuthentication no`), WSL in nat-modus.
  - [ ] Publieke `ansible@neodata`-sleutel in `~/.ssh/authorized_keys`.
  - [ ] Vanaf de mbp: `ansible work-wsl -m ping` → groene pong.
  - [ ] `adguard.yml` draaien (zet `work-wsl.home.arpa`), dan `smoketest.yml`:
        die faalt tot dan op die ene naam.

- [ ] **Tailscale-regels afwerken.** De regels staan in git en OpenTofu zet ze
      (sinds 25-09).
  - [ ] Test met een echt familie-account: Plex en Caddy werken, `:22` en
        Proxmox niet.

- [ ] **Plex voor de familie.** Via Tailscale op de boxen (Apple TV /
      Google TV) aan de tv, geen port forward.
  - [ ] Plex → Network → Custom server access URLs: `http://100.74.124.12:32400`.
  - [ ] Plex → Relay uit.
  - [ ] Per box: Tailscale + Plex, aanmelden met het account van die persoon,
        kwaliteit op Original.
  - [ ] Eerste stream: Dashboard toont Direct Play, niet Relay.

- [ ] **UniFi als gegevensbron (alleen lezen).** Ansible beheert de toestellen
      niet; alles leest, niets schrijft naar UniFi.
  - [ ] Op de iPhones van het gezin: Private Wi-Fi Address → Fixed.
  - [ ] **WireGuard: UniFi bewaart nog DNS `192.168.0.26`** (de oude AdGuard)
        voor Neodata VPN. Het veld staat niet in de UI; via de API lukte het
        niet (24-09). Een nieuw profiel krijgt dus `.26`: zet DNS in de
        WireGuard-app met de hand op `.29`. Opnieuw proberen na een
        UniFi-update, en dan de VPN terug in `unifi_expected_dns`.
  - [ ] De iPhone die gewoon "iPhone" heet (was `.171`): van wie? Alias geven
        zodra hij weer online is.

---

## Git is de bron — wat nog buiten git leeft

Regel: git beslist, de rest volgt. **OpenTofu** voor wat er *bestaat*
(`tofu/tailscale/`, `tofu/proxmox/`), **Ansible** voor wat er *in* een
machine draait, **met de hand maar beschreven** voor wat alleen in een app
kan (Plex, de Semaphore-UI, Full Disk Access op de Mac).

- [ ] **PBS**: datastore-, prune- en verify-jobs. Nakijken of daar een
      bruikbare provider voor is; zo niet, de Ansible-rol laten corrigeren in
      plaats van alleen toevoegen.
- [ ] **AdGuard-versie**: nu update je in de web-UI en kopieer je de versie
      naar git. Omdraaien: versie in git, rol installeert.
- [ ] **Cloudflare in OpenTofu** (`tofu/cloudflare/`, officiële provider
      `cloudflare/cloudflare`). Nu staat alles met de hand in de console,
      ook de mail (MX, SPF) van `neodata.be`: één klik legt die stil, en
      niemand weet dan wat er stond.
  - [ ] Erin: de DNS-records van `neodata.be` en de R2-bucket van PBS, met
        zijn opruimregels. Bestaande dingen importeren, niet opnieuw maken.
  - [ ] Bewust niet: de state-bucket `homelab-tofu-state` (OpenTofu kan zijn
        eigen fundament niet beheren) en de API-tokens (dan moet OpenTofu
        een sleutel hebben die alles in het account mag).
  - [ ] Een token voor OpenTofu met alleen DNS-bewerken op `neodata.be` en
        R2-bewerken, in `tofu/secrets.env`.
  - Bekeken en afgewezen op 25-09: UniFi (alleen community-providers 0.x,
    UniFi werkt zichzelf bij, een fout legt het hele huis plat), de opslag en
    back-upjobs van Proxmox (de Ansible-rol stuurt al bij; meldingen kent de
    provider niet), GitHub (vraagt een token met beheerrechten voor weinig
    winst).

---

## Aanzetten — de code staat er, jij moet nog iets doen

- [ ] **Tailscale na de apply van 07-10** (tags, grants, settings).
  - [ ] Op de mbp: Tailscale werkt nog naar `pve01.home.arpa` en
        `photos.neodata.be`.
  - [ ] Auto-updates voor nieuwe toestellen? Zet het in de console, of geef
        de OAuth-client `opentofu` de scope `feature_settings` en zet
        `devices_auto_updates_on = true` in `tofu/tailscale/settings.tf`.
- [ ] **Tailscale-metrics en alarmen.** `ansible-playbook playbooks/tailscale.yml`,
      dan `playbooks/monitoring.yml`.
- [ ] **OpenTofu drift in Semaphore.** `ansible-playbook playbooks/semaphore.yml`
      (installeert `tofu`), dan `playbooks/semaphore-templates.yml`. Eerste run
      met de hand starten en nakijken.

- [ ] **Plex op de Mac mini staat buiten Homebrew.** Eerst met de hand
      overzetten, dan pas beschrijven. Het waarom staat in
      `host_vars/macmini/main.yml`.

---

## Grotere projecten

- [ ] **Alles achter Pocket ID.** Eén passkey voor het hele homelab. Na
      Outline, want die zet `tofu/pocketid` neer. Elke app maakt bij de eerste
      login zelf het account aan (auto-provisioning) en koppelt op mailadres.
  - Wie beslist, één plek per ding, anders overschrijven ze elkaar:
    - **OpenTofu** (git): groepen, OIDC-clients, welke groep waar mag. De
      regels: zelden anders, verdienen een review.
    - **NeoGate**: de mensen (aanmaken, groep kiezen, weghalen), plus Plex
      delen en Tailscale uitnodigen. Moet zonder terminal kunnen, ook door
      je partner. OpenTofu raakt geen gebruikers aan.
  - Groepen staan sinds 26-09 in `tofu/pocketid/groups.tf`; Outline laat
    alleen `gezin` en `familie` toe, Immich, Audiobookshelf en Grimmory ook
    (sinds 26-09; Karen logt nog in, dan pas de wachtwoord-login uit).
    Grafana, Semaphore, Proxmox VE en PBS alleen `admin`,
    Shelfmark en Vaultwarden `gezin`. Elke nieuwe client krijgt
    `allowed_user_groups` volgens deze lijst:
    - `admin`: Proxmox, PBS, Semaphore, Grafana, Prometheus,
      code-server, de *arr-apps, qBittorrent, RomM, en de onboarding in NeoGate.
    - `gezin` (woont hier): Immich, Audiobookshelf, Grimmory, Shelfmark,
      Outline, Vaultwarden, PDF, PairDrop, MeTube, IT-Tools, RomM.
    - `familie`: Immich, Audiobookshelf, Grimmory, Outline, RomM.
    - `gast` (op bezoek): RomM, PairDrop, BentoPDF, IT-Tools, copyparty. Sinds 05-10 in
      `tofu/pocketid/groups.tf`.
  - [ ] Rollen volgen uit de groep (groups-claim), nooit met de hand per app.
  - [ ] Eerst de mailadressen per persoon gelijkzetten in de apps, anders
        komt er een tweede account naast het bestaande.
  - [ ] Cleanuparr: nakijken of het OIDC kan (de release notes noemen het,
        de README niet). Zo niet: forward-auth, zoals de *arr-apps.
  - Forward-auth (oauth2-proxy naast Caddy) staat sinds 27-09 voor
    code-server, de *arr-apps, Prometheus en qBittorrent (`admin`) en voor
    IT-Tools, MeTube, BentoPDF, PairDrop en OpenBooks (`gezin`).
  - Sinds 27-09 laat de docker-host de poorten van Sonarr, Radarr, Prowlarr,
    Bazarr en code-server alleen nog van Caddy toe (DOCKER-USER). code-server
    heeft geen eigen wachtwoord meer; qBittorrent laat Caddy door zonder
    tweede login.
  - [ ] Werkt een app via Pocket ID: daar registreren en wachtwoord-login
        uit. Twee deuren is er één te veel.
  - [ ] Noodtoegang blijft lokaal: `root@pam`, de admin van PBS en UniFi,
        wachtwoord in Vaultwarden. Ligt Pocket ID plat, dan kom je nog binnen.
  - [ ] Sessies in de apps kort (een dag): uitschakelen in Pocket ID stopt
        nieuwe logins, niet een sessie die al open staat.
  - [ ] Het weekrapport toont wie in welke groep zit: de toegangscontrole
        zonder moeite.
  - [ ] **NeoGate** (eigen backlog): een Pocket ID-plugin en één scherm
        "iemand toevoegen": groepen kiezen uit wat er is (nooit zelf maken),
        uitnodiging als link of QR die verloopt, Plex en Tailscale mee volgens
        de groep. Weghalen is één knop overal: Pocket ID uit, Plex
        intrekken, Tailscale weg. Alleen voor `admin`, met een logboek.
  - Blijft zoals het is: Plex en Overseerr (Plex-account), UniFi
    (Ubiquiti-account), Home Assistant (alleen via een community-add-on),
    AdGuard, ntfy.
- [ ] **Foto's in Immich groeien.** Bij de melding "R2 bijna vol" kiezen
      tussen minder versies, foto's apart, of betalen.
- [ ] **Action1 voor de pc van de ouders**, en voor de Macs.
- [ ] **Apple MDM.** Komt eraan. Daarna een pagina "Mac of iPhone klaarzetten";
      tot dan is er geen vaste werkwijze om te beschrijven.
- [ ] **Een apart gastennetwerk in UniFi.** Nu komt een gast op het gewone
      wifi, naast pve01, de Macs en alle diensten.

---

## Klein, wanneer het uitkomt

- [ ] **Vault-wachtwoorden roteren.** Tijdens het opzetten zijn de eerste
      tekens van beide in een sessielog terechtgekomen.
      `ansible-vault rekey --new-vault-id infra@<bestand>`.
- [ ] **Mac mini draait macOS 14.6.1** — updaten via Action1. Zolang dat zo is
      bouwt Homebrew daar alles vanaf broncode (Tier 3), en daarom staat
      `macos_brew_upgrade` op de Mini uit.
