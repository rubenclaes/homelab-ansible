# Off-site back-up naar Cloudflare R2 — uitvoeringsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Elke nacht een versleutelde kopie van de niet-herbouwbare data in Cloudflare R2, altijd binnen de gratis laag, met een harde stop die de sync uitzet voor er kosten ontstaan.

**Architecture:** `docker` maakt om 02:00 een file-level back-up van `/opt/containers/data` (met database-dumps) naar PBS `store1`. PBS krijgt een S3-endpoint `r2` en een datastore `offsite` met S3-backend. Om 03:50 controleert `r2-guard` het gebruik via de Cloudflare-API; om 04:00 kopieert een lokale sync job de gekozen groepen van `store1` naar `offsite`, laatste 3.

**Tech Stack:** Proxmox Backup Server 4.2, proxmox-backup-client (Debian 12), Cloudflare R2 + GraphQL Analytics API, Ansible, systemd timers, ntfy.

**Spec:** `docs/superpowers/specs/2026-09-25-offsite-backup-r2-design.md`

## Global Constraints

- Bucket `neodata-pbs`, Standard class, niet publiek.
- Groepen naar R2: `host/docker-data`, `vm/101`, `ct/107`, `ct/108`, `ct/109`. Niets anders.
- `transfer-last 3`, prune `keep-last 3` op `offsite`.
- Harde stop: > 9 GB opslag, > 800.000 Class A of > 8.000.000 Class B deze maand → sync job uit + ntfy. Waarschuwing vanaf 8 GB.
- Schema: `docker-data` 02:00, bestaande back-up 02:30, `r2-guard` 03:50, sync 04:00.
- Geheimen alleen in `inventory/host_vars/*/vault.yml` (vault-id `infra`); nooit in de chat, nooit in een log (`no_log`).
- Uitsluiten uit `docker-data`: `immich/postgres`, `immich/model-cache`, `grimmory/mariadb` (vervangen door dumps).

## Review Focus

- `r2-guard` kan de Cloudflare-API niet bereiken (token fout, netwerk) → moet dat als "stop" behandelen, niet als "0 GB". Test: guard met een ongeldig token zet de job uit.
- De guard zet de job uit maar een Ansible-run zet hem stil weer aan → de rol mag een uitgezette job niet heractiveren. Test: `pbs.yml --check` na een stop geeft geen wijziging aan `disable`.
- Een dump faalt (container weg, wachtwoord fout) maar de back-up gaat door met een oude dump → het script moet stoppen bij een mislukte dump. Test: script met een foute DB-naam geeft exit ≠ 0 en maakt geen snapshot.
- Een groep die groeit (Home Assistant-database) duwt R2 langzaam over 8 GB → de waarschuwing moet dat vangen. Test: guard met drempel onder het huidige gebruik stuurt ntfy.
- Herstellen zonder sleutel → waardeloos. Test: restore uit `offsite` op een schone map met alleen de sleutel uit de vault.

---

### Task 1: Cloudflare R2 en de geheimen (Ruben)

**Files:**
- Modify: `inventory/host_vars/pbs/vault.yml` (vault-id `infra`)

- [ ] **Step 1: Bucket** — Cloudflare dashboard → R2 → Create bucket: naam `neodata-pbs`, location Automatic, **Default storage class: Standard**. Public access: uit laten.
- [ ] **Step 2: S3-token** — R2 → Manage API tokens → Create API token: permissie **Object Read & Write**, **alleen bucket `neodata-pbs`**. Noteer Access Key ID, Secret Access Key en de endpoint `https://<account-id>.r2.cloudflarestorage.com`.
- [ ] **Step 3: API-token voor de guard** — My Profile → API Tokens → Create custom token: **Account → Account Analytics → Read**, alleen dit account. Noteer het token.
- [ ] **Step 4: In de vault**

```bash
ansible-vault edit inventory/host_vars/pbs/vault.yml
```

```yaml
vault_r2_account_id: "<account-id>"
vault_r2_access_key: "<Access Key ID>"
vault_r2_secret_key: "<Secret Access Key>"
vault_cf_analytics_token: "<API-token>"
```

- [ ] **Step 5: Controle (Claude)** — `ansible pbs -m debug -a "msg={{ vault_r2_account_id | length > 0 and vault_cf_analytics_token | length > 0 }}"` → `true`.

---

### Task 2: S3-endpoint en datastore `offsite` op PBS

**Files:**
- Create: `roles/pbs/tasks/offsite.yml`
- Modify: `roles/pbs/tasks/main.yml` (include na "Datastore and job configuration"), `roles/pbs/defaults/main.yml` (`pbs_offsite: {}`), `inventory/host_vars/pbs/main.yml` (`pbs_offsite:`-blok)

- [ ] **Step 1: Vars**

```yaml
pbs_offsite:
  endpoint_id: r2
  endpoint: "{{ vault_r2_account_id }}.r2.cloudflarestorage.com"
  access_key: "{{ vault_r2_access_key }}"
  secret_key: "{{ vault_r2_secret_key }}"
  bucket: neodata-pbs
  datastore: offsite
  cache_path: /mnt/datastore/offsite-cache
  groups: [host/docker-data, vm/101, ct/107, ct/108, ct/109]
  keep_last: 3
  sync_schedule: "04:00"
  guard_schedule: "03:50"
  warn_gb: 8
  stop_gb: 9
  stop_class_a: 800000
  stop_class_b: 8000000
```

- [ ] **Step 2: Taken** — in `offsite.yml`, elk "maak aan als hij er niet is" zoals `config.yml` het al doet (lees lijst, maak ontbrekende):
  - `proxmox-backup-manager s3 endpoint create r2 --endpoint <endpoint> --access-key … --secret-key … --path-style true` (`no_log: true`), en `update` als de sleutels wijzigen.
  - `proxmox-backup-manager s3 check r2 neodata-pbs` → moet slagen, anders stop met een Nederlandse melding.
  - cache-map aanmaken, dan `proxmox-backup-manager datastore create offsite /mnt/datastore/offsite-cache --backend type=s3,client=r2,bucket=neodata-pbs --gc-schedule daily --counter-reset-schedule monthly --notification-thresholds s3-put=200000,s3-get=2000000`.
  - prune-job op `offsite`: `keep-last 3`, schedule `daily`.
- [ ] **Step 3: Droog en echt** — `ansible-playbook playbooks/pbs.yml --check --diff` toont de nieuwe objecten; dan zonder `--check` → `failed=0`.
- [ ] **Step 4: Controle** — `ssh pbs 'sudo proxmox-backup-manager datastore list'` toont `offsite`; `s3 check` geeft OK. Tweede `pbs.yml --check` → `changed=0`.
- [ ] **Step 5: Commit** — `git commit -m "feat(pbs): S3 endpoint and offsite datastore on Cloudflare R2"`

---

### Task 3: File-level back-up van `docker` naar `store1`

**Files:**
- Create: `roles/pbs_client/{defaults,tasks,templates}/…` met `docker-data-backup.sh.j2`, `docker-data-backup.service.j2`, `docker-data-backup.timer.j2`
- Create: `playbooks/offsite.yml` (play `docker` met `pbs_client`, play `pbs` met `pbs` tags `offsite`)
- Modify: `inventory/host_vars/docker.yml` (`pbs_client_*`), `inventory/host_vars/docker/vault.yml` of bestaande vault (`vault_pbs_docker_data_token`, `vault_pbs_docker_data_key`)
- Modify: `roles/pbs/tasks/offsite.yml` (gebruiker `docker-data@pbs`, token, ACL `DatastoreBackup` op `/datastore/store1`)

- [ ] **Step 1: Gebruiker en token op PBS** — `proxmox-backup-manager user create docker-data@pbs`, `user generate-token docker-data@pbs backup`, `acl update /datastore/store1 DatastoreBackup --auth-id 'docker-data@pbs!backup'`. Token-secret één keer in de vault (`vault_pbs_docker_data_token`).
- [ ] **Step 2: Sleutel** — op `docker`: `proxmox-backup-client key create /root/.config/proxmox-backup/docker-data.key --kdf none`; inhoud in de vault (`vault_pbs_docker_data_key`); de rol zet hem terug met mode `0600`.
- [ ] **Step 3: Script** (`/usr/local/sbin/docker-data-backup`, `set -euo pipefail`):

```bash
#!/bin/bash
set -euo pipefail
D=/opt/containers/data/_dumps
install -d -m 0700 "$D"
docker exec immich-postgres pg_dumpall -U postgres | gzip > "$D/immich.sql.gz.new"
docker exec grimmory-db sh -c 'mariadb-dump -uroot -p"$MYSQL_ROOT_PASSWORD" --all-databases --single-transaction' | gzip > "$D/grimmory.sql.gz.new"
for f in immich grimmory; do
  [ "$(gzip -cd "$D/$f.sql.gz.new" | head -c 1 | wc -c)" = 1 ] || { echo "dump $f is leeg"; exit 1; }
  mv "$D/$f.sql.gz.new" "$D/$f.sql.gz"
done
export PBS_REPOSITORY='docker-data@pbs!backup@192.168.0.181:store1'
export PBS_PASSWORD_FILE=/root/.config/proxmox-backup/token
export PBS_FINGERPRINT='{{ pbs_client_fingerprint }}'
proxmox-backup-client backup data.pxar:/opt/containers/data \
  --backup-type host --backup-id docker-data \
  --keyfile /root/.config/proxmox-backup/docker-data.key \
  --exclude /opt/containers/data/immich/postgres \
  --exclude /opt/containers/data/immich/model-cache \
  --exclude /opt/containers/data/grimmory/mariadb
```

(Containernamen en de Immich-DB-gebruiker controleren met `docker ps` en de `.env` voor je het script vastlegt; `pipefail` zorgt dat een mislukte `docker exec` het script stopt.)

- [ ] **Step 4: Timer** — `OnCalendar=*-*-* 02:00:00`, `Persistent=true`; bij falen `OnFailure=` naar de bestaande ntfy-melding als die er is, anders `curl` naar ntfy in `ExecStopPost` met `$SERVICE_RESULT`.
- [ ] **Step 5: Test falen** — tijdelijk `grimmory-db` → `grimmory-dbx` in het script op de host: `systemctl start docker-data-backup` → failed, en geen nieuwe snapshot in `store1`. Terugzetten.
- [ ] **Step 6: Test slagen** — `ansible-playbook playbooks/offsite.yml --limit docker`, dan `systemctl start docker-data-backup` → succeeded; op PBS `proxmox-backup-client snapshot list` (als root@pam op localhost) toont `host/docker-data`.
- [ ] **Step 7: Commit** — `git commit -m "feat: nightly file-level backup of docker app data to PBS"`

---

### Task 4: Sync job naar `offsite`

**Files:** Modify `roles/pbs/tasks/offsite.yml`

- [ ] **Step 1: Taak** — `proxmox-backup-manager sync-job create offsite-r2 --store offsite --remote-store store1 --schedule 04:00 --transfer-last 3 --remove-vanished true --encrypted-only true` met één `--group-filter group:<g>` per groep uit `pbs_offsite.groups` (geen `--remote`: lokale sync). **Alleen aanmaken als hij ontbreekt; `disable` nooit aanraken**, zodat een stop van de guard blijft staan.
- [ ] **Step 2: Eerste run met de hand** — `ssh pbs 'sudo proxmox-backup-manager sync-job run offsite-r2'`, volg de taak tot OK.
- [ ] **Step 3: Controle** — `proxmox-backup-client snapshot list --repository localhost:offsite` toont precies de 5 groepen, elk ≤ 3 snapshots; `vm/102`, `vm/103`, `ct/104`, `ct/106` ontbreken.
- [ ] **Step 4: Commit** — `git commit -m "feat(pbs): nightly sync of selected groups to R2"`

---

### Task 5: `r2-guard` — waarschuwing en harde stop

**Files:**
- Create: `roles/pbs/templates/r2-guard.py.j2`, `r2-guard.service.j2`, `r2-guard.timer.j2`
- Modify: `roles/pbs/tasks/offsite.yml`

- [ ] **Step 1: Script** (Python, alleen stdlib): GraphQL naar `https://api.cloudflare.com/client/v4/graphql` met het analytics-token:
  - opslag: `r2StorageAdaptiveGroups` (filter `bucketName`, laatste dag) → `max { payloadSize metadataSize }`;
  - operaties: `r2OperationsAdaptiveGroups` vanaf de 1e van de maand, `sum { requests }` per `actionType`, ingedeeld in Class A (Put/Copy/List/CreateMultipart/UploadPart/CompleteMultipart/…) en Class B (Get/Head/…).
  - Elke fout (HTTP ≠ 200, `errors` in het antwoord, ontbrekend veld) telt als **stop**.
  - Stop: `proxmox-backup-manager sync-job update offsite-r2 --disable true` (bestaat die optie niet: `--delete schedule`, en schrijf de oude schedule naar `/var/lib/r2-guard/schedule`), plus ntfy met prioriteit hoog.
  - ≥ `warn_gb`: ntfy met prioriteit normaal, job blijft aan.
  - Drempels en token als argumenten/omgeving uit de rol, niet hardcoded.
- [ ] **Step 2: Test stop bij fout** — run met een ongeldig token → job uit, ntfy "R2-check mislukt, sync gestopt". Job weer aan.
- [ ] **Step 3: Test stop bij drempel** — run met `--stop-gb 0` → job uit, ntfy. Job weer aan.
- [ ] **Step 4: Test waarschuwing** — run met `--warn-gb 0 --stop-gb 100` → ntfy-waarschuwing, job blijft aan.
- [ ] **Step 5: Timer** — `OnCalendar=*-*-* 03:50:00`; `pbs.yml --check` na een stop → `changed=0` op de sync job.
- [ ] **Step 6: Commit** — `git commit -m "feat(pbs): r2-guard stops the R2 sync before it can cost money"`

---

### Task 6: Sleutels veilig (Ruben + Claude)

- [ ] **Step 1: Paperkeys (Claude)** — `proxmox-backup-client key paperkey --output-format text` voor de pve01-sleutel (`/etc/pve/priv/storage/pbs.enc`) en `docker-data.key`, naar een bestand in de scratchpad (niet in de chat).
- [ ] **Step 2: Ruben** — beide afdrukken, bij de belangrijke papieren; en als bijlage in Vaultwarden (item "PBS-sleutels").
- [ ] **Step 3: Scratchpad-bestand verwijderen.**

---

### Task 7: Herstellen uit R2

- [ ] **Step 1: Bestand uit `docker-data`** — op `docker`, in een lege map: `proxmox-backup-client restore host/docker-data/<laatste> data.pxar /tmp/r2-test --repository …:offsite --keyfile …`; vergelijk `grimmory/books` met het origineel (`diff -r`) en `gzip -t _dumps/*.gz`.
- [ ] **Step 2: Een LXC** — op pve01: `pvesm list` op een tijdelijke storage die `offsite` aanwijst, of `proxmox-backup-client catalog dump ct/109/<laatste> --repository localhost:offsite` op PBS → bestanden zichtbaar.
- [ ] **Step 3: Opruimen** — `/tmp/r2-test` weg, tijdelijke storage weg.

---

### Task 8: Docs en TODO

**Files:**
- Create: sectie `## Herstellen van buiten het huis` in `docs-site/content/runbooks/stuk/pve01.mdx` + rij in de geval-tabel en in `runbooks/stuk/index.mdx`
- Modify: `TODO.md` (off-site afvinken, met wat er wel en niet mee gaat)

- [ ] **Step 1: Runbook** — geval-tabel, stappen (R2 als storage toevoegen op een nieuwe PBS, sleutel uit Vaultwarden, restore), en `## Goed om te weten`: waarom alleen deze 5 groepen, waarom 3 versies, wat de guard doet en hoe je de sync weer aanzet.
- [ ] **Step 2: `ansible-playbook playbooks/docs.yml`** → `failed=0`.
- [ ] **Step 3: Commit en push.**
