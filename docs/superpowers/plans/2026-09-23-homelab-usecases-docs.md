# Homelab-deel in docs-site Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Een deel "Homelab" op docs.neodata.be met use-case-pagina's (toestellen, toegang, internet en DNS) voor de beheerder, naast het bestaande "Technisch".

**Architecture:** Handgeschreven MDX in `docs-site/content/homelab/`, drie mappen met elk een `_meta.js`, één startpagina met een "Ik wil…"-tabel. Geen generatie via Ansible. Bestaande runbooks worden gelinkt, niet herhaald.

**Tech Stack:** Nextra 4.5 (Next 15), MDX, `nextra/components` (`Steps`, `Callout`).

**Spec:** `docs/superpowers/specs/2026-09-23-homelab-usecases-docs-design.md`

## Global Constraints

- Publiek: alleen de beheerder. Nederlands; Engelse vaktermen en UI-labels blijven Engels.
- Alleen wat vandaag werkt. Wat nog gebouwd moet worden → `TODO.md`, niet in de docs.
- Runbook-stijl: korte intro, `<Steps>` met per stap commando of klikwerk + 1–3 zinnen; klikwerk als tabel `Scherm · Wat · Waarom`; het waarom onderaan onder `## Goed om te weten`.
- Geen tussenpagina per groep. Eén startpagina `homelab/index.mdx`, titel in sidebar "Start hier".
- Elke Homelab-pagina is vanaf Overzicht in twee klikken bereikbaar.
- Interne links absoluut en met afsluitende slash: `/homelab/toegang/vpn-geven/`.
- UniFi wordt met de hand beheerd; geen Ansible voor UniFi voorstellen.

## Feiten (uit de repo en van de eigenaar, 23-09)

- NeoGate: `https://neogate.neodata.be`, pagina **Gezin** (`/household`, alleen owner). Uitnodigen: **Uitnodigen** → diensten aanvinken in het toegangsraster → NeoGate maakt de accounts en stuurt de uitnodigingen; **Uitnodiging kopiëren** kopieert de link. Plugins: Plex, Jellyfin, Immich, Tailscale, Seerr, Grimmory. Tailscale-uitnodiging alleen als "netwerk"-toegang aangevinkt is.
- Intrekken in NeoGate: `⋯` (of lang drukken / rechtsklik) op een lid → **Toegang intrekken** of **Verwijderen**; per dienst: uitvinken in het raster. Bij Tailscale trekt NeoGate alleen de **uitnodiging** in; een aanvaarde uitnodiging blijft lid van de tailnet.
- Toegang tot diensten gaat altijd via NeoGate (eigenaar).
- WireGuard "Neodata VPN" in UniFi: `vpn.neodata.be:51820`, subnet `10.10.30.0/24`, allowed IPs `192.168.0.0/24`, DNS `192.168.0.29` (ingebakken in het profiel). Nu één profiel: iPhone `10.10.30.2/32`. Anderen krijgen soms een profiel. Risico: server op "Existing IP Address", WAN-wijziging breekt hem (staat op TODO). Test: wifi uit, VPN aan, `pve01.home.arpa`.
- Tailscale: `--accept-routes` staat overal uit → via Tailscale kom je niet op `192.168.0.x`; van buitenaf naar het LAN is WireGuard. Eigen apparaat (geen telefoon) op de tailnet: runbook Netwerk, geval 3 (`/technisch/runbooks/netwerk/`).
- Twee wegen naar binnen: Tailscale draait op pve01, WireGuard op de gateway; elk werkt als de ander plat ligt (netwerk.mdx "Twee wegen naar binnen").
- Geen gastennetwerk: gasten op het gewone wifi.
- DNS: UniFi-DHCP deelt `192.168.0.29` (AdGuard) uit; `<host>.home.arpa` bestaat alleen voor hosts in de inventory.
- Vast adres: UniFi → client → **Fixed IP** aan op het huidige adres (zie `/technisch/runbooks/nieuwe-guest/vm/`).
- AdGuard: blocklists in `inventory/host_vars/adguard/main.yml` (`adguard_filters`), de rol haalt lijsten weg die er niet in staan. Custom filtering rules en per-client instellingen beheert de rol niet: die blijven in het AdGuard-scherm (`https://dns.neodata.be`).
- PairDrop (`pairdrop.neodata.be`) werkt voor iedereen op hetzelfde netwerk.

## Review Focus

1. Een link of anker naar een pagina die hernoemd is ("Welk geval?" → "Start hier" verandert alleen de sidebar-titel, niet de URL) — de linkcheck moet 0 fouten geven.
2. Een pagina die belooft dat NeoGate iemand volledig van de tailnet haalt — "Toegang afnemen" en "Toestel kwijt" moeten de Tailscale-console-stap hebben.
3. Een WireGuard-profiel met verkeerde DNS — "Iemand VPN geven" moet de DNS-controle (`192.168.0.29`) als eigen stap hebben.
4. Een blokkade in het AdGuard-scherm via een blocklist toevoegen (wordt bij de volgende run weggehaald) — "Blokkeren" moet dat verschil in een Callout zeggen.
5. Een UI-label dat niet klopt met de huidige UniFi/Tailscale-versie — elk klikpad één keer nalopen in de echte UI of als "(label kan verschillen)" markeren.

---

## Bestanden

```
docs-site/content/_meta.js                          + homelab
docs-site/content/index.mdx                         "Ik zoek…"-tabel + Homelab-rijen
docs-site/content/homelab/_meta.js
docs-site/content/homelab/index.mdx                 Start hier
docs-site/content/homelab/toestellen/_meta.js
docs-site/content/homelab/toestellen/nieuw-toestel.mdx
docs-site/content/homelab/toestellen/toestel-kwijt.mdx
docs-site/content/homelab/toegang/_meta.js
docs-site/content/homelab/toegang/van-buitenaf.mdx
docs-site/content/homelab/toegang/diensten-geven.mdx
docs-site/content/homelab/toegang/vpn-geven.mdx
docs-site/content/homelab/toegang/gast-op-bezoek.mdx
docs-site/content/homelab/toegang/toegang-afnemen.mdx
docs-site/content/homelab/internet-en-dns/_meta.js
docs-site/content/homelab/internet-en-dns/blokkeren.mdx
docs-site/content/technisch/runbooks/nieuwe-guest/_meta.js       index → 'Start hier'
docs-site/content/technisch/runbooks/dienst-toevoegen/_meta.js   index → 'Start hier'
TODO.md                                             vier punten erbij
```

## De test: linkcheck

Geen testframework in docs-site. De test is: bouwen, dan elke interne link en elk anker in `out/` controleren. Script in de scratchpad (niet in de repo), `check_links.py`:

```python
#!/usr/bin/env python3
"""Check every internal href in docs-site/out: target page exists, anchor exists."""
import pathlib, re, sys
out = pathlib.Path(sys.argv[1])
pages = {}
for f in out.rglob('*.html'):
    rel = f.relative_to(out).as_posix()
    url = '/' + (rel[:-len('index.html')] if rel.endswith('index.html') else rel[:-5] + '/')
    pages[url] = f.read_text(errors='ignore')
bad = 0
for url, html in pages.items():
    for href in set(re.findall(r'href="(/[^"]*)"', html)):
        if href.startswith(('/_next', '/_pagefind', '/favicon')):
            continue
        path, _, anchor = href.partition('#')
        path = path if path.endswith('/') else path + '/'
        target = pages.get(path)
        if target is None:
            print(f'{url}: page missing {href}'); bad += 1
        elif anchor and f'id="{anchor}"' not in target:
            print(f'{url}: anchor missing {href}'); bad += 1
print(f'{bad} broken'); sys.exit(1 if bad else 0)
```

Draaien: `cd docs-site && npx next build >/dev/null && python3 <scratchpad>/check_links.py out`
Verwacht na elke taak: `0 broken`.

---

### Task 1: Skelet, "Start hier" en linkcheck

**Files:**
- Create: `docs-site/content/homelab/_meta.js`, `docs-site/content/homelab/index.mdx`, `…/toestellen/_meta.js`, `…/toegang/_meta.js`, `…/internet-en-dns/_meta.js`
- Modify: `docs-site/content/_meta.js`, `…/runbooks/nieuwe-guest/_meta.js`, `…/runbooks/dienst-toevoegen/_meta.js`
- Test: `check_links.py` (scratchpad)

**Interfaces:**
- Produces: de URL's uit de bestandslijst; `homelab/index.mdx` linkt al naar alle acht pagina's, dus de linkcheck faalt tot taken 2–4 klaar zijn.

- [ ] **Step 1: Schrijf `check_links.py`** in de scratchpad (code hierboven). Bouw en draai hem op de huidige site. Verwacht: `0 broken` (nulmeting).

- [ ] **Step 2: Sidebar**

`docs-site/content/_meta.js`:
```js
export default {
  index: 'Overzicht',
  homelab: 'Homelab',
  technisch: 'Technisch'
}
```

`docs-site/content/homelab/_meta.js`:
```js
export default {
  index: 'Start hier',
  toestellen: 'Toestellen',
  toegang: 'Toegang',
  'internet-en-dns': 'Internet en DNS'
}
```

`homelab/toestellen/_meta.js`:
```js
export default {
  'nieuw-toestel': 'Nieuw toestel op het netwerk',
  'toestel-kwijt': 'Toestel kwijt'
}
```

`homelab/toegang/_meta.js`:
```js
export default {
  'van-buitenaf': 'Zelf van buitenaf binnen',
  'diensten-geven': 'Iemand diensten geven',
  'vpn-geven': 'Iemand VPN geven',
  'gast-op-bezoek': 'Gast op bezoek',
  'toegang-afnemen': 'Toegang afnemen'
}
```

`homelab/internet-en-dns/_meta.js`:
```js
export default {
  blokkeren: 'Site blokkeren of deblokkeren'
}
```

In `runbooks/nieuwe-guest/_meta.js` en `runbooks/dienst-toevoegen/_meta.js`: `index: 'Welk geval?'` → `index: 'Start hier'`.

- [ ] **Step 3: `homelab/index.mdx`**

```mdx
---
title: Homelab
---

# Homelab

Wat je doet buiten Ansible: UniFi, Tailscale, WireGuard, NeoGate, AdGuard.
Wat via Ansible loopt staat onder [Technisch](/technisch/runbooks/nieuwe-guest/).

| Ik wil… | Ga naar |
| --- | --- |
| een nieuw toestel op het netwerk zetten, met een vast adres | [Nieuw toestel](/homelab/toestellen/nieuw-toestel/) |
| een toestel dat kwijt of weg is afsluiten | [Toestel kwijt](/homelab/toestellen/toestel-kwijt/) |
| zelf van buitenaf aan het homelab | [Zelf van buitenaf](/homelab/toegang/van-buitenaf/) |
| iemand Immich, Plex of een andere dienst geven | [Iemand diensten geven](/homelab/toegang/diensten-geven/) |
| iemand VPN-toegang geven | [Iemand VPN geven](/homelab/toegang/vpn-geven/) |
| iemand op bezoek laten meedoen | [Gast op bezoek](/homelab/toegang/gast-op-bezoek/) |
| iemand zijn toegang afnemen | [Toegang afnemen](/homelab/toegang/toegang-afnemen/) |
| een site blokkeren of juist deblokkeren | [Blokkeren](/homelab/internet-en-dns/blokkeren/) |

Nieuwe machine of dienst op pve01? Dat is [Nieuwe machine](/technisch/runbooks/nieuwe-guest/)
en [Dienst toevoegen](/technisch/runbooks/dienst-toevoegen/).
```

- [ ] **Step 4: Bouw + linkcheck.** Verwacht: FAIL, precies 8 `page missing` vanaf `/homelab/` (de pagina's van taken 2–4). Andere fouten = fout in deze taak.

- [ ] **Step 5: Commit**
```bash
git add docs-site/content/_meta.js docs-site/content/homelab docs-site/content/technisch/runbooks/*/_meta.js
git commit -m "docs-site: Homelab-deel, skelet en Start hier"
```

---

### Task 2: Toestellen

**Files:**
- Create: `homelab/toestellen/nieuw-toestel.mdx`, `homelab/toestellen/toestel-kwijt.mdx`

**Interfaces:**
- Consumes: URL `/homelab/toegang/toegang-afnemen/` (taak 3) — linken mag al.

- [ ] **Step 1: `nieuw-toestel.mdx`** — frontmatter `title: Nieuw toestel op het netwerk`. Imports `Steps, Callout`. Intro: voorbeeld "een nieuwe printer of TV". `<Steps>`:
  1. **Verbind het toestel met het wifi** — gewoon wifi, er is geen apart gastennetwerk.
  2. **Zoek het in UniFi** — tabel Scherm · Wat · Waarom: UniFi Network → Client Devices → nieuwste bovenaan / zoek op fabrikant.
  3. **Geef het een naam** — client openen → Settings → Alias; waarom: in AdGuard-querylog en UniFi herken je het later.
  4. **Zet het adres vast (als iets het bij adres moet vinden)** — Settings → Fixed IP aan op het huidige adres. Wanneer: printers, dingen met een Caddy-route (`upstream:`), niet voor telefoons.
  5. **Moet het een mooi adres krijgen?** — link naar `/technisch/runbooks/dienst-toevoegen/adres/` (de `upstream:`-callout).
  `## Goed om te weten`: `home.arpa`-namen bestaan alleen voor machines in de inventory, niet voor toestellen; waarom UniFi met de hand (UniFi-rol is gebouwd en bewust weggehaald: 20 seconden klikken per toestel tegenover een API-account en onderhoud).

- [ ] **Step 2: `toestel-kwijt.mdx`** — `title: Toestel kwijt`. Callout bovenaan: "Dringend? Doe eerst stap 1 en 2." `<Steps>`:
  1. **Tailscale** — admin console → Machines → toestel → `⋯` → Remove. Of Disable key expiry uit / Expire key.
  2. **WireGuard** — UniFi → Settings → VPN → VPN Server → Neodata VPN → clientprofiel van dat toestel verwijderen.
  3. **NeoGate** — alleen als de persoon ook weg moet: zie [Toegang afnemen](/homelab/toegang/toegang-afnemen/).
  4. **UniFi** — client → Block (optioneel, voor een gestolen toestel dat nog in wifi-bereik kan komen) en de Fixed IP weghalen.
  5. **App-sessies** — Immich/Plex: uitloggen van alle toestellen in de app zelf als het toestel ingelogd bleef.

- [ ] **Step 3: Bouw + linkcheck.** Verwacht: 6 `page missing` (alleen nog taak 3 en 4).

- [ ] **Step 4: Loop de UniFi-klikpaden na** in de echte UniFi-UI; pas labels aan waar ze verschillen.

- [ ] **Step 5: Commit** `git add docs-site/content/homelab/toestellen && git commit -m "docs-site: Homelab → Toestellen"`

---

### Task 3: Toegang

**Files:**
- Create: `homelab/toegang/van-buitenaf.mdx`, `diensten-geven.mdx`, `vpn-geven.mdx`, `gast-op-bezoek.mdx`, `toegang-afnemen.mdx`

- [ ] **Step 1: `van-buitenaf.mdx`** — `title: Zelf van buitenaf binnen`. Tabel bovenaan "Wat wil je bereiken → welke weg":

| Wil je… | Neem | Waarom |
| --- | --- | --- |
| `*.neodata.be`-diensten, `192.168.0.x`, `*.home.arpa` | WireGuard "Neodata VPN" | Tailscale komt niet op het LAN (`--accept-routes` uit) |
| een host op de tailnet via zijn 100.x-adres | Tailscale | |
| iets terwijl de UniFi-gateway plat ligt | Tailscale | draait op pve01, niet op de gateway |

  `<Steps>`: WireGuard aanzetten op iPhone → test (wifi uit, `pve01.home.arpa`) → werkt niet? link `/technisch/runbooks/netwerk/` (De VPN nakijken). Callout: WAN-adres dynamisch, staat op TODO.

- [ ] **Step 2: `diensten-geven.mdx`** — `title: Iemand diensten geven`. Callout: altijd via NeoGate, nooit met de hand in de app. `<Steps>`: open `neogate.neodata.be` → **Gezin** → **Uitnodigen** (bestaand account: **Importeren**) → diensten aanvinken (tabel: welke plugins: Plex, Jellyfin, Immich, Tailscale, Seerr, Grimmory; "netwerk" = Tailscale-uitnodiging) → **Uitnodiging kopiëren** en doorsturen → controleren: lid staat in Gezin met de aangevinkte diensten. Achteraf iets bijgeven: open het lid, vink extra dienst aan.

- [ ] **Step 3: `vpn-geven.mdx`** — `title: Iemand VPN geven`. Keuzetabel: WireGuard (ziet het hele LAN, profiel per toestel, beheer in UniFi) vs Tailscale via NeoGate (alleen de tailnet, persoon beheert zelf). `## WireGuard-profiel` `<Steps>`: UniFi → Settings → VPN → VPN Server → Neodata VPN → **Add Client** (naam `persoon-toestel`) → **controleer de DNS: `192.168.0.29`** (eigen stap, Callout waarom: ingebakken in het profiel, achteraf wijzigen = opnieuw importeren) → QR-code of `.conf` downloaden → op het toestel importeren (WireGuard-app) → test via mobiele data. `## Tailscale` → link naar diensten-geven (netwerk aanvinken).

- [ ] **Step 4: `gast-op-bezoek.mdx`** — `title: Gast op bezoek`. Tabel "Wat wil de gast → wat doe je": wifi → wachtwoord van het gewone wifi (geen gastennetwerk); bestanden uitwisselen → `pairdrop.neodata.be`, werkt meteen op hetzelfde wifi; film kijken → Plex via NeoGate ([Iemand diensten geven]); foto's delen → Immich-deellink vanuit de app, geen account nodig. Callout: gasten zitten op hetzelfde netwerk als alles; een gastennetwerk staat op de TODO.

- [ ] **Step 5: `toegang-afnemen.mdx`** — `title: Toegang afnemen`. `<Steps>`: NeoGate → Gezin → `⋯` op het lid → **Toegang intrekken** (alles) of **Verwijderen**; per dienst: uitvinken → **Tailscale-console** (Callout warning: NeoGate trekt alleen de uitnodiging in, een aanvaarde blijft lid) → Users → persoon → Remove user, en zijn Machines → WireGuard → UniFi-profiel van die persoon verwijderen → controleer: Gezin toont hem niet meer, Tailscale Users niet meer, UniFi VPN-clients niet meer.

- [ ] **Step 6: Bouw + linkcheck.** Verwacht: 1 `page missing` (blokkeren).

- [ ] **Step 7: Loop de NeoGate-, Tailscale- en UniFi-klikpaden na** in de echte UI's.

- [ ] **Step 8: Commit** `git add docs-site/content/homelab/toegang && git commit -m "docs-site: Homelab → Toegang"`

---

### Task 4: Internet en DNS

**Files:**
- Create: `homelab/internet-en-dns/blokkeren.mdx`

- [ ] **Step 1: `blokkeren.mdx`** — `title: Site blokkeren of deblokkeren`. Keuzetabel:

| Je wil… | Waar | Blijft het? |
| --- | --- | --- |
| één site snel deblokkeren of blokkeren | AdGuard-scherm → Filters → Custom filtering rules | ja, de rol raakt eigen regels niet |
| weten waarom iets geblokkeerd is | AdGuard-scherm → Query Log | |
| een hele blocklist erbij of eraf | `inventory/host_vars/adguard/main.yml` → `adguard_filters` | ja; in het scherm toevoegen wordt bij de volgende run weggehaald |

  `<Steps>` voor deblokkeren: `dns.neodata.be` → Query Log → zoek het domein → **Unblock** (maakt `@@||domein^`) → test op het toestel. Voor een blocklist: `$EDITOR` → `ansible-playbook playbooks/site.yml --limit adguard --check --diff` → zonder `--check` → commit en push. Callout: het Review-Focus-punt 4.

- [ ] **Step 2: Bouw + linkcheck.** Verwacht: `0 broken`.

- [ ] **Step 3: Commit** `git add docs-site/content/homelab/internet-en-dns && git commit -m "docs-site: Homelab → Internet en DNS"`

---

### Task 5: Overzicht, TODO en eindcontrole

**Files:**
- Modify: `docs-site/content/index.mdx`, `TODO.md`

- [ ] **Step 1: Overzicht** — in `index.mdx` bovenaan de "Ik zoek…"-tabel een rij `| Iets met toestellen, toegang of DNS | [Homelab](/homelab/) |`.

- [ ] **Step 2: `TODO.md`** — onder de bestaande grotere projecten, in de stijl van het bestand:
  - Een apart gastennetwerk in UniFi
  - NeoGate: Tailscale-lid echt verwijderen, niet alleen de uitnodiging
  - Meldingen via ntfy (ontwerp: `docs/superpowers/specs/2026-09-23-ntfy-oci-design.md`)
  - Apple MDM, en daarna een Homelab-pagina "Mac of iPhone klaarzetten"

- [ ] **Step 3: Bouw + linkcheck.** Verwacht: `0 broken`.

- [ ] **Step 4: Twee-klikken-check** — elke URL uit de `homelab/index.mdx`-tabel komt voor in de gebouwde `out/homelab/index.html`, en `out/index.html` linkt naar `/homelab/`:
```bash
cd docs-site && for p in toestellen/nieuw-toestel toestellen/toestel-kwijt toegang/van-buitenaf toegang/diensten-geven toegang/vpn-geven toegang/gast-op-bezoek toegang/toegang-afnemen internet-en-dns/blokkeren; do grep -q "href=\"/homelab/$p/\"" out/homelab/index.html && echo "OK $p" || echo "MIST $p"; done; grep -q 'href="/homelab/"' out/index.html && echo "OK overzicht"
```
Verwacht: 9× OK.

- [ ] **Step 5: Commit** `git add docs-site/content/index.mdx TODO.md && git commit -m "docs-site: Homelab op Overzicht, vervolgprojecten op TODO"`
