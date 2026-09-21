# Backlog

Elk punt zegt **wat** er moet gebeuren en **waarom**. Zonder het waarom is een
backlog na drie maanden niet meer te lezen.

---

## Eerst dit — er kan nu iets misgaan

- [ ] **Semaphore: "Update guests" raakt Semaphore zelf**
      De template draait `--limit guests`, en `semaphore` zit in die groep. De
      job doet dus `apt full-upgrade` op de machine waarop hij zelf draait.
      *Waarom:* als Semaphore halverwege herstart is de job dood en weet je
      niet of de upgrade af is. Zet de limit op `guests:!semaphore` en patch
      semaphore met de hand of vanaf het werkstation.

- [ ] **Media-stack onder Ansible brengen**
      `media-stack` draait op docker (immich, openbooks, qbittorrent) maar
      staat niet in `docker_stacks_list`. Het rapport laat hem zien onder
      "Stacks buiten Ansible".
      *Waarom:* wat niet in de lijst staat, wordt bij een herbouw niet
      teruggezet. Immich heeft een postgres — doe dit op een rustig moment.
      Waarschijnlijk lost het meteen de dode `torrent`-route op, want
      qbittorrent zit in deze stack.

- [ ] **PBS: semaphore (LXC 104) heeft GEEN backup** — gecontroleerd op 21-09
      Alle andere guests zitten erin (101,102,103,106,107,108), 104 niet.
      De jobs draaien 02:30, updates 04:00 — dat botst dus niet.
      Er staan ook twee verweesde groepen in PBS: ct/109 en vm/110 horen
      bij guests die niet meer bestaan.
      *Waarom:* Semaphore draait alle andere playbooks. Als die container weg
      is en geen backup heeft, herbouw je hem met de hand terwijl je juist
      dán automatisering wil.

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

## Opruimen in de estate

- [ ] **Route `torrent` wijst nergens heen**
      `torrent.neodata.be` → `:8089`, daar luistert niets.
      *Waarom:* een naam die niets doet kost je een keer tien minuten zoeken.
      Lost zichzelf mogelijk op met de media-stack hierboven; anders weg.

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
      *Waarom:* het herstelpad hierboven geeft je 80% van die zekerheid voor
      veel minder werk. Molecule is pas daarna interessant.

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
