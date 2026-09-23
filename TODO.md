# Backlog

## Nu — hier kan iets misgaan

- [ ] **Een geplande job die faalt meldt zichzelf niet — voor Proxmox opgelost.**
      Sinds 23-09 stuurt Proxmox waarschuwingen en fouten naar ntfy (ct 109,
      topic `homelab`), dus een mislukte back-up komt op je telefoon. Getest
      met een vzdump die faalde. Nog open, en allemaal kunnen ze naar dezelfde
      ntfy:

      - **Semaphore.** Het begon hiermee: `Drift check` faalde op 23-09 om
        06:00 en dat is pas twee uur later bij toeval gezien, door met de hand
        in de taaklijst te kijken. Zolang dit er niet is, is elk schema een
        aanname.
      - **PBS** heeft een eigen meldingssysteem en meldt nog nergens heen.
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

## Semaphore

Alle twaalf templates staan sinds 23-09 in
`semaphore_templates_list` in `inventory/host_vars/semaphore/main.yml`, en
`site.yml` roept `semaphore-templates.yml` aan. Wat wanneer draait staat in het
runbook *Onderhoud*.

---

## Opruimen in de estate

- [ ] **`vpn.neodata.be` hangt aan een dynamisch WAN-adres.** De VPN-server
      staat op "Existing IP Address" en UniFi waarschuwt zelf dat dat adres
      wijzigt. Zoek uit of iets die Cloudflare-record bijwerkt; zo niet, zet
      Dynamic DNS aan.

- [ ] **Wie komt via Tailscale op het hele thuisnetwerk?** De subnet-route
      van ct 108 (`192.168.0.0/24`) is goedgekeurd, en je iPhone komt er
      onderweg mee op het LAN (getest 23-09). Wie je via NeoGate op de tailnet
      zet, krijgt dat misschien ook: dat hangt af van de toegangsregels in de
      Tailscale-console (Access controls). Staat daar de standaardregel "alles
      mag alles", dan wel. Beperk de route tot jezelf, en pas daarna "Iemand
      VPN geven" aan.

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
