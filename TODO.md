# Backlog

Per punt één zin over wat er moet gebeuren, en één over waarom. De volgorde
is de volgorde: bovenaan staat wat je het eerst wil oplossen.

De volledige geschiedenis van wat af is staat in `git log`, niet hier.

---

## Nu — hier kan iets misgaan

---

## Aanzetten — de code staat er, jij moet nog iets doen

---

## Semaphore — automatiseren wat nu van jouw geheugen afhangt

- [ ] **`drift.yml` op een schema zetten.** Geschreven, nog niet gedraaid.
      Draait `site.yml --check --diff` en vat samen: per host één regel, dan
      de taken die zouden wijzigen. Met `-e drift_fail=true` wordt hij rood
      bij drift, en dat is de versie die op een schema hoort. Let op: dit
      werkt pas als de droogloop groen kan zijn, dus na de twee
      vault-bestanden hierboven.

- [ ] **`site.yml` op een schema zetten, met een melding als hij faalt.**
      Dit is de grootste winst die er ligt en het kost nul regels code. Nu
      trek je alles gelijk als je eraan denkt; met een schema repareert drift
      zichzelf. Een geplande job die stilletjes faalt is wel erger dan geen
      job, dus de melding hoort erbij.

- [ ] **"Cleanup (apply)" als tweede template**, met `cleanup_apply: true`,
      zaterdag 03:00. Zonder die versie ruimt de rapportversie nooit iets op.

Alle vier de Semaphore-punten zijn UI-werk: de rol installeert en configureert
Semaphore, maar beheert geen templates. Wie ze in code wil, moet ze eerst via
de API beschrijven.

---

## Opruimen in de estate

- [ ] **`openbooks` draait zonder route**, alleen op `192.168.0.15:8080`.
      Geef hem een naam of zet hem uit, maar kies.

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
      - [ ] **De NFS-exports horen in een rol.** Ze staan nu opgeschreven in
            `host_vars/macmini.yml` en de docker-host mount ze alle drie, maar
            niets zet ze terug als de Mini opnieuw opgebouwd wordt.

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
