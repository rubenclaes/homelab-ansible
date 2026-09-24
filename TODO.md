# Backlog

## Lopend — thuis afwerken (gestart 24-09)

- [ ] **A0. Eerst: caddy en adguard hun adres zelf laten kennen.** Nu vragen
      ze het bij elke start aan de UCG, en alleen een Fixed IP in UniFi houdt
      het op `.25` en `.29`. Valt die weg, dan heeft het hele huis geen DNS
      meer en zijn alle routes dood. Het adres staat al in git (`lxcs.yml`);
      de container moet het gewoon zelf gebruiken. Adguard is even weg bij de
      herstart: doe dit als niemand internet gebruikt. Caddy eerst, die is
      minder kritiek.
  - [ ] Als root op pve01: `pct config 106 | grep -e net0 -e nameserver`.
        Neem die `net0`-regel letterlijk over en vervang alleen `ip=dhcp` door
        `ip=192.168.0.25/24,gw=192.168.0.1`. De `hwaddr` moet blijven staan,
        anders ziet UniFi een nieuw toestel.
        `pct set 106 --net0 '<aangepaste regel>'` en `pct reboot 106`.
  - [ ] Controle: `curl -sI https://books.neodata.be` geeft een antwoord.
  - [ ] Hetzelfde voor adguard (107) met `ip=192.168.0.29/24,gw=192.168.0.1`.
        Stond er geen `nameserver`, zet dan ook `--nameserver 1.1.1.1`: zo
        kan adguard zelf nog namen opzoeken als zijn eigen DNS niet draait.
  - [ ] Controle: `dig @192.168.0.29 pve01.home.arpa +short` geeft `192.168.0.14`.
  - [ ] De Fixed IP's in UniFi laten staan. Ze beslissen niets meer, maar ze
        beletten dat de UCG `.25` of `.29` aan een ander toestel geeft.
  - [ ] In `lxcs.yml` de twee opmerkingen "live container still uses DHCP
        (see TODO)" weghalen en committen.

- [ ] **A1. Werk-pc `work-wsl` als beheerde host.** Ubuntu in WSL op de
      werk-pc, beheerd vanaf thuis over de tailnet.
  - [ ] SSH-server, alleen sleutels (`PasswordAuthentication no`), WSL in nat-modus.
  - [ ] Publieke `ansible@neodata`-sleutel in `~/.ssh/authorized_keys`.
  - [ ] Tag `tag:work` op de node in de Tailscale-console.
  - [x] Groep `workstations` met `work-wsl` in `inventory/00-static.yml`
        (bewust niet onder `linux`: vaak uit, en geen gepland playbook mag hem raken).
  - [ ] Vanaf de mbp: `ansible work-wsl -m ping` → groene pong.

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

- [ ] **A5. AdGuard-wildcard uit git.** `*.neodata.be` → caddy staat sinds
      24-09 in `host_vars/adguard/main.yml` en de rol beheert hem.
  - [ ] `ansible-playbook playbooks/adguard.yml --check --diff`. Verwacht:
        geen wijziging, want de regel met de hand is dezelfde. Toont hij wel
        iets voor `*.neodata.be`, eerst uitzoeken waarom.

- [ ] **A4. UniFi als gegevensbron (alleen lezen).** UniFi is een bron, geen
      inventory: de toestellen zelf beheert Ansible niet. Alles leest, niets
      schrijft naar UniFi.
  - [ ] Stap 1 — `ansible.utils` en `netaddr` staan in de requirements. Thuis:
        `pipx inject ansible-core netaddr` en
        `ansible-galaxy collection install -r collections/requirements.yml`.
  - [ ] Stap 2 — route `unifi` → UCG staat in `host_vars/caddy/main.yml`,
        plus `group_vars/all/unifi.yml`, `playbooks/unifi-clients.yml` en
        `playbooks/tasks/unifi_clients.yml`. Thuis:
    - [ ] `caddy.yml --check --diff`, dan echt, dan `smoketest.yml`.
    - [ ] API-sleutel maken: UniFi → Settings → Control Plane → Integrations.
    - [ ] `ansible-vault create --encrypt-vault-id infra inventory/group_vars/all/vault.yml`
          met `vault_unifi_api_key`.
    - [ ] `unifi-clients.yml` draaien; veldnamen nakijken (`macAddress`,
          `name`, `ipAddress`, `type`) en of de lijst volledig is (`totalCount`).
  - [ ] Stap 3 — melding bij onbekend toestel: `playbooks/unifi-watch.yml`. Thuis:
    - [ ] Eigen ntfy-token → `vault_ntfy_unifi_token`.
    - [ ] `unifi_known_macs` vullen uit de uitvoer van stap 2.
    - [ ] Op de telefoons van het gezin: Private Wi-Fi Address → Fixed.
    - [ ] Testrun (verwacht: nul meldingen), dan Semaphore-template elke 15 minuten.
  - [ ] Stap 4 — routes tegen UniFi: `playbooks/unifi-routes.yml`. Thuis:
    - [ ] Draaien.
    - [ ] Testen of de API-sleutel ook de oude API opent
          (`/proxy/network/api/s/default/rest/user` → `use_fixedip`). Zo ja:
          ook reservaties controleren, dan waarschuwt hij vóór een herstart
          in plaats van erna.
  - [ ] Stap 5 — namen in AdGuard, zonder Ansible:
        `dig -x 192.168.0.26 @192.168.0.1 +short`, dan AdGuard → DNS →
        Private reverse DNS servers `192.168.0.1` + "Use private reverse DNS
        resolvers". Geen kopie van de lijst (zie `rewrites.yml`).
  - [ ] Stap 6 — pagina Toestellen op de docs-site: `docs.yml` (block/rescue),
        `toestellen.md.j2`, `_meta.js`. Zonder MAC-adressen.
        **Let op: deze code staat nog niet in de repo** (geen
        `toestellen.md.j2`, geen UniFi in `docs.yml`). Staat ze nog ergens
        lokaal, bv. op de mbp? Thuis:
    - [ ] `docs.yml` draaien, pagina bekijken.
    - [ ] De rescue één keer testen met een foute `unifi_api_url`.

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

- [ ] Vaste adressen voor caddy en adguard → A0.
- [x] AdGuard-wildcard `*.neodata.be` → in de rol (A5 om te controleren).
- [ ] AdGuard upstream (Quad9) en per-client instellingen → zie "Grotere
      projecten". Kan via Ansible (REST API, zoals de rewrites).
- [ ] UniFi: de DNS die DHCP uitdeelt (`.29` + `1.1.1.1`) en de reservaties
      staan alleen in UniFi. Afgesproken dat Ansible niet naar UniFi schrijft;
      dan minstens een controle die waarschuwt als het afwijkt (A4 stap 4).
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
- [ ] De wekelijkse back-upjob naar de Mac mini: `backup.yml` zegt dat hij op
      23-09 van pve01 verdween en alleen met `-e proxmox_datacenter_create=true`
      terugkomt. Nakijken of hij er weer staat; zo niet, terugzetten.
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

- [ ] **Plex en OrbStack op de Mac mini staan buiten Homebrew.** Die moet je
      eerst met de hand overzetten voor je ze beschrijft. Het waarom staat in
      `host_vars/macmini.yml`. (De stacks zelf zijn sinds 23-09 beheerd: `Stacks`
      draait dagelijks ook op de Mini, en een droogloop geeft `changed=0`.)

---

## Grotere projecten

- [ ] **De upstream en clientinstellingen van AdGuard staan nog nergens.**
      Blocklists en rewrites zijn beschreven, de Quad9-upstream over DoH en de
      per-client instellingen leven enkel in die container. Met opzet
      overgeslagen: één verkeerde waarde legt de naamresolutie van het hele
      huis plat, dus dit verdient een eigen wijziging op een rustig moment.

- [ ] **De Duplicati-secrets roteren.** Ze staan sinds 22-09 in een gevaulte
      `.env`, maar ook nog in de historie van `rubenclaes/homelab`. Het
      webservice-wachtwoord is zo gewisseld; `SETTINGS_ENCRYPTION_KEY`
      ontsleutelt Duplicati's eigen instellingen-database en moet via Duplicati
      zelf, anders mag je al je back-upjobs opnieuw aanmaken.

- [ ] **Off-site back-up. De 1 van 3-2-1 ontbreekt nog.** Sinds 23-09 zijn er
      twee kopieen op twee machines - PBS op pve01, en wekelijks volledige
      dumps naar de Mac mini - maar beide staan in hetzelfde huis, aan dezelfde
      stroom. Tegen brand, diefstal of ransomware die allebei bereikt helpt dat
      niet.

      Op PBS staat geen enkele sync job (`/etc/proxmox-backup/sync.cfg` bestaat
      niet). De datastore is al client-side versleuteld, dus het doel hoeft
      niet vertrouwd te worden: een PBS remote naar een goedkope target, of
      rclone van de datastore naar B2.

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
