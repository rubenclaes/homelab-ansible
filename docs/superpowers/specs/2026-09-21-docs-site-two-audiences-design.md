# docs-site: twee publieken

Datum: 2026-09-21

## Probleem

`docs.neodata.be` is nu één publiek: ikzelf. Vier gegenereerde tabellen en twee
runbooks, met eromheen proza dat de tabellen grotendeels herhaalt.

Twee dingen ontbreken. Er is geen plek waar iemand uit het gezin kan zien wat er
draait en wat het doet — `caddy_sites` is een YAML-lijst met Engelse
eenregelaars. En een service heeft geen eigen adres: je kan niet naar één pagina
linken die alles over `photos` zegt, want die pagina bestaat niet.

## Doel

Eén site, twee helften. **Diensten** is voor het gezin: een tegelraster dat
rechtstreeks naar de service linkt. **Technisch** is voor mij: de bestaande
referentietabellen plus één pagina per service. Het proza eromheen gaat fors
terug.

## Beslissingen

| | |
| --- | --- |
| Structuur | Eén site, twee secties in dezelfde sidebar |
| Diensten | Icoontegels, vier per rij, korte regel onder de naam |
| Technische servicepagina | Eigenschappentabel, één per service, alle 33 |
| Gezinsdata | Apart bestand, gekeyed op servicenaam |
| Generatie | Ansible rendert MDX, zoals nu |
| Taal | Nederlands overal; Engelse vaktermen blijven staan |
| Bereikbaarheid | Blijft intern. Buiten scope |
| Bestaand proza | Fors inkorten, het waarom behouden. Runbooks ongemoeid |

## Informatiearchitectuur

```
/                                  Overzicht — ingekort, twee kaarten
/diensten/                         Tegelraster, gegroepeerd per categorie
/technisch/hosts/
/technisch/containers/
/technisch/stacks/
/technisch/services/               de bestaande tabel
/technisch/services/<naam>/        één per service  × 33    ← gegenereerd
/technisch/runbooks/disaster-recovery/
/technisch/runbooks/updates/
```

`reference/` en `runbooks/` verhuizen onder `technisch/`. Dat breekt de huidige
URL's. De site is alleen intern bereikbaar en heeft geen inkomende links, dus
dat kost niets, en het is wat de sidebar in twee helften laat lezen in plaats
van vier gelijkwaardige mappen.

`content/_meta.js` en `content/technisch/_meta.js` zijn met de hand geschreven;
`content/technisch/runbooks/_meta.js` verhuist ongewijzigd mee.
`content/technisch/services/_meta.js` wordt gegenereerd.

## Data

### `inventory/host_vars/caddy/directory.yml` — nieuw

Presentatie voor het gezin, los van routering. `caddy_sites` blijft over
routering gaan en wordt niet dikker.

```yaml
---
# Categorieën in de volgorde waarin ze op /diensten verschijnen.
directory_categories:
  media:     { label: "Films, foto's en muziek" }
  thuis:     { label: "Thuis" }
  bestanden: { label: "Bestanden" }

# Alleen services die hier staan, verschijnen op /diensten. De sleutel is de
# `name` uit caddy_sites. `icon` verwijst naar een sleutel in de iconenset van
# ServiceTiles; onbekend valt terug op een neutrale stip.
directory_services:
  photos:
    category: media
    icon: camera
    label: "Foto's"
    blurb: "Onze foto's en video's"
  plex:
    category: media
    icon: film
    label: "Films & series"
    blurb: "Kijken op TV of telefoon"
  audiobooks:
    category: media
    icon: headphones
    label: "Luisterboeken"
    blurb: "Boeken en podcasts"
  overseerr:
    category: media
    icon: plus
    label: "Aanvragen"
    blurb: "Vraag een film aan"
  wizarr:
    category: media
    icon: user-plus
    label: "Uitnodigen"
    blurb: "Geef iemand toegang"
  spullen:
    category: thuis
    icon: box
    label: "Wat ligt waar"
    blurb: "Met QR-labels"
  memos:
    category: thuis
    icon: note
    label: "Notities"
    blurb: "Snelle notities"
  pairdrop:
    category: bestanden
    icon: send
    label: "Delen"
    blurb: "Naar een ander toestel"
  pdf:
    category: bestanden
    icon: file
    label: "PDF's"
    blurb: "Samenvoegen, splitsen"
```

Negen tegels. `blurb` is een korte regel, geen zin — de tegel is vier per rij
breed. Toon is Nederlands en huiselijk: "Wat ligt waar", niet "Homebox".

Twee services staan er bewust niet in:

- **jellyfin** — naast `plex` levert dat twee tegels met hetzelfde icoon en
  dezelfde belofte op. Jellyfin houdt zijn route en zijn technische pagina,
  maar concurreert niet om dezelfde klik.
- **home** (Homepage) — doet hetzelfde werk als `/diensten` zelf. Twee
  voordeuren die dezelfde services opsommen lopen uiteen, en de
  handonderhouden loopt weg. `/diensten` wordt de voordeur.

### `caddy_sites` — `desc` wordt Nederlands

Ongeveer vijftien `desc`-waarden zijn Engels en worden herschreven. Vaktermen
blijven staan; dat is de stijl die `index.mdx` al hanteert.

```
prowlarr    Indexer manager feeding Sonarr and Radarr
         →  Indexerbeheer voor Sonarr en Radarr
tinyauth    Auth middleware used by Caddy forward_auth
         →  Auth-middleware achter Caddy's forward_auth
prometheus  Metrics store scraped by Grafana
         →  Metrics-store die Grafana scrapet
```

`books` staat nu op `"TODO: describe this service"` en krijgt een echte
omschrijving. Lukt dat niet — de poort is `6061` en het is onduidelijk wat er
draait — dan hoort dat als punt in `TODO.md`, niet als TODO op een pagina.

### Validatie

`docs.yml` krijgt een `assert` vóór het renderen:

- elke sleutel in `directory_services` bestaat in `caddy_sites | map(attribute='name')`
- elke `category` bestaat in `directory_categories`

Faalt de run, dan is er hernoemd of verwijderd zonder mee te gaan. Een dode
tegel verschijnt nooit, want de run haalt het niet.

## Generatie

### Sjablonen

| Sjabloon | Rendert naar |
| --- | --- |
| `docs/diensten.md.j2` | `content/diensten.mdx` |
| `docs/services.md.j2` | `content/technisch/services/index.mdx` |
| `docs/service.md.j2` | `content/technisch/services/<naam>.mdx`, in een lus |
| `docs/services-meta.js.j2` | `content/technisch/services/_meta.js` |
| `docs/hosts.md.j2` | `content/technisch/hosts.mdx` |
| `docs/containers.md.j2` | `content/technisch/containers.mdx` |
| `docs/stacks.md.j2` | `content/technisch/stacks.mdx` |

`content/technisch/services/` wordt vóór elke render weggegooid en opnieuw
aangemaakt — dezelfde `absent` → `directory` die `docs.yml` al gebruikt bij het
publiceren. Zonder dat blijft een verwijderde service als pagina achter.

### Upstream in het sjabloon

De servicepagina toont het echte upstream-adres:

```jinja
{% set up = s.upstream | default(
     (hostvars[s.host].ansible_host | default('?')) ~ ':' ~ s.port) %}
```

`hostvars[h].ansible_host` direct uitlezen is veilig vanuit de
localhost-play — `hosts.md.j2` doet het al. Wat níét werkt is een
inventory-variabele lezen wiens *waarde* een `hostvars[...]`-template is, zoals
`caddy_tinyauth_upstream`; dat is wat `docs.yml` en `report.yml` eerder brak.
Een site met `upstream:` heeft geen inventory-host, vandaar de `default('?')`.

### Iconen

Nextra levert geen iconenset. Een component `ServiceTiles` in
`docs-site/components/` houdt een vaste set lijniconen vast en wordt via
`mdx-components.js` globaal beschikbaar gemaakt, zodat gegenereerde MDX hem
zonder import kan aanroepen. `diensten.mdx` geeft de data door als prop:

```mdx
<ServiceTiles
  categories={ {{ directory_categories | to_json }} }
  services={ {{ tiles | to_json }} } />
```

Ansible levert data, React tekent. Een onbekende `icon` valt terug op een
neutrale stip in plaats van de build te breken.

## Paginaontwerp

### `/diensten`

Per categorie een klein hoofdje in kapitalen, daaronder een raster van vier
tegels per rij; twee op telefoonbreedte. Een tegel is icoon, naam, één korte
regel, en is in zijn geheel een link naar `https://<naam>.neodata.be`. Geen
tussenpagina — de tegel is de link.

Boven het raster twee zinnen, niet meer. Geen callout over hoe de pagina
gegenereerd wordt: die pagina is niet voor mij.

### `/technisch/services/<naam>`

Titel is de servicenaam, daaronder `desc` als ondertitel, daaronder een
eigenschappentabel in dezelfde stijl als de rest van Referentie:

| Eigenschap | Waarde |
| --- | --- |
| URL | `<naam>.neodata.be`, als link |
| Upstream | `192.168.0.15:2283` |
| Host | link naar de hostpagina |
| Poort | `2283` |
| Groepen | `docker_hosts` |
| Eigenschappen | TLS-upstream · achter tinyauth · forwarded headers · host-header |

Leeg blijft `—`. Onderaan één regel die zegt uit welke inventory-sleutel de
pagina komt.

Een link service → stack zit er niet in: `caddy_sites` weet niet in welke
stack een container draait, en `docker_stacks_list` is niet volledig
(`media-stack` ontbreekt, zie `TODO.md`). Dat verzinnen levert een link op die
liegt. De hostpagina is de brug.

## Het inkorten

- **`index.mdx`** — "Hoe het in elkaar zit" gaat van vijf alinea's naar twee.
  Blijft: de vault-splitsing op blast radius, en dat de inventory live uit
  Proxmox komt. Weg: de opsomming van welke rol wat doet, die de hostpagina al
  toont. "Conventies" verhuist naar `README.md` voor zover het daar nog niet
  staat. De vier kaarten worden twee: Diensten en Technisch.
- **`hosts.md.j2`** — de slotalinea over het `ansible`-serviceaccount weg, die
  staat in `README.md`. De alinea over live adressen uit Proxmox blijft: dat
  legt uit waarom de kolom klopt terwijl twee containers DHCP draaien.
- **`services.md.j2`, `containers.md.j2`, `stacks.md.j2`** — de
  waarschuwingscallout blijft, het proza eromheen wordt één regel.
- **Runbooks** — ongemoeid. Dat zijn procedures; die hebben hun woorden nodig.

## Buiten scope

- **Bereikbaarheid.** `docs.neodata.be` antwoordt alleen op private ranges en
  Tailscale (`roles/caddy/templates/Caddyfile.j2`), de rest krijgt 403. Het
  gezin kan `/diensten` dus niet openen van op mobiele data, terwijl `photos`
  en `plex` dat wel zijn. Bewust zo gelaten; de Caddyfile wordt niet aangeraakt.
- Inloguitleg, app-instructies per dienst, FAQ's per service.
- Het opruimen dat `TODO.md` al noemt: de dode `torrent`-route, de dubbele
  Pocket ID, `media-stack` buiten Ansible. De servicepagina's maken dat
  zichtbaarder, maar lossen het niet op.

## Risico's

- **33 gegenereerde bestanden in git.** Nu zijn het er vier. De diff wordt
  luider; daar staat tegenover dat je in de diff ziet wanneer een service
  verandert. Ze worden niet genegeerd, want dan is `npm run dev` leeg zonder
  eerst Ansible te draaien.
- **URL's breken.** Alles onder `/reference/` en `/runbooks/` verhuist.
  Geaccepteerd.
- **`directory.yml` kan uiteenlopen** met `caddy_sites`. De assert vangt een
  hernoeming of verwijdering. Wat hij niet vangt: een nieuwe service die nooit
  aan het gezin getoond wordt. Dat is een keuze, geen fout.

## Verificatie

1. `ansible-lint` en `ansible-playbook playbooks/docs.yml --syntax-check` schoon.
2. `playbooks/docs.yml` draait door tot en met de build.
3. `docs-site/out/` bevat `diensten/index.html`, `technisch/services/index.html`
   en 33 maal `technisch/services/<naam>/index.html`.
4. De assert faalt aantoonbaar: hernoem tijdelijk een sleutel in
   `directory_services` en bevestig dat de run stopt vóór het renderen.
5. Een tegel op `/diensten` opent de service zelf, niet een documentatiepagina.
6. Op telefoonbreedte staan er twee tegels per rij en valt er niets buiten beeld.
