# Backlog

## Nu — hier kan iets misgaan

- [ ] **Een geplande job die faalt meldt zichzelf niet.** `Drift check` faalde
      op 23-09 om 06:00 en dat is pas twee uur later bij toeval gezien, door
      met de hand in de taaklijst te kijken. Zolang dit er niet is, is elk
      schema een aanname.

      Dit gaat sinds 23-09 ook over de back-ups. De wekelijkse job schrijft
      over NFS naar de Mac mini; slaapt die op zondagnacht, dan faalt hij stil.
      En de oude job naar `local` faalde maandenlang elke zondag zonder dat
      iemand het zag - dát is wat dit gat kost. Proxmox meldt nu naar
      `mail-to-root`, wat lokale post is die niemand leest.

      Je hebt al Prometheus, Grafana, Loki en Alloy op VM 102 draaien. Een
      Alertmanager ernaast dekt in één keer de schijven, de hosts en de
      certificaten; Semaphore en Proxmox kunnen daarna naar dezelfde
      ontvanger wijzen.

- [ ] **Twee stacks op de Mini komen niet terug na een herstart van OrbStack.**
      Oorzaak gevonden op 23-09: het zijn precies de twee die een externe
      schijf onder `/Volumes` aankoppelen - `duplicati` op
      `/Volumes/media01/backups`, `shelfmark` op `/Volumes/SSD Nas/...`. De
      vijf die wél terugkwamen gebruiken alleen paden onder
      `/Users/rubenclaes/Container`. OrbStack deelt die schijf pas later de VM
      in, en `restart: unless-stopped` helpt niet tegen een start die niet
      lukt.

      De goedkoopste reparatie is `Stacks` een dagelijks schema geven: dan
      herstelt het zichzelf binnen een dag. Doe dat pas ná de eerste
      handmatige run hieronder, anders draait die eerste beheerde run
      onbewaakt.

---

## Aanzetten — de code staat er, jij moet nog iets doen

- [ ] **De Mac mini is beschreven, niet beheerd.** `stacks.yml --limit
      macmini` is groen in droogloop en meldt voor alle zes stacks `ok`, maar
      zolang hij niet echt gedraaid heeft is het een beschrijving en geen
      herbouwpad.

          ansible-playbook playbooks/stacks.yml --limit macmini

      Daarnaast, los daarvan: **Plex** en **OrbStack** staan buiten Homebrew,
      dus die moet je eerst met de hand overzetten voor je ze beschrijft. Het
      waarom staat in `host_vars/macmini.yml`.

---

## Semaphore

Alle twaalf templates staan sinds 23-09 in
`semaphore_templates_list` in `inventory/host_vars/semaphore/main.yml`, en
`site.yml` roept `semaphore-templates.yml` aan. Wat wanneer draait staat in het
runbook *Onderhoud*.

---

## Opruimen in de estate

- [ ] **Pocket ID draait dubbel.** `id` op docker is de huidige instantie,
      `auth` op de Mini de oude - allebei op 1411, allebei 200. Zet `auth` uit
      en haal zijn route weg, anders weet je bij een storing niet welke stuk
      is. Daarna kan `pocketid` in `docker_stacks_list` van de Mini.

- [ ] **`vpn.neodata.be` hangt aan een dynamisch WAN-adres.** De VPN-server
      staat op "Existing IP Address" en UniFi waarschuwt zelf dat dat adres
      wijzigt. Zoek uit of iets die Cloudflare-record bijwerkt; zo niet, zet
      Dynamic DNS aan.

- [ ] **`--accept-routes` staat overal uit.** Voor DNS maakt dat sinds 23-09
      niet meer uit, maar onderweg kom je zo niet bij `192.168.0.x` - en de
      subnet-route die ct 108 adverteert doet niets zolang niemand hem
      accepteert.

- [ ] **De monitoring-stack herstart bij de eerste beheerde run.**
      `docker compose up --dry-run` zegt Recreate voor grafana, prometheus,
      loki en alloy. Te overleven, hun data staat in `${DATA_PATH}`, maar plan
      het: het is een onderbreking van precies het ding dat onderbrekingen
      moet melden.

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

---

## Klein, wanneer het uitkomt

- [ ] **Vault-wachtwoorden roteren.** Tijdens het opzetten zijn de eerste
      tekens van beide in een sessielog terechtgekomen.
      `ansible-vault rekey --new-vault-id infra@<bestand>`.

- [ ] **Mac mini draait macOS 14.6.1** — updaten via Action1. Zolang dat zo is
      bouwt Homebrew daar alles vanaf broncode (Tier 3), en daarom staat
      `macos_brew_upgrade` op de Mini uit.
