# Backlog

## Nu — hier kan iets misgaan

- [ ] **Een geplande job die faalt meldt zichzelf niet.** `Drift check` faalde
      op 23-09 om 06:00 en dat is pas twee uur later bij toeval gezien, door
      met de hand in de taaklijst te kijken. Zolang dit er niet is, is elk
      schema een aanname.

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

- [ ] **De Mac mini is beschreven, niet beheerd.** Beide droeglopen zijn
      groen - `stacks.yml --limit macmini` meldt voor alle zes stacks `ok`, en
      `nfs.yml` verschilt alleen in de kopregel en de aanhalingstekens - maar
      zolang ze niet echt gedraaid hebben is het een beschrijving en geen
      herbouwpad.

          ansible-playbook playbooks/stacks.yml --limit macmini
          ansible-playbook playbooks/nfs.yml -K

      Daarnaast, los daarvan: **Plex** en **OrbStack** staan buiten Homebrew,
      dus die moet je eerst met de hand overzetten voor je ze beschrijft. Het
      waarom staat in `host_vars/macmini.yml`.

---

## Semaphore

Alle twaalf templates staan sinds 23-09 in
`semaphore_templates_list` in `inventory/host_vars/semaphore/main.yml`, en
`site.yml` roept `semaphore-templates.yml` aan. Wat wanneer draait staat in het
runbook *Onderhoud*.

- [ ] **`Baseline (dry run)` heet iets anders dan hij doet.** Hij draait
      `baseline.yml` zonder `--check`, en dat playbook convergeert gewoon - wie
      erop klikt om te kijken, past de baseline toe op elke Linux-host.
      Hernoemen maakt een tweede template (de naam is de sleutel), `--check`
      toevoegen verandert wat een bestaande knop doet. Kies er één.

---

## Opruimen in de estate

- [ ] **Pocket ID draait dubbel.** `id` op docker is de huidige instantie,
      `auth` op de Mini de oude - allebei op 1411, allebei 200. Zet `auth` uit
      en haal zijn route weg, anders weet je bij een storing niet welke stuk
      is. Daarna kan `pocketid` in `docker_stacks_list` van de Mini.

- [ ] **`shelfmark` draait zonder route**, op `192.168.0.26:8084`. Geef hem een
      naam of zet hem uit, maar kies. Hij staat nu in
      `docker_ports_without_route` zodat report.yml zwijgt, en dat is uitstel.

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

- [ ] **Action1 voor de pc van de ouders**, en voor de Macs.

---

## Klein, wanneer het uitkomt

- [ ] **Vault-wachtwoorden roteren.** Tijdens het opzetten zijn de eerste
      tekens van beide in een sessielog terechtgekomen.
      `ansible-vault rekey --new-vault-id infra@<bestand>`.

- [ ] **Mac mini draait macOS 14.6.1** — updaten via Action1. Zolang dat zo is
      bouwt Homebrew daar alles vanaf broncode (Tier 3), en daarom staat
      `macos_brew_upgrade` op de Mini uit.
