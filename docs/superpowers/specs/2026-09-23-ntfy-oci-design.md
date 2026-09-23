# ntfy als OCI-container: meldingen die aankomen

Datum: 2026-09-23
Status: ontwerp, proef op pve01 geslaagd

## Probleem

Proxmox meldt alles aan `mail-to-root`: lokale post die niemand leest. De
wekelijkse back-up naar `local` faalde maandenlang zonder dat iemand het zag
(eerste punt in `TODO.md`). Wie een storing moet melden, mag bovendien niet
afhangen van de machine die stuk kan gaan: de docker-VM kan zichzelf niet
aangeven als hij plat ligt.

## Doel

Een eigen ntfy-server als OCI-container op pve01, en Proxmox die er zijn
waarschuwingen en fouten naartoe stuurt. Een mislukte back-up komt binnen als
melding op je telefoon.

Dit is ook het eerste gebruik van OCI-containers in deze estate. De rol wordt
daarom algemeen gebouwd, niet specifiek voor ntfy.

## Beslissingen

| | |
| --- | --- |
| Dienst | ntfy, niet Gotify: Gotify heeft geen iPhone-app |
| Vorm | OCI-image als LXC, geen Docker-stack. Moet blijven werken als de docker-VM plat ligt |
| Image | `docker.io/binwiederhier/ntfy:v2.28.0`, vaste versie, nooit `latest` |
| Container | vmid 109, `ntfy`, `192.168.0.32/24`, 1 core, 256 MB, 2 GB rootfs |
| State | Eigen volume `mp0` op `/var/lib/ntfy` (1 GB). Het image heeft die map niet |
| Configuratie | Volledig via env: gebruikers, rechten en tokens declaratief, geen handwerk in de container |
| Geheimen | Wachtwoord-hash en token in `inventory/group_vars/proxmox/vault.yml` |
| Bereikbaar | `ntfy.neodata.be` via Caddy |
| Rol | Nieuwe rol `proxmox_oci`, lijst `pve_oci_lxcs` in `lxcs.yml` |

## Wat de proef leerde

Op 23-09 is dit gebouwd en weer gesloopt op vmid 199. Vier dingen die het
ontwerp vormen:

1. **`pct create` negeert `--entrypoint` en `--env`** bij een OCI-template: hij
   neemt die van het image over. Ze moeten er ná het aanmaken op gezet worden.
2. **De env is een lijst gescheiden door NUL-tekens.** Dat kan niet via een
   shell- of `command`-argument, want een argument kan geen NUL bevatten. Hij
   moet via de REST-API (`ansible.builtin.uri`, JSON kent `\u0000`). Proxmox
   schrijft er losse `lxc.environment.runtime`-regels van.
3. **Wie `env` zet, vervangt alles, ook `PATH`.** Zonder `PATH` vindt hij
   `ntfy` niet en stopt de container zonder melding. De rol zet `PATH` altijd
   mee.
4. **`oci-registry-pull --filename` plakt zelf `.tar` achter de naam.** Geef
   `ntfy_v2.28.0`, niet `ntfy_v2.28.0.tar`.

Resultaat met gebruikers, rechten en token alleen uit env: `/v1/health` gaf
`healthy`, publiceren met token naar `homelab` 200, naar een ander topic 403,
zonder token 403. Geheugengebruik: 14 MB.

Het vaste IP werkt zonder DHCP: Proxmox zet het zelf vanaf de host
(`host-managed=1` op `net0`), want er draait geen init die het netwerk
configureert.

## Datamodel

In `inventory/group_vars/proxmox/lxcs.yml`, een aparte lijst naast `pve_lxcs`:

```yaml
# Containers uit een OCI-image. Apart van pve_lxcs, want die lijst gaat ervan
# uit dat er Debian, SSH en een baseline op komt. Hier niet: dit is één
# programma, en alles wat het nodig heeft staat in env.
pve_oci_lxcs:
  - vmid: 109
    hostname: ntfy
    image: docker.io/binwiederhier/ntfy
    version: v2.28.0
    entrypoint: ntfy serve
    cores: 1
    memory: 256
    disk: { storage: vm-hdd, size: 2 }
    ip: 192.168.0.32/24
    volumes:
      - { mp: /var/lib/ntfy, storage: vm-hdd, size: 1 }
    env:
      NTFY_BASE_URL: https://ntfy.neodata.be
      NTFY_LISTEN_HTTP: ":80"
      NTFY_BEHIND_PROXY: "true"
      NTFY_CACHE_FILE: /var/lib/ntfy/cache.db
      NTFY_AUTH_FILE: /var/lib/ntfy/user.db
      NTFY_AUTH_DEFAULT_ACCESS: deny-all
      NTFY_UPSTREAM_BASE_URL: https://ntfy.sh
      NTFY_AUTH_USERS: "ruben:{{ vault_ntfy_ruben_hash }}:admin,proxmox:{{ vault_ntfy_proxmox_hash }}:user"
      NTFY_AUTH_ACCESS: "proxmox:homelab:wo"
      NTFY_AUTH_TOKENS: "proxmox:{{ vault_ntfy_proxmox_token }}:proxmox"
```

`NTFY_UPSTREAM_BASE_URL` is er voor de iPhone: Apple laat een app alleen
wakker maken via hun eigen push, en ntfy.sh geeft voor een eigen server enkel
een "kijk eens"-seintje door. De inhoud haalt de app daarna zelf bij
`ntfy.neodata.be`.

## De rol `proxmox_oci`

Praat met de Proxmox-API vanaf de controller, zoals `proxmox_lxc`. Per
container in `pve_oci_lxcs`:

1. **Template.** Staat `local:vztmpl/<naam>_<versie>.tar` er niet, dan
   `POST .../storage/local/oci-registry-pull`.
2. **Container.** Bestaat de vmid niet, dan `POST /nodes/pve01/lxc` met rootfs, volumes,
   `net0`, `unprivileged`, `onboot`, tag `oci`, en in `description` het image
   met versie.
3. **Entrypoint en env.** Lees de huidige config via de API, vergelijk, en zet
   ze via de API als ze verschillen. Is er iets veranderd, dan herstart de
   container, want env geldt pas na een start. Zo geeft een tweede run
   `ok`, geen `changed`.
4. **Versie.** Verschilt de `description` van de gevraagde versie, dan
   waarschuwt de rol en doet hij niets. Met `-e proxmox_oci_recreate=true`
   sloopt hij de container en bouwt hem opnieuw met het nieuwe image.

Opnieuw bouwen gooit ook `mp0` weg. Voor ntfy is dat bewust aanvaard: gebruikers,
rechten en tokens komen uit env en staan er na de start meteen weer. Wat
verloren gaat, is de berichtcache van de laatste twaalf uur.

Alles gaat via de API-token van Ansible, net als `proxmox_lxc`. `env` en
`entrypoint` vallen onder `VM.Config.Options` (gecontroleerd in
`check_ct_modify_config_perm` op pve01), en dat recht heeft de token al. Een
OCI-image ophalen vraagt `Datastore.AllocateTemplate`, en ook dat heeft hij.

## Inventory

De dynamische inventory stopt nu elke guest behalve `haos` in `linux` en
`guests`. Een OCI-container heeft geen SSH, dus `site.yml` zou er de baseline op
willen draaien en falen. In `homelab.proxmox.yml` wordt de regel "geen haos"
"geen haos en geen tag `oci`", en zo'n container gaat naar `appliances`. Die
groep bestaat daar al voor.

Zo hoeft een volgende OCI-container niet opnieuw in die regels. De tag regelt
het.

## Proxmox-meldingen

In de rol `proxmox_datacenter`, een nieuwe `notifications.yml`:

- Een webhook-doel `ntfy`, `POST` rechtstreeks naar `http://192.168.0.32/homelab`,
  met het token als Proxmox-secret (niet leesbaar in `notifications.cfg`). Niet
  via `ntfy.neodata.be`: een melding mag niet afhangen van Caddy en AdGuard,
  want dat zijn precies dingen die stuk kunnen gaan. Het verkeer blijft op het
  LAN.
- Een matcher die `warning` en `error` naar `ntfy` stuurt.
- `mail-to-root` en de standaard-matcher blijven staan.

Controle: `pvesh create /cluster/notifications/targets/ntfy/test` moet op je
telefoon binnenkomen.

## Back-up

De dagelijkse PBS-job neemt 109 vanzelf mee (`all: 1`, alleen 100 uitgezonderd).
Hij komt **niet** in de wekelijkse job naar de Mac mini: alles wat hem opnieuw
bouwt, staat in git en in de vault.

## Docs

- `nieuwe-guest.mdx`: nieuw "Geval 4 — Een OCI-container", met de update-stap
  en waarom een OCI-container anders is.
- De dienstpagina komt vanzelf uit `caddy_sites`.
- `TODO.md`: het eerste punt is voor Proxmox opgelost. Semaphore, PBS en
  Alertmanager blijven open.

## Bekende grenzen

- **Buitenshuis zonder VPN** krijg je het seintje van ntfy.sh wel, maar kan de
  app de inhoud niet ophalen: `ntfy.neodata.be` is alleen binnen of via de
  VPN bereikbaar. Dat oplossen is een aparte beslissing over wat je naar
  buiten opent.
- **OCI-containers zijn in Proxmox 9.2 een tech preview.** Daarom alleen ntfy
  en niets waar data van afhangt.
- **ntfy zelf moet ook bewaakt worden.** Ligt ntfy plat, dan hoor je niets. Dat
  vang je pas af met een tweede kanaal (bv. Uptime Kuma of een Alertmanager
  die ook mailt), en dat valt hier buiten.

## Buiten scope

Semaphore-meldingen, PBS-meldingen (PBS heeft een eigen meldingssysteem),
Alertmanager, en Uptime Kuma. Ze kunnen allemaal naar dezelfde ntfy wijzen, en
dat is precies waarom ntfy eerst komt.
