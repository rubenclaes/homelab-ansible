# Backlog

Per punt één zin over wat er moet gebeuren, en één over waarom. De volgorde
is de volgorde: bovenaan staat wat je het eerst wil oplossen.

De volledige geschiedenis van wat af is staat in `git log`, niet hier.

---

## Nu — hier kan iets misgaan

- [ ] **De PBS-encryptiesleutel staat nergens buiten pve01.**
      `proxmox-backup-client key show`, uitprinten, buiten het huis leggen.
      Ben je pve01 én de sleutel kwijt, dan is elke back-up die je ooit maakte
      onleesbaar. Vijf minuten werk, en alles hangt ervan af.

- [ ] **De Semaphore-template "Update guests" patcht Semaphore zelf.**
      Zet de limit op `guests:!semaphore`; die machine patch je met de hand.
      Herstart Semaphore halverwege, dan is de job dood en weet je niet of de
      upgrade af is.

- [ ] **De wekelijkse PBS-job heeft nog nooit een back-up gemaakt** —
      `backup-e6cc3e8b-ac39`, gecontroleerd op 21-09.
      Storage `local` mist het content-type `backup`, dus `vzdump` breekt af
      voordat hij de vmid-lijst leest. Kies: `backup` toevoegen aan `local`,
      of de job naar `pbs` richten zoals de dagelijkse al doet. De dagelijkse
      job dekt alles, dus het derde antwoord is hem weggooien.

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

- [ ] **`site.yml` op een schema zetten, met een melding als hij faalt.**
      Dit is de grootste winst die er ligt en het kost nul regels code. Nu
      trek je alles gelijk als je eraan denkt; met een schema repareert drift
      zichzelf. Een geplande job die stilletjes faalt is wel erger dan geen
      job, dus de melding hoort erbij.

- [ ] **"Cleanup (apply)" als tweede template**, met `cleanup_apply: true`,
      zaterdag 03:00. Zonder die versie ruimt de rapportversie nooit iets op.

---

## Opruimen in de estate

- [ ] **Twee verweesde PBS-groepen** — `ct/109` en `vm/110`, van guests die
      niet meer bestaan. Een back-uplijst met groepen die nergens bij horen
      lees je na een half jaar niet meer met vertrouwen.

- [ ] **Vier diensten draaien door zonder route** — `wizarr`, `dozzle`,
      `jackett` en `tautulli` op de Mac mini. Geen playbook zet ze stil, dus
      met de hand. Let op dat Sonarr of Radarr Jackett nog als indexer kunnen
      hebben; Prowlarr doet dat werk al. Doe dit vóór je de lijst van de Mini
      vult, anders beschrijf je vier diensten die je toch weghaalt.

- [ ] **`openbooks` draait zonder route**, alleen op `192.168.0.15:8080`.
      Geef hem een naam of zet hem uit, maar kies.

- [ ] **Pocket ID draait dubbel** — `auth` op de Mac mini en `id` op docker.
      Bij een storing weet je niet welke stuk is. Zoek uit welke de apps
      gebruiken, migreer, zet de andere uit.

---

## Grotere projecten

- [ ] **Twee hosts draaien diensten die geen playbook kan terugbouwen.**
      De Mac mini heeft zeven routes en `docker-grafana-stack` twee, en van
      geen enkele staat de stack in deze repo. Gaat de Mini stuk, dan zet jij
      Plex met de hand terug.

      De weg ernaartoe ligt er nu wel. `stacks.yml` is niet langer aan de host
      `docker` gebonden: elke host met een `docker_stacks_list` wordt beheerd,
      ook een Mac, want de Debian-only stukken van de rol staan apart in
      `roles/docker_stacks/tasks/linux.yml`. Beide hosts hebben een host_vars
      met de volgorde erin, en `playbooks/discover.yml` haalt op wat er nu
      echt draait.

      Wat er nog te doen is, per host:

      - [ ] `discover.yml --limit docker-grafana-stack`, compose-files naar de
            containers-repo, `docker_stacks_list` vullen. Dit is de kleine.
      - [ ] `discover.yml --limit macmini`, dan `brew leaves` en de casks
            overnemen. Dat alleen al maakt de software van de Mini
            herbouwbaar en kost niets.
      - [ ] De containers van de Mini naar de containers-repo, lijst vullen,
            de macOS-paden in zijn host_vars aanzetten.
      - [ ] `docs.yml` rendert `stacks.mdx` alleen uit de host `docker`. Zodra
            een tweede host een lijst heeft, is die pagina onvolledig. Eén
            loop over `docker_hosts` in plaats van één hostvars-lookup.
      - [ ] De NFS-export van de Mini (`/Volumes/FastStore`) opschrijven. Geen
            rol beheert hem, de stacks op de docker-host monteren hem, en
            zonder hem vallen die om. Nu staat hij alleen in `/etc/exports`
            op een machine die je aan het beschrijven bent omdat je hem kunt
            verliezen.

- [ ] **Niets bewijst dat een back-up terugkomt.**
      `recovery-drill.yml` bewijst dat een container te herbouwen is, niet dat
      je data terug te zetten is. Een drill die een PBS-back-up op een vrij
      nummer terugzet, een bestand controleert en weer opruimt, dekt het
      engste onbekende af. Zie de runbook Herstellen.

- [ ] **Action1 voor de pc van de ouders**, en voor de Macs.

---

## Klein, wanneer het uitkomt

- [ ] **`~/.ssh/config` staat op `0644`.** De volgende echte `dotfiles.yml`-run
      zet hem op `0600`. Het bestand noemt je hosts, gebruikers en sleutelpaden.
- [ ] **Vault-wachtwoorden roteren.** Tijdens het opzetten zijn de eerste
      tekens van beide in een sessielog terechtgekomen.
      `ansible-vault rekey --new-vault-id infra@<bestand>`.
- [ ] **`~/.ssh/config` opruimen** — pv01-typo, `pve01-unifi-os` weg, nieuwe
      hosts samenvoegen.
- [ ] **Dubbele docker / docker-desktop casks** op MBP en Mini.
- [ ] **Mini: `brew leaves` → `host_vars/macmini.yml`**, het `_extra`-patroon.
      `discover.yml --limit macmini` schrijft die lijst voor je. Het kleinste
      stuk van het grote punt hierboven, en los te doen.
- [ ] **Mac mini draait macOS 14.6.1** — updaten via Action1.
