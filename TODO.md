# Backlog

Per punt één zin over wat er moet gebeuren, en één over waarom. De volgorde
is de volgorde: bovenaan staat wat je het eerst wil oplossen.

De volledige geschiedenis van wat af is staat in `git log`, niet hier.

---

## Nu — hier kan iets misgaan

---

## Aanzetten — de code staat er, jij moet nog iets doen

- [ ] **`dns-smoketest.yml` op een schema zetten.** Geschreven en gelint,
      nog niet gedraaid. Hij vraagt elke `<host>.home.arpa` bij AdGuard op en
      vergelijkt met het adres uit de inventory, plus één publieke naam voor
      de forwarding. Hoort naast `drift.yml` in Semaphore: sinds 22-09 loopt
      de hele estate via één LXC, en dat is precies het soort ding dat je
      niet wil ontdekken op het moment dat je het nodig hebt.

      Let op: hij roept `dig` aan op de host die hem draait. `dnsutils` staat
      daarom sinds vandaag in `baseline_packages`, maar dat betekent dat
      Semaphore eerst een `site.yml` gezien moet hebben voor het schema werkt.

---

## Semaphore — automatiseren wat nu van jouw geheugen afhangt

De vier punten die hier stonden zijn geen UI-werk meer.
`roles/semaphore_templates` beschrijft de templates én hun cron via de API, en
ze staan in `semaphore_templates_list` in `inventory/host_vars/semaphore/`:
Site (apply) zondag 03:00, Drift (report) dagelijks 06:00, Cleanup (apply)
zaterdag 03:00, Restore drill de 1e van de maand, en Update guests met
`--limit guests:!semaphore` zonder schema. Wat rest staat hieronder.

- [ ] **`inventory/host_vars/semaphore/vault.yml` aanmaken.** Zonder dat
      bestand faalt de rol meteen, en dat is met opzet - een sync die
      stilletjes overslaat is erger dan een rode run.

          ansible-vault create --encrypt-vault-id infra \
            inventory/host_vars/semaphore/vault.yml

      Met `vault_semaphore_api_user` en `vault_semaphore_api_password`: de
      login van de web-UI.

- [ ] **`semaphore-templates.yml` eerst met `--check` draaien, dan echt.**
      Lees de rapportageregel voor je hem loslaat. `name` is de sleutel:
      staat er iets onder `create` dat je dacht bij te werken, dan wijkt de
      naam af van wat er nu in de UI staat en zou je een tweede template
      maken naast de bestaande.

      De rol is tegen een nagebouwde API getest - aanmaken, bijwerken,
      schema's, en drie runs achter elkaar zonder wijziging - maar nog nooit
      tegen jouw Semaphore. De eerste echte run is het bewijs.

- [ ] **Een melding als een geplande job faalt.** Dit staat nog steeds open
      en de rol lost het niet op: hij zet schema's, geen alerting. Een
      geplande job die stilletjes faalt is erger dan geen job.

- [ ] **`semaphore-templates.yml` in `site.yml` zetten**, zodra die eerste
      echte run groen was. Eén regel. Nu bewust nog niet: een ongeteste
      API-aanroep hoort niet in het playbook dat alles gelijktrekt.

---

## Opruimen in de estate

- [ ] **De VPN deelt de verkeerde DNS uit.** WireGuard op de UniFi-gateway
      geeft clients `192.168.0.26` mee - de AdGuard op de Mac mini, precies
      degene die uit moet. Zet hem in de UniFi-controller op `192.168.0.29`
      en download het iPhone-profiel opnieuw: de clientconfiguratie heeft die
      waarde ingebakken, dus alleen serverzijde wijzigen is niet genoeg.
      **Doe dit vóór je de AdGuard op de Mini uitzet**, anders heeft je VPN
      geen naamresolutie meer. AdGuard op `.29` beperkt geen clients, dus
      `10.10.30.x` mag meteen vragen stellen.

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

- [ ] **AdGuard werkt zichzelf bij, en de rol pint een versie. Kies.**
      Op 23-09 stond de rol op `v0.107.71` terwijl er `v0.107.79` draaide: hij
      had zichzelf bijgewerkt. De pin is bijgetrokken zodat de rol hem niet
      terugzet, maar dat is uitstel - bij de volgende zelf-update staat het er
      weer. Twee eerlijke antwoorden:

      - zelf-bijwerken uitzetten in AdGuard, en de pin gaat weer ergens over.
        Dan bepaal jij wanneer de DNS van het huis een nieuwe binary krijgt.
      - de pin laten vallen en `state: latest`-gedrag accepteren. Dan is het
        beschreven, maar niet meer beheerst.

      Wat niet werkt is allebei half, zoals nu. De rol wilde de DNS van het
      hele huis downgraden, en dat werd alleen tegengehouden door een fout
      elders (`unarchive` kreeg een `checksum`-parameter die niet bestaat;
      die is nu opgelost met `get_url`).

      De blocklists zijn wél beschreven sinds 23-09. Wat nog niet in de rol
      staat: de Quad9-upstream over DoH en de clientinstellingen. Die upstream
      is met opzet overgeslagen - één verkeerde waarde legt de naamresolutie
      van het hele huis plat, en dat verdient een eigen wijziging.

- [ ] **De AdGuard op de Mac mini uitzetten.** Al het andere is af: sinds
      22-09 loopt de hele estate via de LXC op `192.168.0.29`, die Ansible
      beheert en PBS meeneemt - hosts, containers en DHCP. Het waarom staat
      in de netwerk-runbook.

      Wat rest is de Mini zelf. Zijn AdGuard draait nog en hij wijst met de
      hand naar zichzelf, op zowel `Ethernet` als `USB 10/100/1G/2.5G LAN`
      (en7 is de actieve). Handmatig ingesteld, dus DHCP bereikt hem niet.
      `sudo` vraagt daar een wachtwoord, dus dit is handwerk:

        ssh -t macmini 'sudo networksetup -setdnsservers "USB 10/100/1G/2.5G LAN" 192.168.0.29 1.1.1.1'
        ssh -t macmini 'sudo networksetup -setdnsservers "Ethernet" 192.168.0.29 1.1.1.1'
        ssh macmini 'dig +short pve01.home.arpa; dig +short books.neodata.be'

      Verwacht `192.168.0.14` en `192.168.0.25`. Klopt dat, pas dán:

        ssh -t macmini 'sudo /Applications/AdGuardHome/AdGuardHome -s stop'

      Omkeerbaar met `-s start`. LET OP dat hij bij een herstart van de Mini
      gewoon terugkomt - denk je dat hij uit is, dan heb je er stilletjes
      weer twee. Definitief weg is `-s uninstall`, als je een paar dagen
      zeker weet dat je hem niet mist.

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
