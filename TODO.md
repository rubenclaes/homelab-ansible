# Backlog

Per punt één zin over wat er moet gebeuren, en één over waarom. De volgorde
is de volgorde: bovenaan staat wat je het eerst wil oplossen.

De volledige geschiedenis van wat af is staat in `git log`, niet hier.

---

## Nu — hier kan iets misgaan

- [ ] **De Semaphore-template "Update guests" patcht Semaphore zelf.**
      Zet de limit op `guests:!semaphore`; die machine patch je met de hand.
      Herstart Semaphore halverwege, dan is de job dood en weet je niet of de
      upgrade af is.

---

## Aanzetten — de code staat er, jij moet nog iets doen

- [ ] **Wat de node nu adverteert hoort in `tailscale_up_extra_args`.**
      Nu staat het alleen in de staat van die ene container.

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

- [ ] **`tinyauth` bestaat niet meer, maar de machinerie wel.**
      De route is weg (22-09), maar `caddy_tinyauth_upstream` in
      `host_vars/caddy/main.yml` en het snippet `tinyauth_forwarder` in de
      Caddyfile staan er nog. Geen enkele site zet `auth: true`, dus het
      snippet wordt nooit geïmporteerd en de var wijst naar een dode poort.
      Komt tinyauth niet terug, dan kunnen beide weg.

---

## Grotere projecten

- [ ] **AdGuard draait dubbel, en de verkeerde is de echte.**
      Er draaien er twee. De LXC op 192.168.0.29 is degene die deze repo
      beheert; daar staan sinds 22-09 de tien `home.arpa`-rewrites in, en hij
      beantwoordt ze correct. Alleen: niemand vraagt het hem. Elke beheerde
      host wijst in `/etc/resolv.conf` naar **192.168.0.26**, de Mac mini, en
      daar draait een tweede AdGuard Home als macOS-app
      (`/Applications/AdGuardHome/AdGuardHome`). Die doet het echte werk: een
      wildcard `*.neodata.be -> 192.168.0.25` (nagekeken met een naam die niet
      bestaat, die ook 192.168.0.25 teruggeeft). De LXC kent die namen juist
      weer níét.

      Gevolg nu: die tien rewrites doen praktisch niets. En erger, de DNS van
      de hele estate hangt aan de Mac mini - dezelfde machine die de drie
      NFS-shares exporteert en die deze backlog al aanwijst als het ding dat
      je niet kunt terugbouwen. Valt hij om, dan valt naamresolutie voor elke
      host om.

      De rol zegt in zijn eigen commentaar "this host is the network's DNS"
      over de LXC. Dat is nu simpelweg niet waar.

      De weg eruit, en hij is kort:

      - [ ] Zet in de LXC-AdGuard met de hand een wildcard
            `*.neodata.be -> 192.168.0.25` erbij. De rol raakt rewrites
            buiten `home.arpa` niet aan, dus dat blijft staan.
      - [ ] Laat de UniFi-DHCP 192.168.0.29 als DNS uitdelen in plaats van
            192.168.0.26, en zet de vaste resolv.conf van de guests mee om.
      - [ ] Controleer met `dig @192.168.0.29 books.neodata.be` én
            `dig @192.168.0.29 pve01.home.arpa` dat beide werken vóór je
            omschakelt, niet erna.
      - [ ] Daarna de AdGuard op de Mini uitzetten, of bewust als tweede
            resolver laten staan - maar kies, want twee DNS-servers waarvan
            er één stilletjes de echte is, is precies hoe je tijdens een
            storing een uur kwijtraakt.

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

      - [ ] **Nog nooit echt gedraaid.** De droogloop is op 22-09 wél
            helemaal doorgekomen, vanuit iTerm: `ok=11, changed=0,
            failed=0`, alles wat schrijft netjes overgeslagen. Hij zou
            `pbs:backup/ct/107/2026-09-22T00:34:14Z` van adguard terugzetten
            op vmid 199 op `vm-hdd` en daar
            `/opt/AdGuardHome/AdGuardHome.yaml` in zoeken; er staan vijf
            back-ups van die guest klaar. Alles wat eraan vooraf gaat klopt
            dus. Wat nog niet bewezen is, is het enige dat telt: dat die
            back-up ook echt terugkomt. Draai hem één keer zonder `--check`:

              ansible-playbook playbooks/restore-drill.yml -e drill_confirm=true

            Een gefaalde drill laat het wrak staan, met opzet. Opruimen met
            `pct destroy 199`. LXC-only, met opzet - een
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
- [ ] **`~/.ssh/config` opruimen** — pv01-typo, `pve01-unifi-os` weg, nieuwe
      hosts samenvoegen. (De rechten zijn al goed: `0600`, gecontroleerd 22-09.)
- [ ] **Mac mini draait macOS 14.6.1** — updaten via Action1.
