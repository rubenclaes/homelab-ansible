# Grimmory, Shelfmark en Recyclarr naar de media-stack — uitvoeringsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Grimmory, Shelfmark en Recyclarr draaien in de media-stack op `docker` en werken zoals voorheen; de Mac mini is opgeruimd en Expenseowl gearchiveerd.

**Architecture:** Compose-diensten erbij in `containers/stacks/media`, data met `rsync` van de Mac mini naar `/opt/containers/data` op `docker`, Caddy-routes omzetten, pas daarna de Mac mini opruimen. Terugdraaien kan tot Task 5: route terug en containers op de Mac weer starten.

**Tech Stack:** Docker Compose, Ansible (`stacks.yml`, `caddy.yml`, `docs.yml`), OrbStack op de Mac mini, rsync over SSH.

**Spec:** `docs/superpowers/specs/2026-09-25-mac-mini-naar-media-stack-design.md`

## Global Constraints

- Data op `docker`: `/opt/containers/data/{grimmory,shelfmark,recyclarr}`, eigenaar `1000:1000`.
- Grimmory: host-poort `6061`. Shelfmark: host-poort `8087` (container `8084`).
- Shelfmark-torrentmap: `/mnt/ssdnas/Media/Downloads/Complete` (zelfde pad in de container).
- Geheimen van Grimmory in `files/env/media.env` (vault-id `stacks`).
- Niets op de Mac mini verwijderen voor Task 5 groen is.
- Archief op de Mac mini: `~/Container/_archief/<naam>-2026-09-25.tar.gz`.

## Review Focus

- Grimmory start met een lege database in plaats van de gekopieerde → aanmelden faalt of er zijn geen boeken. Test: aanmelden + aantal boeken gelijk aan voor (Task 1 noteert het).
- Rechten na rsync (bestanden van uid 501) → mariadb start niet. Test: `docker compose ps` toont `grimmory-db` healthy.
- Shelfmark kan niet schrijven in de bookdrop → download blijft hangen. Test: `touch` als uid 1000 in de bookdrop.
- Recyclarr bereikt Sonarr/Radarr niet → stille fout elke nacht. Test: `recyclarr sync` met exit 0.
- Een route die nog naar `macmini` wijst na de opruiming → 502. Test: `smoketest.yml` groen.

---

### Task 1: Veiligheidskopie en nulmeting op de Mac mini

**Files:** geen (alleen de Mac mini).

- [ ] **Step 1: Noteer wat er nu in Grimmory zit**

Open `https://books.neodata.be`, meld aan, noteer het aantal boeken en gebruikers. Dat is de nulmeting voor Task 5.

- [ ] **Step 2: Archiveer de drie mappen plus Expenseowl**

```bash
ssh macmini 'cd ~/Container && mkdir -p _archief && \
  tar czf _archief/grimmory-2026-09-25.tar.gz Grimmory && \
  tar czf _archief/shelfmark-2026-09-25.tar.gz Shelfmark && \
  tar czf _archief/recyclarr-2026-09-25.tar.gz recyclarr && \
  tar czf _archief/expenseowl-2026-09-25.tar.gz Archive/expenseowl && \
  ls -lh _archief/*2026-09-25*'
```

Expected: vier bestanden, geen ervan 0 bytes. (Grimmory draait nog: dit is een vangnet, de echte kopie komt in Task 3 met de containers gestopt.)

---

### Task 2: De drie diensten in de media-stack

**Files:**
- Modify: `~/Development/containers/stacks/media/docker-compose.yml` (na `radarr:`)
- Modify: `files/env/media.env` (vault `stacks`)

- [ ] **Step 1: Grimmory-variabelen naar media.env**

```bash
ansible-vault edit files/env/media.env
```

Voeg onderaan toe, met de waarden uit `ansible-vault view files/env/grimmory.env`:

```
# ── Grimmory ─────────────────────────────────────────────────────────
GRIMMORY_DB_NAME=grimmory
GRIMMORY_DB_USER=grimmory
GRIMMORY_DB_PASS=<uit grimmory.env>
GRIMMORY_DB_ROOT_PASS=<uit grimmory.env>
```

- [ ] **Step 2: Diensten toevoegen, na het `radarr:`-blok**

```yaml
  # E-books, strips en luisterboeken. Tot 25-09 op de Mac mini.
  grimmory:
    <<: *common
    image: grimmory/grimmory:v3.3.3@sha256:fffd0ae0bfccd64ca00441e8fa58a14e286b9115e5df1cb47eecf294ad09e6ff
    container_name: grimmory
    environment:
      APP_USER_ID: ${PUID}
      APP_GROUP_ID: ${PGID}
      TZ: ${TZ}
      DATABASE_URL: "jdbc:mariadb://grimmory-db:3306/${GRIMMORY_DB_NAME}"
      DATABASE_USERNAME: ${GRIMMORY_DB_USER}
      DATABASE_PASSWORD: ${GRIMMORY_DB_PASS}
      DISK_TYPE: LOCAL
    depends_on:
      grimmory-db:
        condition: service_healthy
    ports:
      - "${BIND_ADDR}:6061:6060"
    volumes:
      - ${DATA_PATH}/grimmory/data:/app/data
      - ${DATA_PATH}/grimmory/books:/books
      - ${DATA_PATH}/grimmory/bookdrop:/bookdrop
    healthcheck:
      test: ["CMD-SHELL", "wget -q -O - http://localhost:6060/api/v1/healthcheck >/dev/null 2>&1 || exit 1"]
      interval: 60s
      retries: 5
      start_period: 60s
      timeout: 10s

  grimmory-db:
    <<: *common
    image: lscr.io/linuxserver/mariadb:11.8.8@sha256:f10560e128acaa2054a9acb0c4862f97a857d7dbe86870f3afb5c7daea1c8363
    container_name: grimmory-db
    environment:
      <<: *env
      MYSQL_ROOT_PASSWORD: ${GRIMMORY_DB_ROOT_PASS}
      MYSQL_DATABASE: ${GRIMMORY_DB_NAME}
      MYSQL_USER: ${GRIMMORY_DB_USER}
      MYSQL_PASSWORD: ${GRIMMORY_DB_PASS}
    volumes:
      - ${DATA_PATH}/grimmory/mariadb:/config
    healthcheck:
      test: ["CMD", "mariadb-admin", "ping", "-h", "localhost"]
      interval: 5s
      timeout: 5s
      retries: 10

  # Zoekt boeken en legt ze in de bookdrop van Grimmory. Poort 8087, want
  # 8084 is hier BentoPDF. De torrentmap staat op hetzelfde pad als in
  # qBittorrent, dan is er geen remote-path mapping nodig.
  shelfmark:
    <<: *common
    image: ghcr.io/calibrain/shelfmark:v1.3.15@sha256:9602290324993c801b319d3166b202b96bd9039af2416f0916dae03a5bdca815
    container_name: shelfmark
    environment:
      <<: *env
    ports:
      - "${BIND_ADDR}:8087:8084"
    volumes:
      - ${DATA_PATH}/shelfmark/config:/config
      - ${DATA_PATH}/grimmory/bookdrop:/bookdrop
      - ${DATA_PATH}/grimmory/books:/books
      - /mnt/ssdnas/Media/Downloads/Complete:/mnt/ssdnas/Media/Downloads/Complete

  # Zet de kwaliteitsprofielen van Sonarr en Radarr gelijk. In media-net,
  # zodat http://sonarr:8989 en http://radarr:7878 uit zijn config werken.
  recyclarr:
    <<: *common
    image: ghcr.io/recyclarr/recyclarr@sha256:55afe316d3e4e4e3b9120cef7c79436b1b5311f6a18d4ef4b7653e720499c90a
    container_name: recyclarr
    environment:
      TZ: ${TZ}
    volumes:
      - ${DATA_PATH}/recyclarr/config:/config
      - ${DATA_PATH}/recyclarr/logs:/logs
```

- [ ] **Step 3: Controleer de compose-file**

Run: `cd ~/Development/containers/stacks/media && ansible-vault view ~/Development/homelab-ansible/files/env/media.env > /tmp/media.env && docker compose --env-file /tmp/media.env config --quiet; echo rc=$?; rm /tmp/media.env`
Expected: `rc=0`.

- [ ] **Step 4: Commit en push (containers-repo en homelab-ansible)**

```bash
git -C ~/Development/containers add stacks/media/docker-compose.yml
git -C ~/Development/containers commit -m "feat(media): grimmory, shelfmark and recyclarr from the Mac mini"
git -C ~/Development/containers push
git add files/env/media.env && git commit -m "feat: grimmory secrets in media.env"
```

Nog niet `stacks.yml` draaien: eerst de data (Task 3), anders start Grimmory met een lege database.

---

### Task 3: Stoppen op de Mac, data naar `docker`

**Files:** geen.

- [ ] **Step 1: Stop de drie op de Mac mini**

```bash
ssh macmini 'cd ~/Container && for d in Grimmory Shelfmark recyclarr; do (cd $d && /usr/local/bin/docker compose down); done; /usr/local/bin/docker ps --format "{{.Names}}"'
```

Expected: `grimmory`, `shelfmark`, `recyclarr` staan niet meer in de lijst.

- [ ] **Step 2: Kopieer de data, via de Mac als tussenstation**

```bash
mkdir -p /tmp/mig && rsync -a macmini:Container/Grimmory/{data,books,bookdrop} /tmp/mig/grimmory/ \
  && rsync -a macmini:Container/Grimmory/grimmory/mariadb /tmp/mig/grimmory/ \
  && rsync -a macmini:Container/Shelfmark/config /tmp/mig/shelfmark/ \
  && rsync -a macmini:Container/recyclarr/{config,logs} /tmp/mig/recyclarr/
rsync -a --rsync-path="sudo rsync" /tmp/mig/ docker:/opt/containers/data/
ssh docker 'sudo chown -R 1000:1000 /opt/containers/data/{grimmory,shelfmark,recyclarr} && sudo du -sh /opt/containers/data/{grimmory,shelfmark,recyclarr}'
rm -rf /tmp/mig
```

Expected: grimmory ~200M, shelfmark ~14M, recyclarr klein.

---

### Task 4: Starten op `docker` en Caddy omzetten

**Files:**
- Modify: `inventory/host_vars/caddy/main.yml:66-67`

- [ ] **Step 1: Stack uitrollen**

Run: `ansible-playbook playbooks/stacks.yml --limit docker`
Expected: `failed=0`.

- [ ] **Step 2: Controleer de containers**

Run: `ssh docker 'sudo docker ps --filter name=grimmory --filter name=shelfmark --filter name=recyclarr --format "{{.Names}} {{.Status}}"'`
Expected: `grimmory-db (healthy)`, `grimmory (healthy)` (na ~60 s), `shelfmark`, `recyclarr` Up.

- [ ] **Step 3: Routes omzetten**

```yaml
  - { name: books, host: docker, port: 6061, stack: media, desc: "Grimmory — bibliotheek voor e-books, strips en luisterboeken" }
  - { name: shelfmark, host: docker, port: 8087, stack: media, desc: "Shelfmark — zoekt boeken en legt ze in de bookdrop van Grimmory" }
```

Verplaats beide regels van het blok `# --- Mac mini ---` naar `# --- docker ---`.

- [ ] **Step 4: Caddy uitrollen**

Run: `ansible-playbook playbooks/caddy.yml`
Expected: `failed=0`.

---

### Task 5: Testen

- [ ] **Step 1: Grimmory** — `https://books.neodata.be`: aanmelden, aantal boeken en gebruikers gelijk aan Task 1.
- [ ] **Step 2: Bookdrop schrijfbaar** — `ssh docker 'sudo -u "#1000" touch /opt/containers/data/grimmory/bookdrop/.t && rm /opt/containers/data/grimmory/bookdrop/.t && echo ok'` → `ok`.
- [ ] **Step 3: Shelfmark** — `https://shelfmark.neodata.be` opent; zoek en download één boek; het verschijnt in Grimmory.
- [ ] **Step 4: Recyclarr** — `ssh docker 'sudo docker exec recyclarr recyclarr sync; echo rc=$?'` → `rc=0`, geen "Problem connecting".
- [ ] **Step 5: Checks** — `ansible-playbook playbooks/unifi-routes.yml` en `ansible-playbook playbooks/smoketest.yml` → beide `failed=0`.

Faalt iets hier: routes terug (Task 4 Step 3 omgekeerd + `caddy.yml`) en op de Mac `docker compose up -d` in de drie mappen.

- [ ] **Step 6: Commit** — `git add inventory/host_vars/caddy/main.yml && git commit -m "feat: books and shelfmark routes to docker"`

---

### Task 6: Mac mini opruimen

**Files:**
- Modify: `inventory/host_vars/macmini.yml:156-159` (docker_stacks_list), `:166-173` (LET OP expenseowl), header regel 2 ("acht compose-projecten")
- Modify: `inventory/host_vars/semaphore/main.yml:181-185`
- Delete: `~/Development/homelab/{Grimmory,Shelfmark,recyclarr}/`

- [ ] **Step 1: Inventory** — haal `grimmory`, `recyclarr`, `shelfmark` uit `docker_stacks_list` in `macmini.yml`, schrap het LET OP-blok over expenseowl, en pas de telling in de header aan. In `semaphore/main.yml`: "komen `duplicati` en `shelfmark` op de Mini niet terug" → alleen `duplicati`.
- [ ] **Step 2: homelab-repo** — `git -C ~/Development/homelab rm -r Grimmory Shelfmark recyclarr && git -C ~/Development/homelab commit -m "chore: grimmory, shelfmark and recyclarr moved to the media stack on docker" && git -C ~/Development/homelab push`
- [ ] **Step 3: Mac mini** — `ssh macmini 'cd ~/Container && rm -rf Grimmory Shelfmark recyclarr Archive/expenseowl && ls _archief'` (de archieven van Task 1 blijven).
- [ ] **Step 4: Controle** — `ansible-playbook playbooks/stacks.yml --limit macmini --check` → `changed=0`, `failed=0`.
- [ ] **Step 5: Duplicati** — `https://duplicati.neodata.be`: back-upt een job `Container/Grimmory`, `Shelfmark` of `recyclarr`? Haal die bron eruit.
- [ ] **Step 6: Commit** — `git add inventory && git commit -m "chore: mac mini no longer runs grimmory, shelfmark, recyclarr"`

---

### Task 7: Docs en rapport

**Files:**
- Modify: `docs-site/content/runbooks/toevoegen/dienst.mdx:183-225`, `docs-site/content/runbooks/toevoegen/index.mdx:16` (voorbeeld "Shelfmark op de Mac mini" → "Home Assistant")
- Modify: `docs-site/content/runbooks/onderhoud/semaphore.mdx:201`
- Generated: `docs-site/content/homelab/{machines,diensten/*}.mdx` via `docs.yml`

- [ ] **Step 1: Handgeschreven pagina's** — pas de drie plaatsen hierboven aan.
- [ ] **Step 2: Genereren en publiceren** — `ansible-playbook playbooks/docs.yml` → `failed=0`.
- [ ] **Step 3: Rapport** — `ansible-playbook playbooks/report.yml` → geen "dode route" of "geen route" voor 6061/8087.
- [ ] **Step 4: Commit en push** — `git add -A && git commit -m "docs: grimmory, shelfmark and recyclarr on docker" && git push`
