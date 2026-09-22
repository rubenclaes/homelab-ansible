# Backlog

Per punt één zin over wat er moet gebeuren, en één over waarom. De volgorde
is de volgorde: bovenaan staat wat je het eerst wil oplossen.

De volledige geschiedenis van wat af is staat in `git log`, niet hier.

---

## Nu — hier kan iets misgaan

- [ ] **De PBS-encryptiesleutel staat nergens buiten pve01.**
      Hij staat op `/etc/pve/priv/storage/pbs.enc` (gecontroleerd 22-09).
      `proxmox-backup-client key paperkey` geeft er een uitprintbare versie
      van. Uitprinten, buiten het huis leggen. Ben je pve01 én de sleutel
      kwijt, dan is elke back-up die je ooit maakte onleesbaar. Vijf minuten
      werk, en alles hangt ervan af.

- [ ] **De Semaphore-template "Update guests" patcht Semaphore zelf.**
      Zet de limit op `guests:!semaphore`; die machine patch je met de hand.
      Herstart Semaphore halverwege, dan is de job dood en weet je niet of de
      upgrade af is.

- [ ] **Deze MacBook mag het LAN niet op vanuit Python.**
      `curl`, `ssh` en `nc` komen bij 192.168.0.x, Python niet: elke poging
      geeft `[Errno 65] No route to host`. Dat is de Local Network-toestemming
      van macOS 26. Gevolg: de Proxmox-inventoryplugin werkt hier niet, dus
      `site.yml`, `drift.yml` en `stacks.yml` vinden hun hosts niet,
      `caddy-smoketest.yml` meldt álle sites stuk terwijl ze het doen (die
      test draait `delegate_to: localhost`), en `restore-drill.yml` haalt
      zijn vijf inventory-controles wél maar valt daarna om op "Lees de
      guests die op de node bestaan" - ook een API-taak op localhost. Zet hem aan onder
      Systeeminstellingen -> Privacy en beveiliging -> Lokaal netwerk, voor de
      app die Claude Code draait. Tot dan is er van deze Mac uit alleen met de
      hand een statische inventory te draaien.

---

## Aanzetten — de code staat er, jij moet nog iets doen

- [ ] **`inventory/host_vars/adguard/vault.yml` aanmaken.**
      `vault_adguard_api_user` en `vault_adguard_api_password`, identiteit
      `infra`. Tot dan faalt `site.yml` op `adguard`, met opzet: een lijst die
      stil niet meer wordt toegepast is erger dan een rode run.

- [ ] **Tailscale OAuth-client maken** en in
      `inventory/host_vars/tailscale/vault.yml` zetten. Scope `auth_keys`, tag
      `tag:homelab`, en die tag moet in de policy onder `tagOwners` staan.
      Zonder client blijft aanmelden na een herbouw handwerk. Wat de node nu
      adverteert hoort in `tailscale_up_extra_args`.

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

- [ ] **Twee verweesde PBS-groepen** — `ct/109` en `vm/110`, van guests die
      niet meer bestaan. Elk één snapshot van 18-09, samen ~57 GB. Ze staan er
      nog: `pve@pbs` heeft alleen `DatastoreBackup` en mag niet verwijderen,
      dus `pvesm free` geeft "missing Datastore.Modify|Datastore.Prune".
      Weghalen doe je in de PBS-UI (Datastore -> store1 -> Content -> groep ->
      Forget), of door `pve@pbs` tijdelijk `DatastorePowerUser` op
      `/datastore/store1` te geven. Een back-uplijst met groepen die nergens
      bij horen lees je na een half jaar niet meer met vertrouwen.

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

- [ ] **`expenseowl` draait op de Mini maar staat in geen repo meer.**
      Commit `04742c2` in `rubenclaes/homelab` gooide zijn compose-file weg,
      samen met die van Prowlarr, Sonarr, Radarr, Seerr, audiobookshelf en
      Flareresolver. Voor die zes klopt dat — ze draaien op de docker-VM. Voor
      expenseowl niet: die draait alléén daar. De checkout op de Mini staat
      één commit achter, dus het bestand staat er lokaal nog; de eerste
      beheerde run haalt die commit binnen en dan is het weg. Kies: terugzetten
      in de repo, of de dienst uitzetten.

- [ ] **`tinyauth` bestaat niet meer, maar de machinerie wel.**
      De route is weg (22-09), maar `caddy_tinyauth_upstream` in
      `host_vars/caddy/main.yml` en het snippet `tinyauth_forwarder` in de
      Caddyfile staan er nog. Geen enkele site zet `auth: true`, dus het
      snippet wordt nooit geïmporteerd en de var wijst naar een dode poort.
      Komt tinyauth niet terug, dan kunnen beide weg.

---

## Grotere projecten

- [ ] **De Mac mini: van beschreven naar beheerd.**
      `host_vars/macmini.yml` beschrijft hem nu wél — brew-formules, casks,
      de zes compose-projecten die er draaien én in de repo staan, het pad van
      de clone, de docker-CLI en de drie NFS-exports. De droogloop
      (`stacks.yml --limit macmini --check --diff`) is groen en `Bring stacks
      up` meldt voor alle zes `ok`, dus een echte run herbouwt niets.

      Wat er nog te doen is:

      - [ ] **Eén keer echt draaien.** Tot dat gebeurd is, is het een
            beschrijving en geen herbouwpad. De git-taak trekt dan commit
            `04742c2` binnen — zie het expenseowl-punt hierboven, doe dat
            eerst.
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

- [ ] **Secrets staan hard in `Duplicati/docker-compose.yml`** in
      `rubenclaes/homelab` - `SETTINGS_ENCRYPTION_KEY` en
      `DUPLICATI__WEBSERVICE_PASSWORD`, beide `helipost`. De repo is privé,
      dus dit is geen brand, maar ze staan in de historie en zijn niet te
      roteren zonder de compose-file aan te raken. Naar een `.env`, en dan
      naar `files/env/duplicati.env` onder de `stacks`-identiteit, zoals elke
      andere stack hier. De stack staat al in `docker_stacks_list` met
      `env: false`; dat wordt dan weer de standaard.

- [x] **Niets bewijst dat een back-up terugkomt.** `restore-drill.yml`
      geschreven: zet de nieuwste PBS-back-up van één guest terug op vmid 199,
      haalt net0 eraf zodat hij niet botst met het origineel, start hem, leest
      er één bestand uit en sloopt hem. De paden die hij controleert staan per
      guest in `drill_probes` in `lxcs.yml`.

      - [ ] **Nog nooit gedraaid.** Tot je hem één keer draait bewijst hij
            precies evenveel als geen drill. De `--check` is op 22-09 wél
            geprobeerd: de vijf controles vooraf komen door (guest bekend,
            vmid 199 niet geclaimd), maar daarna heeft hij de Proxmox-API
            nodig vanaf de controller. Vanaf deze Mac kan dat nu niet - zie
            het Local Network-punt bovenaan. Draai hem dus vanuit Semaphore,
            of nadat die toestemming aan staat. LXC-only, met opzet - een
            teruggezette VM op hetzelfde netwerk botst op MAC en IP met het
            origineel, en daar is geen veilige automatisering voor.
      - [ ] **Daarna op een schema in Semaphore.** Een drill die je alleen
            draait als je eraan denkt, draai je precies niet in het half jaar
            waarin de back-ups stilletjes stukgaan.

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

- [ ] **Vault-wachtwoorden roteren.** Tijdens het opzetten zijn de eerste
      tekens van beide in een sessielog terechtgekomen.
      `ansible-vault rekey --new-vault-id infra@<bestand>`.
- [ ] **`~/.ssh/config` opruimen** — pv01-typo, `pve01-unifi-os` weg, nieuwe
      hosts samenvoegen. (De rechten zijn al goed: `0600`, gecontroleerd 22-09.)
- [ ] **Mac mini draait macOS 14.6.1** — updaten via Action1.
