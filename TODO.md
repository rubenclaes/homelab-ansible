# Backlog

Per punt één zin over wat er moet gebeuren, en één over waarom. De volgorde
is de volgorde: bovenaan staat wat je het eerst wil oplossen.

De volledige geschiedenis van wat af is staat in `git log`, niet hier.

---

## Nu — hier kan iets misgaan

---

## Aanzetten — de code staat er, jij moet nog iets doen

- [x] **De crons staan op lokale tijd**, 23-09. De unit zet
      `SEMAPHORE_SCHEDULE_TIMEZONE=Europe/Brussels` en de dienst is om 08:54
      herstart; `systemctl show` bevestigt de variabele. Daarvoor was het UTC,
      dus alles draaide twee uur later dan er stond - en schoof het mee met de
      zomertijd.

      Let op bij een droogloop: `semaphore.yml --check --diff` laat het
      verschil zien maar schrijft niets, en herstart dus ook niets. Hier is
      twee keer gedacht dat het gezet was terwijl de unit nog van 21-09 was.

- [x] **`dns-smoketest.yml` staat op een schema**, 23-09, dagelijks 06:30.
      Eerst met de hand gedraaid en groen - tien namen, allemaal het adres uit
      de inventory - daarna als template aangemaakt. 06:30 omdat 06:00 en
      07:00 al bezet zijn door Drift check en Docs.

      `dig` bleek al aanwezig op de Semaphore-container, dus de zorg dat
      `dnsutils` eerst via een `site.yml` moest landen was onnodig. Dat blijft
      wel gelden voor een nieuwe controller.

---

## Semaphore — automatiseren wat nu van jouw geheugen afhangt

De vier punten die hier stonden zijn geen UI-werk meer.
`roles/semaphore_templates` beschrijft de templates én hun cron via de API. Op
23-09 echt gedraaid; vijf templates staan in `semaphore_templates_list` in
`inventory/host_vars/semaphore/main.yml`:

| Template | Cron | Wat |
| --- | --- | --- |
| Site converge | `0 5 * * 0` | site.yml, `--limit all:!mbp:!semaphore` |
| Update guests | `0 4 * * 0` | update.yml, `--limit guests:!semaphore` |
| Drift check | `0 6 * * *` | drift.yml met `drift_fail` en `drift_limit` |
| DNS smoketest | `30 6 * * *` | dns-smoketest.yml |
| Cleanup (Apply) | `0 3 * * 6` | cleanup.yml met `cleanup_apply` |
| Restore drill | `0 4 1 * *` | restore-drill.yml |

Lokale tijd sinds 23-09. `--check` geeft nul wijzigingen, dus wat hier staat is
wat er draait.

LET OP dat `Drift check` nog op `error` staat: die faalde op 23-09 om 06:00 op
de `unarchive: checksum`-fout in de adguard-rol. Die fix staat inmiddels op
origin, dus de eerste eerlijke run is morgenvroeg 06:00. Wat verder rest staat
hieronder.

- [x] **`inventory/host_vars/semaphore/vault.yml` aangemaakt**, 23-09. Let op
      dat het `--encrypt-vault-id infra` is en niet `--vault-id`: ansible.cfg
      kent twee identiteiten, dus bij aanmaken moet je zeggen mét welke je
      versleutelt.

- [x] **De dubbele templates opgeruimd**, 23-09. De lijst was er die dag
      eerst met eigen namen ingezet en maakte duplicaten naast wat er al
      stond: `Site (apply)`, `Drift (report)` en `Cleanup (apply)` met een
      kleine a. Alle drie weg, de repo draait nu op de bestaande namen.

      De les die blijft: `name` is de sleutel, en `Cleanup (apply)` naast
      `Cleanup (Apply)` verschilt in één hoofdletter. Ga bij het verwijderen
      op het id af en niet op de naam - hier sneuvelde daardoor per ongeluk de
      originele id 10, inclusief zijn taakgeschiedenis, waarna de rol hem
      opnieuw aanmaakte als id 15.

- [ ] **De zes overgebleven templates overnemen in de repo.**
      `Baseline (dry run)`, `Caddy`, `Cleanup (report)`, `Docs`,
      `Homelab Report` en `Stacks` staan nog alleen in de UI. Docs draait
      dagelijks 07:00 en Homelab Report zondag 08:00; de andere vier hebben
      geen schema. Kopieerwerk, geen ontwerpwerk - maar zolang het niet
      gebeurd is, is "welk playbook draait wanneer" nog steeds niet volledig
      in git te lezen.

- [x] **`semaphore-templates.yml` echt gedraaid**, 23-09. Vijf templates en
      hun schema's staan erin, `--check` geeft sindsdien nul wijzigingen, en
      alle twaalf templates in het project hebben hun environment nog.

      Dat laatste was niet vanzelfsprekend: de eerste versie stuurde alleen
      `environment_id` mee, en dat veld is in Semaphore geen kolom maar een
      aparte tabel die bij elke schrijfactie leeggegooid wordt. Zonder
      `environment_ids` in het payload draait een template zonder zijn
      variabelen.

- [ ] **Een melding als een geplande job faalt.** Dit staat nog steeds open
      en de rol lost het niet op: hij zet schema's, geen alerting.

      Het is geen theorie meer. `Drift check` faalde op 23-09 om 06:00 UTC op
      de `unarchive: checksum`-fout in de adguard-rol, en dat is pas gezien
      toen er met de hand in de taaklijst gekeken werd - twee uur later, bij
      toeval. Precies het scenario waarvoor hier stond dat een stille job
      erger is dan geen job.

- [ ] **`semaphore-templates.yml` in `site.yml` zetten.** De eerste echte run
      was groen, dus de reden om te wachten is weg. Eén regel.

      Bedenk wel wat het oplevert: `Site converge` draait met
      `--limit all:!mbp:!semaphore`, dus in de geplande converge zou deze play
      juist worden overgeslagen. Hij zou alleen meelopen als je site.yml met
      de hand en zonder limit draait.

---

## Opruimen in de estate

- [ ] **Zet `--accept-routes` aan op de toestellen die van huis gaan.**
      Nu staat het overal uit (`RouteAll: False` op de Mini en ct 108). Voor
      DNS maakt dat sinds 23-09 niet meer uit - de nameserver is een
      tailnet-adres - maar het betekent wel dat je onderweg niet bij
      `192.168.0.x` kunt, alleen bij wat een eigen 100.x-adres heeft. De
      subnet-route die ct 108 adverteert doet dus niets zolang niemand hem
      accepteert.


- [ ] **`vpn.neodata.be` hangt aan een dynamisch WAN-adres.** Hij wees op
      22-09 naar `94.111.99.122` en dat klopte, maar de VPN-server staat op
      "Existing IP Address" en UniFi waarschuwt zelf dat dat adres wijzigt.
      Zoek uit of iets die Cloudflare-record bijwerkt; zo niet, zet Dynamic
      DNS aan. Een VPN die stil kapot gaat bij een IP-wijziging ontdek je op
      het slechtst denkbare moment.

- [ ] **`shelfmark` draait zonder route**, op `192.168.0.26:8084`. Zelfde
      keuze. Hij staat nu in `docker_ports_without_route` zodat report.yml
      hem niet elke run meldt, maar dat is uitstel, geen besluit.

- [ ] **Pocket ID draait dubbel** — `auth` op de Mac mini (poort 1411) en `id`
      op docker (ook 1411). Beide geven 200. Bij een storing weet je niet
      welke stuk is. Zoek uit welke de apps gebruiken, migreer, zet de andere
      uit. Zolang dit niet beslist is staat pocketid met opzet níét in
      `docker_stacks_list` van de Mini: anders vault je de secrets van een
      dienst die je volgende maand uitzet.

---

## Grotere projecten

- [ ] **De upstream en de clientinstellingen van AdGuard staan nog nergens.**
      De blocklists en de rewrites zijn sinds 23-09 beschreven, de rest niet:
      de Quad9-upstream over DoH en wat er per client is ingesteld leven enkel
      in die container. De upstream is met opzet overgeslagen - één verkeerde
      waarde legt de naamresolutie van het hele huis plat, en dat verdient een
      eigen wijziging op een rustig moment.

      Let op bij het updaten van AdGuard zelf: hij werkt zichzelf NIET bij
      (geen timer, geen cron, geen auto_update in de config). Klik je op
      "Update now" in de UI, werk dan `adguard_version` en `adguard_checksum`
      in `roles/adguard/defaults/main.yml` mee bij. Doe je dat niet, dan zet
      de volgende run de oude binary terug - en dat is een DNS-onderbreking
      voor iedereen. Dat gebeurde op 22-09: de UI stond op v0.107.79, de rol
      op v0.107.71.

        curl -sL https://github.com/AdguardTeam/AdGuardHome/releases/download/v0.107.XX/checksums.txt | grep linux_amd64

- [ ] **Twee stacks op de Mini komen niet terug na een herstart van OrbStack.**
      Op 23-09 herstartte OrbStack om 08:34. Vijf van de zeven stacks kwamen
      vanzelf terug, `duplicati` en `shelfmark` niet - ze bleven op `exited`
      staan (137 en 255) terwijl hun compose `restart: unless-stopped` zegt.
      Met de hand weer opgestart.

      Zolang dat niet uitgezocht is, betekent elke herstart van OrbStack of
      van de Mini dat je back-updienst stil uit staat. Kijk naar de
      opstartvolgorde: allebei hangen ze aan paden onder
      `/Users/rubenclaes/Container` en Duplicati ook aan `/Volumes/media01`.
      Een volume dat er bij het starten nog niet is verklaart precies dit.

- [ ] **De Mac mini: van beschreven naar beheerd.**
      `host_vars/macmini.yml` beschrijft hem nu wél — brew-formules, casks,
      de zes compose-projecten die er draaien én in de repo staan, het pad van
      de clone, de docker-CLI en de drie NFS-exports. De droogloop
      (`stacks.yml --limit macmini --check --diff`) is groen en `Bring stacks
      up` meldt voor alle zes `ok`, dus een echte run herbouwt niets.

      Wat er nog te doen is:

      - [ ] **Eén keer echt draaien.** Tot dat gebeurd is, is het een
            beschrijving en geen herbouwpad. Er staat nu niets meer in de
            weg: expenseowl is uitgezet en gearchiveerd, dus de commit die de
            git-taak binnenhaalt (`04742c2`) gooit geen draaiende dienst meer
            om.
      - [ ] **Plex als cask.** Hij draait als
            `/Applications/Plex Media Server.app`, buiten Homebrew om. Zet je
            hem in `macos_casks` als `plex-media-server`, dan gaat brew over
            een bestaande installatie heen die hij niet geplaatst heeft.
            Eerst met de hand overzetten, dan pas beschrijven.
      - [ ] **OrbStack staat buiten Homebrew.** `macos_casks` noemt hem nu
            (dat is wat er draait, niet Docker Desktop), maar de installatie
            op de machine komt niet van brew. De eerste echte run struikelt
            daar mogelijk over; dan `brew install --cask orbstack --adopt`.
            De oude `docker`- en `docker-desktop`-cask-restjes wijzen naar een
            `/Applications/Docker.app` die niet meer bestaat en mogen weg.
      - [ ] **De NFS-exports één keer echt draaien.** `roles/nfs_exports`
            schrijft `/etc/exports` nu uit `nfs_exports_shares`, en
            `playbooks/nfs.yml -K` is het herbouwpad. Gedraaid is hij nog
            niet: tot dat gebeurd is, is ook dit een beschrijving. De
            template quote elk pad, dus `"/Volumes/SSD Nas"` komt er goed
            uit - dat is lokaal nagekeken, niet op de machine zelf.

- [ ] **De Duplicati-secrets roteren.** Ze staan sinds 22-09 niet meer hard
      in de compose-file: die leest nu `${SETTINGS_ENCRYPTION_KEY}` en
      `${DUPLICATI__WEBSERVICE_PASSWORD}` uit een `.env`, gevault onder
      `stacks` in `files/env/duplicati.env`, net als elke andere stack hier.
      De waarden zijn niet veranderd, dus er is niets herbouwd.

      Wat blijft: ze staan nog in de historie van `rubenclaes/homelab`, en
      die krijg je er niet uit zonder de historie te herschrijven. Roteren is
      het echte antwoord, maar het is niet gratis:

      - `DUPLICATI__WEBSERVICE_PASSWORD` is gewoon een wachtwoord - nieuwe
        waarde in de vault, stack opnieuw uitrollen, klaar.
      - `SETTINGS_ENCRYPTION_KEY` ontsleutelt Duplicati's eigen
        instellingen-database. Verander je die zomaar, dan kan hij zijn
        configuratie niet meer lezen en mag je al je back-upjobs opnieuw
        aanmaken. Dat hoort via Duplicati zelf te gaan, niet via een
        variabele.

      Doe dat eerste stuk gerust los; het tweede vraagt een rustig moment.

- [ ] **De monitoring-stack herstart bij de eerste beheerde run.**
      `docker compose up --dry-run` op docker-grafana-stack zegt Recreate voor
      grafana, prometheus, loki en alloy: ze zijn ooit met een andere config
      gestart dan wat er nu in de compose-file en de `.env` staat. Te
      overleven — hun data staat in `${DATA_PATH}` — maar plan het, want het
      is een onderbreking van precies het ding dat je onderbrekingen moet
      melden.

- [ ] **Action1 voor de pc van de ouders**, en voor de Macs.

---

## Klein, wanneer het uitkomt

- [ ] **VS Code mag het LAN niet op vanuit Python, iTerm wel.**
      De Local Network-toestemming van macOS 26 staat sinds 22-09 aan voor
      iTerm, en daar werkt alles: de Proxmox-inventory laadt, `adguard.yml`
      draaide, `caddy-smoketest.yml` geeft "All 26 sites respond". Onder
      VS Code niet: die sessie draait als `Code Helper (Plugin)` onder
      `/Applications/Visual Studio Code.app` en dat bundel heeft de
      toestemming niet, dus daar geeft Python nog steeds `[Errno 65]`.
      Niet dringend - playbooks draai je in iTerm - maar het is wel de reden
      dat een agent in VS Code de dynamische inventory niet kan lezen. Wil je
      het gelijktrekken: vinkje aan voor Visual Studio Code, en dan cmd-Q en
      opnieuw open, want een draaiend proces pakt het niet op.

- [ ] **Vault-wachtwoorden roteren.** Tijdens het opzetten zijn de eerste
      tekens van beide in een sessielog terechtgekomen.
      `ansible-vault rekey --new-vault-id infra@<bestand>`.
- [ ] **Mac mini draait macOS 14.6.1** — updaten via Action1.
