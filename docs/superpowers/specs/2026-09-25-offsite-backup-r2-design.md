# Off-site back-up naar Cloudflare R2

25-09-2026. Samen met Ruben afgesproken.

## Doel

Een kopie buiten het huis van wat niet uit git herbouwd kan worden, binnen
de gratis laag van Cloudflare R2 (10 GB opslag), met een waarschuwing
voor het ooit geld kost. Brand, diefstal of ransomware in huis mag geen
data meer kosten die niet in git staat.

## Wat gaat mee

| Groep in PBS | Wat | Schatting (gecomprimeerd) | Waarom |
| --- | --- | --- | --- |
| `host/docker-data` (nieuw) | `/opt/containers/data` op `docker`, plus dumps van de databases | ~1,5 GB | de enige data van de apps: Vaultwarden, Immich, Grimmory, instellingen |
| `vm/101` | Home Assistant, heel | ~2,5 GB | automatiseringen en toestellen staan niet in git |
| `ct/107` | adguard | ~0,4 GB | klein, snel terug |
| `ct/108` | tailscale | ~0,3 GB | klein, snel terug |
| `ct/109` | ntfy | < 0,1 GB | gebruikers en tokens |

Samen ~5 GB, 3 versies in R2 (dedup maakt de extra versies klein).

**Niet mee**: `docker` en `docker-grafana-stack` als hele VM (images en OS,
herbouwbaar), `caddy` en `semaphore` (volledig in git). Git zelf staat al
op GitHub.

## Beslist

| Vraag | Keuze | Waarom |
| --- | --- | --- |
| Opslag | Cloudflare R2, Standard class, bucket `neodata-pbs` | 10 GB gratis, terughalen altijd gratis |
| Hoe | PBS 4.2: S3-endpoint `r2`, datastore `offsite` met S3-backend, lokale sync job `store1` → `offsite` met groepfilter | PBS doet het zelf, geen extra tool |
| Versleuteling | blijft client-side: pve01 met zijn bestaande sleutel, `docker` met een nieuwe | Cloudflare kan niets lezen |
| Databases | vóór de back-up een dump: `pg_dump` (Immich), `mariadb-dump` (Grimmory); de live-mappen van die databases en `immich/model-cache` worden uitgesloten | een kopie van een draaiende database kan stuk zijn |
| SQLite-apps (Sonarr, Radarr, Vaultwarden, …) | mappen zoals ze zijn | ze maken zelf back-ups in hun config-map; Vaultwarden heeft zijn eigen versleutelde back-up |
| Schema | `docker-data` 02:00, bestaande PBS-back-up 02:30, sync naar R2 04:00 | sync na alle back-ups |
| Bewaren in R2 | laatste 3 per groep | ruimte |
| Waarschuwing | dagelijks: R2-gebruik via de Cloudflare-API; boven 8 GB een ntfy-melding | R2 heeft geen harde uitgavengrens |
| Sleutels | paperkey van beide sleutels op papier, en in Vaultwarden | zonder sleutel is de kopie in R2 waardeloos |
| Beheer | in `roles/pbs` en een nieuwe taak op `docker`; geheimen in de vault | git is de bron |

## Klaar als

- De sync job naar R2 draait en is groen.
- Een bestand uit `docker-data` én een LXC zijn uit `offsite` teruggezet en
  kloppen.
- R2 toont minder dan 8 GB; de waarschuwing is getest met een lage drempel.
- Beide sleutels staan op papier en in Vaultwarden.
- Runbook "Herstellen van buiten het huis" staat op de docs-site.

## Buiten scope

- Plex-media en de NFS-shares van de Mac mini (te groot, herbouwbaar door
  opnieuw te downloaden).
- De wekelijkse dumps naar de Mac mini blijven zoals ze zijn.
