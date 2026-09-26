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

- [ ] **Een Alertmanager** naast Prometheus, Grafana, Loki en Alloy op VM 102,
      naar ntfy. Dekt in één keer de schijven, de hosts en de certificaten.
      Proxmox en PBS melden al zelf aan ntfy (sinds 23-09). Eén grens: ligt ntfy
      zelf plat, dan hoor je niets; een Alertmanager die ook mailt vangt dat af.

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
  - [ ] In de console "Prevent edits in the admin console" aanzetten. De docs
        zeggen al dat het dicht is; tot dan wist de volgende `apply` een
        wijziging in de console stil uit.
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
- [ ] **Tag op ct 108 (tailscale)?** Staat als mijn toestel op de tailnet,
      zonder tag. Een tag zetten maakt de tag eigenaar: beslissen, dan in
      `tofu/tailscale/devices.tf`.
- [ ] **Een geplande `tofu plan` in Semaphore**, die rood wordt bij drift, zoals
      de Drift check voor Ansible. Nu draait OpenTofu alleen op de mbp.
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


- [ ] **Plex op de Mac mini staat buiten Homebrew.** Eerst met de hand
      overzetten, dan pas beschrijven. Het waarom staat in
      `host_vars/macmini.yml`.

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
    Grafana, Semaphore en Proxmox VE alleen `admin`. Elke nieuwe client
    krijgt
    `allowed_user_groups` volgens deze lijst:
    - `admin`: Proxmox, PBS, Portainer, Semaphore, Grafana, Prometheus,
      code-server, de *arr-apps, qBittorrent, en de onboarding in NeoGate.
    - `gezin` (woont hier): Immich, Audiobookshelf, Grimmory, Shelfmark,
      Outline, Vaultwarden, PDF, PairDrop, MeTube, IT-Tools.
    - `familie`: Immich, Audiobookshelf, Grimmory, Outline.
    - Geen `gast` tot er echt een is.
  - [ ] Rollen volgen uit de groep (groups-claim), nooit met de hand per app.
  - [ ] `requires_reauthentication` op de clients van Proxmox, PBS,
        Portainer en Semaphore: een gestolen sessie is niet genoeg.
  - [ ] Eerst de mailadressen per persoon gelijkzetten in de apps, anders
        komt er een tweede account naast het bestaande.
  - [ ] Clients voor wat het zelf kan: Shelfmark, Portainer en PBS (OpenID
        realm). Cleanuparr: eerst
        nakijken, de release notes noemen OIDC, de README niet.
  - [ ] Vaultwarden (SSO sinds 1.35): het hoofdwachtwoord blijft, alleen de
        login gaat via Pocket ID.
  - [ ] Forward-auth in Caddy (oauth2-proxy of TinyAuth) voor wat geen eigen
        OIDC heeft: eerst code-server, Sonarr, Radarr, Prowlarr, Bazarr en
        Prometheus (geen of een zwakke login, veel macht); daarna IT-Tools,
        MeTube, BentoPDF, OpenBooks, qBittorrent.
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
