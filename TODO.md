# Backlog

## Lopend — thuis afwerken (gestart 24-09)

- [ ] **A0. Eerst: vaste adressen na de verhuis naar de UCG.** In UniFi
      nakijken dat caddy (`192.168.0.25`) en adguard (`192.168.0.29`) nog een
      Fixed IP hebben. Beide containers draaien nog op DHCP (zie `lxcs.yml`).
      Valt die reservatie weg, dan heeft na een herstart het hele huis geen DNS
      meer en zijn alle routes dood.

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
  - [ ] Policy uit de console kopiëren naar `files/tailscale/policy.hujson` en committen.

      Stand in de repo: `policy.hujson` heeft de `mac-mini:32400`-regel, de
      test met `maarten.claes95@gmail.com`, en funnel alleen voor mijn eigen
      account. Nakijken of de console daar exact mee overeenkomt.

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
