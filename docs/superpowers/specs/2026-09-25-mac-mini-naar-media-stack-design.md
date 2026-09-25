# Grimmory, Shelfmark en Recyclarr van de Mac mini naar de media-stack

25-09-2026. Samen met Ruben afgesproken.

## Doel

Drie diensten verhuizen van de Mac mini (OrbStack) naar de media-stack op
`docker` (VM 103 op pve01), en ze werken daarna zoals nu. Expenseowl gaat weg
van de Mac mini, met zijn data gearchiveerd.

Waarom: ze horen bij de rest van de media-stack (Sonarr, Radarr, qBittorrent),
PBS neemt ze elke nacht mee, en de Mac mini doet nog alleen wat hij moet doen:
Plex, de schijven en zijn eigen back-up.

## Beslist

| Vraag | Keuze | Waarom |
| --- | --- | --- |
| Welke stack | `stacks/media` in de `containers`-repo | ze horen bij Sonarr/Radarr/qBittorrent |
| Data van Grimmory (database + boeken, ~200 MB) | lokale schijf van `docker`: `/opt/containers/data/grimmory` | een database op NFS kan stukgaan; PBS neemt het mee |
| Poort Grimmory | `6061`, zoals nu | vrij op `docker` |
| Poort Shelfmark | `8087` (was `8084`) | `8084` is op `docker` al BentoPDF |
| Torrent-map van Shelfmark | `/mnt/ssdnas/Media/Downloads/Complete` | daar schrijft qBittorrent. Op de Mac las hij `Books/Media/...`, een lege map: een fout die meteen weg is |
| Recyclarr | in `media-net`, zelfde config | dan werken `http://sonarr:8989` en `http://radarr:7878` weer |
| Expenseowl | stoppen, data als `.tar.gz` in `~/Container/_archief` | zoals Pocket ID op 23-09 |
| Geheimen van Grimmory | uit `files/env/grimmory.env` naar `files/env/media.env` (vault `stacks`) | één `.env` per stack |

## Stappen

Niets op de Mac mini wordt weggegooid voor stap 6 werkt. Tot dan is terug
gaan: de Caddy-route terug op `host: macmini`, en de containers op de Mac
weer starten.

1. **Veiligheidskopie** op de Mac mini: `Grimmory`, `Shelfmark`, `recyclarr`
   als `.tar.gz` in `~/Container/_archief`.
2. **containers-repo**: de drie diensten in `stacks/media/docker-compose.yml`,
   de Grimmory-variabelen in `media.env`. Commit en push.
3. **Stoppen op de Mac, data kopiëren**: `docker compose down` voor de drie
   op de Mac mini, dan de data naar `docker:/opt/containers/data/`
   (`grimmory/`, `shelfmark/`, `recyclarr/`), eigenaar `1000:1000`.
4. **Starten op `docker`**: `playbooks/stacks.yml --limit docker`.
5. **Caddy**: `books` → `host: docker, port: 6061, stack: media`;
   `shelfmark` → `host: docker, port: 8087, stack: media`. Dan `caddy.yml`.
6. **Testen**:
   - `books.neodata.be`: aanmelden, zelfde boeken en gebruikers als voor.
   - `shelfmark.neodata.be` opent; een boek via Shelfmark komt in de
     bookdrop en daarna in Grimmory.
   - Recyclarr: `docker exec recyclarr recyclarr sync` zonder fouten.
   - `unifi-routes.yml` en `smoketest.yml` groen.
7. **Opruimen op de Mac mini**: `grimmory`, `shelfmark`, `recyclarr` uit
   `docker_stacks_list` in `macmini.yml`; hun mappen uit de `homelab`-repo;
   Expenseowl stoppen en archiveren, en de LET OP-noot erover weg. De
   Semaphore-noot over "shelfmark op de Mini" aanpassen (alleen `duplicati`
   blijft).
8. **Duplicati op de Mac** nakijken: back-upt een job `Container/Grimmory`,
   dan die bron eruit halen.
9. **Docs en rapport**: `docs.yml` draaien (de dienstpagina's en Machines
   volgen vanzelf uit de inventory); de voorbeelden met "Shelfmark op de Mac
   mini" in `runbooks/toevoegen/` aanpassen. Commit en push.

## Buiten scope

- Plex, Duplicati, Alloy en de Portainer-agent blijven op de Mac mini.
- De NFS-mounts van `docker` blijven zoals ze zijn.
