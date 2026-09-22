# Backlog

Elk punt zegt **wat** er moet gebeuren en **waarom**. Zonder het waarom is een
backlog na drie maanden niet meer te lezen.

---

## Eerst dit — er kan nu iets misgaan

- [ ] **De PBS-encryptiesleutel staat nergens buiten pve01**
      `proxmox-backup-client key show`, uitprinten, buiten het huis leggen.
      *Waarom:* de back-ups op de PBS-opslag zijn versleuteld. Ben je pve01 én
      de sleutel kwijt, dan is er niets terug te zetten en is elke back-up die
      je ooit hebt gemaakt waardeloos. Dit is vijf minuten werk en het is het
      enige punt op deze lijst waar alles van afhangt.

- [ ] **Semaphore: "Update guests" raakt Semaphore zelf**
      De template draait `--limit guests`, en `semaphore` zit in die groep. De
      job doet dus `apt full-upgrade` op de machine waarop hij zelf draait.
      *Waarom:* als Semaphore halverwege herstart is de job dood en weet je
      niet of de upgrade af is. Zet de limit op `guests:!semaphore` en patch
      semaphore met de hand of vanaf het werkstation.

- [ ] **PBS: de wekelijkse job (`backup-e6cc3e8b-ac39`) heeft nog nooit een
      backup gemaakt** — gecontroleerd op 21-09
      Storage `local` heeft content `vztmpl,import,iso`, geen `backup`-type.
      `vzdump` breekt daarom af vóór hij de vmid-lijst leest;
      `/var/log/pve/tasks/index` toont bij elke run "can't use storage
      'local' for backups - wrong content type" en `/var/lib/vz/dump` is
      leeg. Dit stond eerder genoteerd als "faalt door vmid 109" — dat klopt
      niet, en het weglaten van 109 heeft er dus niets aan veranderd.
      *Waarom:* zolang dit als "opgelost" te boek staat, kijkt niemand er
      nog naar. Oplossen is een keuze met gevolgen voor opslag/retentie:
      `backup` toevoegen aan `local`'s content, of de job retargeten naar
      `pbs` zoals de dagelijkse job al doet. Bewust hier geparkeerd, niet in
      de proxmox-rebuild-path-branch.

---

## Inrichten — de code staat er, deze handelingen niet

- [ ] **AdGuard: `inventory/host_vars/adguard/vault.yml` aanmaken**
      `vault_adguard_api_user` en `vault_adguard_api_password`, identiteit
      `infra`. *Waarom:* tot dan faalt `site.yml` op `adguard` met een assert
      die dit zegt — bewust, zie de spec. Controleer daarna de eerste run met
      `--check`: het rapport toont welke `*.home.arpa`-namen erbij komen.

- [ ] **AdGuard: *Sta onversleutelde DNS-over-HTTPS toe* aanzetten, en de
      webpoort in `caddy_doh_upstream` nakijken**
      Het staat op `:80`, wat AdGuards gebruikelijke keuze na de wizard is,
      maar niet gecontroleerd. *Waarom:* zonder de schakelaar geeft
      `dns.neodata.be/dns-query` een 404 en heeft een telefoon met het profiel
      geen DNS.

- [ ] **Tailscale: OAuth-client maken en in `inventory/host_vars/tailscale/vault.yml` zetten**
      Scope `auth_keys`, tag `tag:homelab`; die tag moet in de policy onder
      `tagOwners` staan. *Waarom:* zonder client blijft aanmelden na een
      herbouw handwerk. Wat de node nu adverteert (subnet-routes?) hoort in
      `tailscale_up_extra_args`, anders weigert `tailscale up`.

- [ ] **`devices.yml` vullen met echte toestellen**
      De vier regels zijn voorbeelden met verzonnen MAC-adressen. *Waarom:*
      elk voorbeeld met een `ip` krijgt een `*.home.arpa`-naam in AdGuard.
      De MAC-adressen en de vaste adressen haal je uit UniFi, onder Clients;
      de reservering zelf zet je daar met de hand.

---

## Opruimen in de estate

- [ ] **PBS: twee verweesde groepen** — `ct/109` en `vm/110`
      Ze horen bij guests die niet meer bestaan.
      *Waarom:* een back-uplijst waarin groepen staan die nergens bij horen,
      lees je na een half jaar niet meer met vertrouwen. Opruimen is vijf
      minuten; uitzoeken wat ct/109 ook alweer was, niet.

- [ ] **Vier diensten draaien door zonder route**
      `wizarr`, `dozzle`, `jackett` en `tautulli` zijn uit `caddy_sites`
      gehaald, maar de processen draaien nog op de Mac mini. Ze staan niet in
      `docker_stacks_list`, dus geen playbook zet ze stil.
      *Waarom:* iets dat draait maar geen naam meer heeft, kost geheugen en
      valt bij een storing niemand op. Zet ze met de hand uit op de Mini.
      Let op: Sonarr of Radarr kunnen Jackett nog als indexer hebben staan —
      Prowlarr doet dat werk al.

- [ ] **`openbooks` draait zonder route**
      Alleen bereikbaar als `192.168.0.15:8080`.
      *Waarom:* of hij verdient een naam, of hij hoeft niet te draaien.
      Allebei goed, maar kies.

- [ ] **Pocket ID draait dubbel**
      `auth` op de Mac mini (.26) en `id` op docker (.15).
      *Waarom:* twee identity providers betekent dat je bij een storing niet
      weet welke stuk is. Zoek uit welke de apps gebruiken, migreer, zet de
      andere uit.

---

## Repo zelf

- [ ] **Geen tests**
      Lint en `--syntax-check` zijn spellingscontrole. Niets bewijst dat een
      rol op een schone machine werkt.
      *Waarom:* `playbooks/recovery-drill.yml` geeft je 80% van die zekerheid
      voor veel minder werk. Molecule is pas daarna interessant.

---

## Semaphore

- [ ] **Notificaties bij mislukte taken (Telegram of e-mail)**
      *Waarom:* een geplande job die stilletjes faalt is erger dan geen job.
      Nu merk je het pas als je gaat kijken.

- [ ] **"Cleanup (apply)" als tweede template**
      Naast de bestaande report-versie, met `cleanup_apply: true`, zaterdag
      03:00.
      *Waarom:* de report-versie laat alleen zien wat er zou gebeuren. Zonder
      de apply-versie wordt er nooit iets opgeruimd.

---

## Klein, wanneer het uitkomt

- [ ] **`~/.ssh/config` staat op `0644`**
      De volgende echte `dotfiles.yml`-run zet hem op `0600`.
      *Waarom:* het bestand noemt je hosts, gebruikers en sleutelpaden. Op een
      Mac met één gebruiker is het risico klein, maar `0600` is de norm.

- [ ] **Vault-wachtwoorden roteren**
      *Waarom:* tijdens het opzetten zijn de eerste twaalf tekens van beide
      wachtwoorden in een sessielog terechtgekomen. Roteren is goedkoop:
      `ansible-vault rekey --new-vault-id infra@<bestand>`.

- [ ] **Dubbele docker / docker-desktop casks (MBP + Mini)** — met de hand
- [ ] **Mini: `brew leaves` → `host_vars/macmini.yml`** (het `_extra`-patroon)
- [ ] **`~/.ssh/config` opruimen** (pv01-typo, `pve01-unifi-os` weg, nieuwe hosts samenvoegen)
- [ ] **Mac mini draait macOS 14.6.1** — updaten via Action1
---

## Volgende projecten

- [ ] **Action1 voor de pc van de ouders (+ Macs)**

---

## Done
- [x] GitHub-actions op hun huidige versies (checkout v7, setup-python v7, cache v6) en de workflow leest alleen nog
- [x] README omgebouwd tot stappenplan: eenmalig opzetten, wat wil je doen, hoe voer je een wijziging door, wat als het misgaat
- [x] Herstelrunbook met het volledige terugzetten erin, inclusief `pct restore` en `qmrestore` en de omgekeerde argumentvolgorde
- [x] CI is groen: de twee "bestaande" lint-overtredingen zijn opgelost zonder de uitvoer te veranderen, en de workflow is nu ook handmatig te starten op een branch
- [x] `new-guest.yml`: één commando van lege lijstregel tot gebaselinede container, met een runbook in gewone taal ernaast
- [x] Toestellen krijgen hun filterbeleid uit `devices.yml`: een client per toestel in AdGuard, met safe search, geblokkeerde diensten en een schema
- [x] De UniFi-rol weer verwijderd: een reservering zetten is twintig seconden klikken en woog niet op tegen een account, een vault en andermans API onderhouden
- [x] `*.home.arpa`-namen voor hosts en toestellen in AdGuard, via de API; het scherm blijft eigenaar van `AdGuardHome.yaml`
- [x] `roles/tailscale` meldt een node zelf aan met een eenmalige sleutel; `tailscale-key.yml` maakt er een per toestel
- [x] DNS-profiel per telefoon op `docs.<domain>/profielen/`, met de toestelnaam als AdGuard-client-ID
- [x] Media-stack onder Ansible: `media` staat in `docker_stacks_list` als project `media-stack`
- [x] PBS back-upt ook LXC 104 (semaphore) — de job draait 101,102,103,104,106,107,108
- [x] `torrent`-route leeft weer: qbittorrent kwam mee met de media-stack, precies zoals het item voorspelde
- [x] wizarr, dozzle, jackett en tautulli uit `caddy_sites` en van `/diensten`
- [x] Herstelpad bewezen: recovery-drill.yml bouwt, bootstrapt, baselinet en vernietigt een wegwerp-LXC
- [x] caddy-upgrade.yml: upgradet en weigert als de Cloudflare-module verdwijnt
- [x] SystemMaxUse=500M op alle acht hosts (docker-grafana-stack stond op 276M)
- [x] Finder-restart handler bij de macOS-defaults
- [x] Beszel-data verwijderd; cleanup gedraaid met apply (2.3 GB vrij)
- [x] caddy-smoketest.yml werkt nu ook onder --check
- [x] Tags per play: `site.yml --tags dns` draait alleen dat stuk
- [x] bootstrap.yml weigert meer dan één host tegelijk
- [x] requirements.txt pint de toolchain gelijk aan CI

- [x] Provisioning compleet: caddy, docker-engine, adguard, tailscale en pbs worden nu geïnstalleerd, niet alleen geconfigureerd
- [x] `site.yml --check` meldt `changed=0` op alle tien hosts — idempotentie eindelijk aangetoond
- [x] Documentatiesite in het Nederlands; runbooks kloppen weer met de playbooks
- [x] Rapport laat route-drift zien: routes zonder container, containers zonder route, stacks buiten Ansible
- [x] evcc en trek routes weg; glance en azuracast verwijderd; beszel uit de infra-stack
- [x] BESZEL_TOKEN/KEY uit de vaulted infra.env
- [x] Caddyfile-routes komen uit `caddy_sites`; upstreams via inventory-hostnaam
- [x] proxmox_lxc is list-driven vanuit `pve_lxcs` en heeft nu defaults/
- [x] docker_stacks ruimt orphans op als een service uit een compose verdwijnt
- [x] Inventory komt live uit Proxmox; hosts.yml is weg
- [x] API-token heeft VM.GuestAgent.Audit (beheerd via proxmox-access.yml)
- [x] qemu-guest-agent hoort bij de baseline voor KVM-guests
- [x] Vault gesplitst in twee identiteiten: `infra` en `stacks`
- [x] Pre-commit hook blokkeert een plaintext secret vóór de push, niet erna
- [x] Repo-hygiëne: .gitignore, vendored collections niet meer in Git (5164 bestanden)
- [x] Collections gepind in collections/requirements.yml
- [x] README geschreven (setup, bootstrap, updates, secrets, prerequisites)
- [x] update.yml gesplitst: guests vóór de hypervisor, aparte reboot-schakelaars
- [x] site.yml is het echte master-playbook
- [x] caddy-rol maakt zijn systemd drop-in map aan
- [x] dotfiles-rol faalt niet meer op een Mac zonder ~/.ssh/config
- [x] semaphore-rol geeft een duidelijke fout in plaats van "undefined"
- [x] Cloudflare-token geroteerd, in Vault, uitgerold via de caddy-rol
- [x] baseline_held_packages (caddy op hold)
- [x] ssh.socket vs ssh.service conflict opgelost in de baseline-rol
- [x] docker-grafana-stack, adguard, tailscale en semaphore onboarded
- [x] Caddyfile in Git + opgeruimd (unifi, downloads, automate weg)
- [x] Stacks onder Ansible: utils, homepage, metrics, rustdesk, portainer, neogate, infra, homebox
- [x] Alle docker .env-bestanden in Vault
- [x] Semaphore UI draait op semaphore.neodata.be
