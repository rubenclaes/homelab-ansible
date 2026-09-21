# docs-site: Two Audiences — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split `docs.neodata.be` into `/diensten` — a tile grid for the family that links straight to each service — and `/technisch`, the existing reference tables plus one generated page per service.

**Architecture:** The site keeps its current shape: Ansible renders MDX into `docs-site/content/`, Nextra static-exports it, Caddy serves the folder. Two things are added. Family-facing presentation moves into a new `inventory/host_vars/caddy/directory.yml` keyed by service name, so `caddy_sites` stays about routing. A React component drawn from that data renders the tiles, and a per-service template renders 33 technical pages into a directory that is wiped and rebuilt on every run.

**Tech Stack:** Nextra 4.5.0 (pinned), Next 15.5.25, React 19.3.0, Pagefind 1.3.0, ansible-core 2.21.4, Jinja2 templates, Caddy.

**Spec:** `docs/superpowers/specs/2026-09-21-docs-site-two-audiences-design.md`

## Global Constraints

- `ansible-lint` must pass at the **`production`** profile after every task.
- `ansible-playbook --syntax-check` must pass for every file in `playbooks/`.
- `bin/check-vaulted` must pass; `directory.yml` holds no secrets and stays plaintext.
- FQCN for every Ansible module. Every task named, starting with a capital letter.
- **No new npm dependencies.** `package.json` is not modified by this plan. Nextra stays pinned at `4.5.0`.
- `next.config.mjs` keeps `output: 'export'`, `trailingSlash: true`, `images: { unoptimized: true }`. Do not change them — the site is served by a plain file server with no Node process.
- **All reader-facing copy is Dutch.** English technical nouns stay English inside Dutch sentences (`indexer`, `stack`, `middleware`, `control plane`, `upstream`). This matches `content/index.mdx`.
- Generated MDX is committed. `docs-site/.gitignore` is not modified.
- Use `git mv` for moves so history follows the file.
- The Caddyfile is **not** touched. Reachability is out of scope.

## Prerequisites

Tasks 1, 4 and 7 are verified entirely with `npm run build` and need nothing but the repo.

Tasks 3, 5, 6 and 8 run `playbooks/docs.yml`, which gathers facts from every host and reads the Proxmox dynamic inventory. They must be run from the workstation, on the home network or Tailscale, with the vault password available. Confirm before starting:

```bash
cd docs-site && npm ci --no-audit --no-fund && cd ..
ansible-inventory --graph >/dev/null && echo "inventory OK"
```

---

### Task 1: Move the content tree under `technisch/`

Everything that exists today moves; nothing is generated differently yet. This is the URL change on its own, so that if it is wrong it is wrong in isolation.

**Files:**
- Move: `docs-site/content/reference/{hosts,containers,stacks,services}.mdx` → `docs-site/content/technisch/`
- Move: `docs-site/content/runbooks/` → `docs-site/content/technisch/runbooks/`
- Delete: `docs-site/content/reference/_meta.js`
- Create: `docs-site/content/technisch/_meta.js`
- Modify: `docs-site/content/_meta.js`
- Modify: `playbooks/docs.yml:14-18`

**Interfaces:**
- Produces: the URL prefix `/technisch/` and the `_meta.js` key `services`, which Task 6 reuses for a folder rather than a file. Both are relied on by Tasks 4, 6 and 7.

- [ ] **Step 1: Move the files**

```bash
cd /Users/rubenclaes/Development/homelab-ansible/docs-site/content
mkdir -p technisch
git mv reference/hosts.mdx      technisch/hosts.mdx
git mv reference/containers.mdx technisch/containers.mdx
git mv reference/stacks.mdx     technisch/stacks.mdx
git mv reference/services.mdx   technisch/services.mdx
git mv runbooks                 technisch/runbooks
git rm reference/_meta.js
rmdir reference 2>/dev/null || true
```

- [ ] **Step 2: Write the two `_meta.js` files**

`docs-site/content/_meta.js` — replace the whole file:

```js
export default {
  index: 'Overzicht',
  diensten: 'Diensten',
  technisch: 'Technisch'
}
```

`docs-site/content/technisch/_meta.js` — new file:

```js
// De pagina's in deze map worden geschreven door playbooks/docs.yml.
// Alleen runbooks/ is met de hand geschreven.
export default {
  hosts: 'Hosts',
  containers: 'LXC-containers',
  stacks: 'Docker-stacks',
  services: 'Services',
  runbooks: 'Runbooks'
}
```

`docs-site/content/technisch/runbooks/_meta.js` moves unchanged and needs no edit.

- [ ] **Step 3: Point the playbook at the new directory**

In `playbooks/docs.yml`, the "Render the generated reference pages" task — change the `dest` only:

```yaml
      ansible.builtin.template:
        src: "docs/{{ item }}.md.j2"
        dest: "{{ docs_site }}/content/technisch/{{ item }}.mdx"
        mode: "0644"
```

Leave `docs_pages: [services, hosts, containers, stacks]` alone; Task 6 changes it.

- [ ] **Step 4: Build and verify the new URLs exist**

```bash
cd docs-site && rm -rf out .next && npm run build
ls out/technisch/hosts/index.html \
   out/technisch/containers/index.html \
   out/technisch/stacks/index.html \
   out/technisch/services/index.html \
   out/technisch/runbooks/updates/index.html \
   out/technisch/runbooks/disaster-recovery/index.html
```

Expected: six paths listed, no error. Then confirm the old tree is gone:

```bash
test ! -d out/reference && test ! -d out/runbooks && echo "old URLs gone"
```

Expected: `old URLs gone`.

- [ ] **Step 5: Verify the sidebar reads as two halves**

```bash
cd docs-site && npm run dev
```

Open `http://localhost:3000`. Expected: sidebar shows `Overzicht` and `Technisch` (no `Diensten` yet — that page does not exist until Task 5). `Technisch` expands to Hosts, LXC-containers, Docker-stacks, Services, Runbooks in that order. Stop the dev server.

- [ ] **Step 6: Lint the playbook**

```bash
cd /Users/rubenclaes/Development/homelab-ansible
ansible-lint && ansible-playbook --syntax-check playbooks/docs.yml
```

Expected: both clean.

- [ ] **Step 7: Commit**

```bash
git add -A docs-site/content playbooks/docs.yml
git commit -m "Move the reference and runbook pages under technisch/

The site is about to gain a second audience. Grouping everything that
exists today under one prefix is what lets the sidebar read as two
halves rather than four sibling folders.

URLs under /reference/ and /runbooks/ break. The site answers only to
private ranges and Tailscale and has no inbound links, so that costs
nothing.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Rewrite the `desc` values in Dutch

Pure data. The per-service pages in Task 6 put `desc` in their subtitle, so it is worth having right before those pages exist.

**Files:**
- Modify: `inventory/host_vars/caddy/main.yml:30-73`

**Interfaces:**
- Produces: `caddy_sites[*].desc`, Dutch, no `TODO` strings. Consumed by Tasks 5 and 6.

- [ ] **Step 1: Rewrite every English `desc`**

Apply exactly these. Entries not listed are already Dutch and stay untouched.

```
portainer    Docker management UI for docker
          →  Docker-beheer voor de docker-host
semaphore    Ansible control plane — runs the playbooks on a schedule
          →  Ansible control plane — draait de playbooks volgens schema
monitoring   Uptime Kuma — uptime checks and alerting
          →  Uptime Kuma — bereikbaarheidscontroles en meldingen
prometheus   Metrics store scraped by Grafana
          →  Metrics-store die Grafana scrapet
home         Homepage — the start page and service dashboard
          →  Homepage — startpagina met alle diensten
pairdrop     Local file transfer between devices, AirDrop-style
          →  Bestanden tussen toestellen in huis, zoals AirDrop
code         code-server — VS Code in the browser
          →  code-server — VS Code in de browser
tools        IT-Tools — offline developer utilities
          →  IT-Tools — ontwikkelaarsgereedschap, offline
metube       MeTube — yt-dlp web front end
          →  MeTube — webinterface voor yt-dlp
pdf          BentoPDF — merge, split and convert PDFs
          →  BentoPDF — PDF's samenvoegen, splitsen en omzetten
termix       Web SSH client for the homelab
          →  SSH in de browser
torrent      qBittorrent — writes to the NFS share from the Mac mini
          →  qBittorrent — schrijft naar de NFS-share van de Mac mini
neogate      NeoGate — homelab access management (own app)
          →  NeoGate — toegangsbeheer voor het homelab (eigen app)
photos       Immich — photo and video library
          →  Immich — foto- en videobibliotheek
id           Pocket ID — OIDC provider (current instance)
          →  Pocket ID — OIDC-provider (huidige instantie)
prowlarr     Indexer manager feeding Sonarr and Radarr
          →  Indexerbeheer voor Sonarr en Radarr
overseerr    Media requests from friends and family
          →  Aanvragen voor films en series
audiobooks   Audiobookshelf — audiobook and podcast server
          →  Audiobookshelf — luisterboeken en podcasts
sonarr       TV series management
          →  Beheer van series
radarr       Film management
          →  Beheer van films
tinyauth     Auth middleware used by Caddy forward_auth
          →  Auth-middleware achter Caddy's forward_auth
plex         Plex media server — the Mac mini's main job
          →  Plex — de hoofdtaak van de Mac mini
bazarr       Subtitle fetching for Sonarr and Radarr
          →  Ondertitels ophalen voor Sonarr en Radarr
tautulli     Plex usage statistics
          →  Kijkstatistieken van Plex
jackett      Torrent indexer proxy
          →  Proxy voor torrent-indexers
dozzle       Live Docker log viewer
          →  Live Docker-logs bekijken
duplicati    Backups from the Mac mini
          →  Back-ups vanaf de Mac mini
auth         Pocket ID — old instance, to be retired
          →  Pocket ID — oude instantie, wordt uitgefaseerd
wizarr       Plex/Jellyfin invitations for new users
          →  Uitnodigingen voor Plex en Jellyfin
jellyfin     Jellyfin media server
          →  Jellyfin — mediaserver naast Plex
```

Leave the `# TODO: old Pocket ID instance` comment on the `auth` line where it is.

- [ ] **Step 2: Deal with `books`**

`books` is on `macmini:6061` and its `desc` is `"TODO: describe this service"`. Open `https://books.neodata.be` and identify it.

If you can tell what it is, write the Dutch description in the same style.

If you cannot, set it to `"Onbekend — draait op macmini:6061"` and add this to `TODO.md`, under `## Opruimen in de estate`:

```markdown
- [ ] **`books` op macmini:6061 — geen idee wat het is**
      De route bestaat, de `desc` stond op een TODO en is nu "Onbekend".
      *Waarom:* een dienst waarvan niemand weet wat hij doet, wordt bij een
      herbouw niet teruggezet en bij een storing niet gemist. Zoek uit wat er
      luistert, beschrijf het of zet het uit.
```

A page must never render the word `TODO` at a reader.

- [ ] **Step 3: Verify no English or TODO is left**

```bash
cd /Users/rubenclaes/Development/homelab-ansible
grep -n 'desc:' inventory/host_vars/caddy/main.yml | grep -iE 'TODO|the |and |for |with ' || echo "clean"
```

Expected: `clean`.

- [ ] **Step 4: Verify the inventory still parses**

```bash
ansible-inventory --host caddy | python3 -c 'import json,sys; d=json.load(sys.stdin); print(len(d["caddy_sites"]), "services")'
```

Expected: `33 services`.

- [ ] **Step 5: Lint**

```bash
ansible-lint && bin/check-vaulted
```

Expected: both clean.

- [ ] **Step 6: Commit**

```bash
git add inventory/host_vars/caddy/main.yml TODO.md
git commit -m "Write every service description in Dutch

The per-service pages put desc in their subtitle, so a reader meets it
directly rather than inside a table cell. Half the list was English and
one entry still said TODO.

Technical nouns stay English inside Dutch sentences, which is the style
content/index.mdx already uses.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Add `directory.yml` and the assert that guards it

**Files:**
- Create: `inventory/host_vars/caddy/directory.yml`
- Modify: `playbooks/docs.yml` — play-level `vars:` and a new first task

**Interfaces:**
- Produces: `directory_categories` (mapping, insertion-ordered) and `directory_services` (mapping keyed by `caddy_sites[*].name`). Consumed by Task 5.
- Produces: play-level vars `caddy_domain`, `caddy_sites`, `pve_lxcs`, `pve_lxc_defaults`, `docker_stacks_list`, `docker_stacks_wait_for_mounts`, `directory_categories`, `directory_services`. Consumed by Tasks 5 and 6.

- [ ] **Step 1: Create the data file**

`inventory/host_vars/caddy/directory.yml`:

```yaml
---
# Presentatie voor /diensten. Los van caddy_sites, dat over routering gaat en
# niet dikker mag worden van proza.
#
# De volgorde van directory_categories is de volgorde op de pagina: YAML
# bewaart de volgorde van een mapping en to_json geeft die ongewijzigd door.
directory_categories:
  media: { label: "Films, foto's en muziek" }
  thuis: { label: "Thuis" }
  bestanden: { label: "Bestanden" }

# Alleen wat hier staat, verschijnt op /diensten. De sleutel is de `name` uit
# caddy_sites; docs.yml faalt als die niet meer bestaat.
#
# `blurb` is een korte regel, geen zin: de tegel is vier per rij breed.
# `icon` verwijst naar een sleutel in docs-site/components/icons.jsx.
#
# Bewust afwezig:
#   jellyfin - naast plex twee tegels met hetzelfde icoon en dezelfde belofte.
#              Houdt zijn route en zijn technische pagina.
#   home     - Homepage doet hetzelfde werk als deze pagina. Twee voordeuren
#              lopen uiteen en de handonderhouden loopt weg.
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

- [ ] **Step 2: Lift the template vars to play level**

In `playbooks/docs.yml`, the "Build the documentation site" play. Move the `vars:` block off the template task and onto the play, adding the two new ones. The play header becomes:

```yaml
- name: Build the documentation site
  hosts: localhost
  gather_facts: false
  vars:
    docs_site: "{{ playbook_dir }}/../docs-site"
    docs_pages: [services, hosts, containers, stacks]
    # Read straight off the caddy host. Safe here because none of these values
    # contain a template themselves. A var whose VALUE is a hostvars template -
    # caddy_tinyauth_upstream is the one - cannot be read from a localhost play;
    # that is what broke docs.yml and report.yml before.
    caddy_domain: "{{ hostvars['caddy'].caddy_domain }}"
    caddy_sites: "{{ hostvars['caddy'].caddy_sites }}"
    directory_categories: "{{ hostvars['caddy'].directory_categories }}"
    directory_services: "{{ hostvars['caddy'].directory_services }}"
    pve_lxcs: "{{ hostvars['pve01'].pve_lxcs }}"
    pve_lxc_defaults: "{{ hostvars['pve01'].pve_lxc_defaults }}"
    docker_stacks_list: "{{ hostvars['docker'].docker_stacks_list }}"
    docker_stacks_wait_for_mounts: "{{ hostvars['docker'].docker_stacks_wait_for_mounts }}"
  tasks:
```

Then delete the now-duplicated `vars:` block from the "Render the generated reference pages" task, leaving it as module + loop only.

- [ ] **Step 3: Add the assert as the play's first task**

Insert before "Render the generated reference pages":

```yaml
    # A tile that points at a service which no longer exists is worse than no
    # tile: it looks live and 404s. Fail the run instead of rendering it.
    - name: Check the directory against the routes it claims
      ansible.builtin.assert:
        that:
          - directory_services.keys() | difference(caddy_sites | map(attribute='name') | list) | length == 0
          - directory_services.values() | map(attribute='category') | unique
            | difference(directory_categories.keys() | list) | length == 0
        fail_msg: >-
          directory.yml is out of step with caddy_sites.
          Unknown services: {{ directory_services.keys()
            | difference(caddy_sites | map(attribute='name') | list) | join(', ') | default('none', true) }}.
          Unknown categories: {{ directory_services.values() | map(attribute='category') | unique
            | difference(directory_categories.keys() | list) | join(', ') | default('none', true) }}.
        success_msg: "{{ directory_services | length }} tiles, all routed."
```

- [ ] **Step 4: Verify the assert passes**

```bash
cd /Users/rubenclaes/Development/homelab-ansible
ansible-playbook playbooks/docs.yml --start-at-task "Check the directory against the routes it claims" --step
```

Expected: the assert task reports `ok` with `9 tiles, all routed.` Answer `n` at the next prompt to stop before the npm steps.

- [ ] **Step 5: Verify the assert actually fails when it should**

```bash
sed -i '' 's/^  photos:$/  photoos:/' inventory/host_vars/caddy/directory.yml
ansible-playbook playbooks/docs.yml 2>&1 | grep -A3 'out of step'
```

Expected: the run fails, naming `photoos` as an unknown service. Then restore:

```bash
sed -i '' 's/^  photoos:$/  photos:/' inventory/host_vars/caddy/directory.yml
git diff --stat inventory/host_vars/caddy/directory.yml
```

Expected: no diff — the file is back as committed.

- [ ] **Step 6: Lint**

```bash
ansible-lint && ansible-playbook --syntax-check playbooks/docs.yml && bin/check-vaulted
```

Expected: all clean.

- [ ] **Step 7: Commit**

```bash
git add inventory/host_vars/caddy/directory.yml playbooks/docs.yml
git commit -m "Declare the family-facing service directory

Nine services, with a Dutch label, a one-line blurb, an icon and a
category. Kept out of caddy_sites so that list stays about routing and
does not grow prose per entry.

The assert is the point of the split: a key that no longer matches a
route fails the run rather than rendering a tile that 404s.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Build the `ServiceTiles` component

Proved against a hand-written fixture page. Task 5 replaces that page with a generated one.

**Files:**
- Create: `docs-site/components/icons.jsx`
- Create: `docs-site/components/ServiceTiles.jsx`
- Create: `docs-site/components/ServiceTiles.module.css`
- Modify: `docs-site/mdx-components.js`
- Create (temporary): `docs-site/content/diensten.mdx`

**Interfaces:**
- Produces: a global MDX component `<ServiceTiles categories={…} services={…} />`.
  - `categories`: `{ [key: string]: { label: string } }`, rendered in key order.
  - `services`: `Array<{ name, url, label, blurb, icon, category }>`, all strings.
  - A `category` with no matching services renders nothing. An unknown `icon` renders the fallback dot.
  - Task 5 emits exactly these two props from Jinja.

- [ ] **Step 1: Write the icon set**

`docs-site/components/icons.jsx`:

```jsx
// Nextra ships no icon set. These are the only ones /diensten needs; the key
// is what directory.yml puts in `icon`. An unknown key falls back to a dot
// rather than breaking the build, because a missing icon is not worth a
// failed deploy.
const ICONS = {
  camera: (
    <>
      <path d="M3 8a2 2 0 0 1 2-2h2l1.5-2h7L17 6h2a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z" />
      <circle cx="12" cy="12.5" r="3.5" />
    </>
  ),
  film: (
    <>
      <rect x="3" y="4" width="18" height="16" rx="2" />
      <path d="M7 4v16M17 4v16M3 12h18M3 8h4M3 16h4M17 8h4M17 16h4" />
    </>
  ),
  headphones: (
    <>
      <path d="M4 14v-2a8 8 0 0 1 16 0v2" />
      <rect x="2.5" y="13" width="4" height="7" rx="2" />
      <rect x="17.5" y="13" width="4" height="7" rx="2" />
    </>
  ),
  plus: (
    <>
      <circle cx="12" cy="12" r="9" />
      <path d="M12 8v8M8 12h8" />
    </>
  ),
  'user-plus': (
    <>
      <circle cx="9" cy="8" r="3.5" />
      <path d="M2.5 20a6.5 6.5 0 0 1 13 0M18 8v6M15 11h6" />
    </>
  ),
  note: (
    <>
      <path d="M5 3h9l5 5v13a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1z" />
      <path d="M14 3v5h5M8 13h8M8 17h5" />
    </>
  ),
  box: (
    <>
      <path d="M3 8l9-5 9 5v8l-9 5-9-5z" />
      <path d="M3 8l9 5 9-5M12 13v8" />
    </>
  ),
  send: (
    <>
      <path d="M21 3L3 10.5l7 3 3 7z" />
      <path d="M21 3l-11 10.5" />
    </>
  ),
  file: (
    <>
      <path d="M6 2h8l5 5v14a1 1 0 0 1-1 1H6a1 1 0 0 1-1-1V3a1 1 0 0 1 1-1z" />
      <path d="M14 2v5h5M8 14h8M8 18h4" />
    </>
  ),
  fallback: <circle cx="12" cy="12" r="3.5" />
}

export function Icon({ name, className }) {
  return (
    <svg
      className={className}
      viewBox="0 0 24 24"
      aria-hidden="true"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.6"
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      {ICONS[name] ?? ICONS.fallback}
    </svg>
  )
}
```

- [ ] **Step 2: Write the stylesheet**

`docs-site/components/ServiceTiles.module.css`:

```css
/* Neutral rgba rather than theme variables: these read correctly on both the
   light and the dark theme without knowing which one is active. */
.cat {
  margin: 2rem 0 0;
}

.cat:first-child {
  margin-top: 1rem;
}

/* Scoped to .cat AND tagged with the class so it beats nextra-theme-docs'
   own heading typography, which would otherwise render this at h2 size. */
.cat h2.label {
  font-size: 0.6875rem;
  letter-spacing: 0.09em;
  text-transform: uppercase;
  font-weight: 600;
  opacity: 0.55;
  margin: 0 0 0.6rem;
  border: 0;
  padding: 0;
}

.grid {
  display: grid;
  grid-template-columns: repeat(2, 1fr);
  gap: 0.6rem;
  list-style: none;
  padding: 0;
  margin: 0;
}

@media (min-width: 640px) {
  .grid {
    grid-template-columns: repeat(4, 1fr);
  }
}

.tile {
  display: flex;
  flex-direction: column;
  align-items: center;
  text-align: center;
  gap: 0.35rem;
  border: 1px solid rgba(128, 128, 128, 0.28);
  border-radius: 0.7rem;
  background: rgba(128, 128, 128, 0.05);
  padding: 0.9rem 0.6rem 0.8rem;
  text-decoration: none;
  color: inherit;
  transition: border-color 0.15s, background 0.15s;
}

.tile:hover {
  border-color: rgba(128, 128, 128, 0.55);
  background: rgba(128, 128, 128, 0.1);
}

.icon {
  width: 26px;
  height: 26px;
  flex: none;
}

.name {
  font-weight: 600;
  font-size: 0.8125rem;
}

.blurb {
  font-size: 0.72rem;
  line-height: 1.35;
  opacity: 0.62;
}
```

- [ ] **Step 3: Write the component**

`docs-site/components/ServiceTiles.jsx`:

```jsx
import { Icon } from './icons'
import styles from './ServiceTiles.module.css'

// The whole tile is the link, and it points at the service itself - not at a
// documentation page about the service. There is no page in between.
export function ServiceTiles({ categories, services }) {
  return Object.entries(categories).map(([key, category]) => {
    const tiles = services.filter(s => s.category === key)
    if (tiles.length === 0) return null

    return (
      <section className={styles.cat} key={key}>
        <h2 className={styles.label}>{category.label}</h2>
        <ul className={styles.grid}>
          {tiles.map(s => (
            <li key={s.name}>
              <a className={styles.tile} href={s.url}>
                <Icon name={s.icon} className={styles.icon} />
                <span className={styles.name}>{s.label}</span>
                <span className={styles.blurb}>{s.blurb}</span>
              </a>
            </li>
          ))}
        </ul>
      </section>
    )
  })
}
```

- [ ] **Step 4: Register it globally**

`docs-site/mdx-components.js` — replace the whole file:

```js
import { useMDXComponents as getThemeComponents } from 'nextra-theme-docs'
import { ServiceTiles } from './components/ServiceTiles'

const themeComponents = getThemeComponents()

// ServiceTiles is registered here rather than imported per page, because the
// page that uses it is generated by Ansible and an import line in a Jinja
// template is one more thing that can go stale.
export function useMDXComponents(components) {
  return { ...themeComponents, ServiceTiles, ...components }
}
```

- [ ] **Step 5: Write the temporary fixture page**

`docs-site/content/diensten.mdx` — this exact content, including the deliberately unknown icon on the last tile:

```mdx
---
title: Diensten
---

# Diensten

Alles wat hier thuis draait. Klik en je bent er.

<ServiceTiles
  categories={ {"media":{"label":"Films, foto's en muziek"},"thuis":{"label":"Thuis"},"leeg":{"label":"Lege categorie"}} }
  services={ [
    {"name":"photos","url":"https://photos.neodata.be","label":"Foto's","blurb":"Onze foto's en video's","icon":"camera","category":"media"},
    {"name":"plex","url":"https://plex.neodata.be","label":"Films & series","blurb":"Kijken op TV of telefoon","icon":"film","category":"media"},
    {"name":"memos","url":"https://memos.neodata.be","label":"Notities","blurb":"Snelle notities","icon":"note","category":"thuis"},
    {"name":"spullen","url":"https://spullen.neodata.be","label":"Wat ligt waar","blurb":"Met QR-labels","icon":"nietbestaand","category":"thuis"}
  ] } />
```

- [ ] **Step 6: Build and verify**

```bash
cd docs-site && rm -rf out .next && npm run build
test -f out/diensten/index.html && echo "page built"
grep -c 'https://photos.neodata.be' out/diensten/index.html
```

Expected: `page built`, and a count of at least `1`.

- [ ] **Step 7: Verify the four behaviours in the browser**

```bash
cd docs-site && npm run dev
```

Open `http://localhost:3000/diensten`. Confirm all four:

1. Two category headings — `FILMS, FOTO'S EN MUZIEK` and `THUIS` — small and uppercase, **not** at h2 size. If they render large, the CSS specificity guard in Step 2 failed.
2. `Lege categorie` does **not** appear: a category with no services renders nothing.
3. The `Wat ligt waar` tile shows a plain dot, not a broken image — the unknown-icon fallback.
4. Narrow the window below 640px: two tiles per row, nothing clipped, no horizontal scroll.

Stop the dev server.

- [ ] **Step 8: Commit**

```bash
cd /Users/rubenclaes/Development/homelab-ansible
git add docs-site/components docs-site/mdx-components.js docs-site/content/diensten.mdx
git commit -m "Add the ServiceTiles component

Ansible supplies data, React draws it. The whole tile is a link to the
service itself; there is no documentation page in between, so the blurb
has to live on the tile - hover is not available to the people this page
is for.

diensten.mdx is a fixture for now and is replaced by a generated page in
the next commit. It carries a deliberately unknown icon and an empty
category so both fallbacks are exercised.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Generate `/diensten` from the inventory

**Files:**
- Create: `playbooks/templates/docs/diensten.md.j2`
- Modify: `playbooks/docs.yml` — one new task
- Overwrite: `docs-site/content/diensten.mdx` (now generated)

**Interfaces:**
- Consumes: `directory_categories`, `directory_services`, `caddy_domain` (Task 3); `<ServiceTiles>` (Task 4).

- [ ] **Step 1: Write the template**

`playbooks/templates/docs/diensten.md.j2`:

```jinja
---
title: Diensten
---

{# De tegels worden hier platgeslagen tot de vorm die ServiceTiles verwacht:
   een lijst, niet de mapping uit directory.yml, zodat de component niet hoeft
   te weten hoe de inventory eruitziet. #}
{% set tiles = [] -%}
{% for name, d in directory_services.items() -%}
{% set _ = tiles.append({
     'name': name,
     'url': 'https://' ~ name ~ '.' ~ caddy_domain,
     'label': d.label,
     'blurb': d.blurb,
     'icon': d.icon | default('fallback'),
     'category': d.category
   }) -%}
{% endfor -%}

# Diensten

Alles wat hier thuis draait. Klik en je bent er.

<ServiceTiles
  categories={ {{ directory_categories | to_json }} }
  services={ {{ tiles | to_json }} } />

{# Geen callout over hoe deze pagina gegenereerd wordt. Die is niet voor de
   lezer van deze pagina. #}
```

Note the space in `{ {{` — without it Jinja reads `{{{` and the render fails.

- [ ] **Step 2: Add the render task**

In `playbooks/docs.yml`, directly after "Render the generated reference pages":

```yaml
    - name: Render the family-facing directory
      ansible.builtin.template:
        src: docs/diensten.md.j2
        dest: "{{ docs_site }}/content/diensten.mdx"
        mode: "0644"
```

- [ ] **Step 3: Render and inspect the diff**

```bash
cd /Users/rubenclaes/Development/homelab-ansible
ansible-playbook playbooks/docs.yml --start-at-task "Check the directory against the routes it claims" --step
```

Step through the two render tasks, then answer `n` to stop before `npm ci`. Then:

```bash
git diff docs-site/content/diensten.mdx
```

Expected: the fixture is replaced by nine tiles across three categories, every `url` reading `https://<name>.neodata.be`, and no `nietbestaand` icon left.

- [ ] **Step 4: Build and verify all nine tiles**

```bash
cd docs-site && rm -rf out .next && npm run build
for s in photos plex audiobooks overseerr wizarr spullen memos pairdrop pdf; do
  grep -q "https://$s.neodata.be" out/diensten/index.html || echo "MISSING: $s"
done; echo "checked"
```

Expected: `checked` with no `MISSING` lines.

- [ ] **Step 5: Verify the two exclusions**

```bash
grep -c 'jellyfin.neodata.be\|home.neodata.be' out/diensten/index.html || echo "0 - correctly absent"
```

Expected: `0 - correctly absent`. Jellyfin and Homepage are deliberately not on the family grid.

- [ ] **Step 6: Lint**

```bash
cd /Users/rubenclaes/Development/homelab-ansible
ansible-lint && ansible-playbook --syntax-check playbooks/docs.yml
```

Expected: both clean.

- [ ] **Step 7: Commit**

```bash
git add playbooks/templates/docs/diensten.md.j2 playbooks/docs.yml docs-site/content/diensten.mdx
git commit -m "Generate /diensten from the inventory

The fixture becomes a rendered page. directory.yml is now the only place
a tile is declared, which is what makes the assert in docs.yml worth
having.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Generate one technical page per service

**Files:**
- Create: `playbooks/templates/docs/service.md.j2`
- Create: `playbooks/templates/docs/services-meta.js.j2`
- Move: `docs-site/content/technisch/services.mdx` → `docs-site/content/technisch/services/index.mdx`
- Modify: `playbooks/docs.yml` — `docs_pages`, plus three new tasks
- Modify: `playbooks/templates/docs/services.md.j2` — render target changes

**Interfaces:**
- Consumes: play-level `caddy_sites`, `caddy_domain` (Task 3); `desc` in Dutch (Task 2); the `/technisch/` prefix (Task 1).
- Produces: 33 pages at `/technisch/services/<name>/`.

- [ ] **Step 1: Restructure the services page into a folder**

```bash
cd /Users/rubenclaes/Development/homelab-ansible/docs-site/content/technisch
mkdir -p services.tmp
git mv services.mdx services.tmp/index.mdx
git mv services.tmp services
```

- [ ] **Step 2: Drop `services` from the shared loop**

In `playbooks/docs.yml`:

```yaml
    docs_pages: [hosts, containers, stacks]
```

That loop writes to `content/technisch/<page>.mdx`, which is no longer where
the services page lives. It now sits inside the directory Step 3 wipes, so it
has to be rendered after the wipe rather than before it.

- [ ] **Step 3: Add the four tasks that build the services directory**

In `playbooks/docs.yml`, directly after "Render the family-facing directory".
Order matters: the wipe comes first, and everything that lives in the
directory is rendered after it.

```yaml
    # Wiped and rebuilt rather than overwritten: a service deleted from
    # caddy_sites must not leave its page behind, and a stale page looks live.
    # Same absent -> directory swap this playbook already uses when publishing.
    - name: Clear the per-service pages
      ansible.builtin.file:
        path: "{{ docs_site }}/content/technisch/services"
        state: "{{ item }}"
        mode: "0755"
      loop: [absent, directory]

    - name: Render the services index
      ansible.builtin.template:
        src: docs/services.md.j2
        dest: "{{ docs_site }}/content/technisch/services/index.mdx"
        mode: "0644"

    - name: Render one page per service
      ansible.builtin.template:
        src: docs/service.md.j2
        dest: "{{ docs_site }}/content/technisch/services/{{ item.name }}.mdx"
        mode: "0644"
      loop: "{{ caddy_sites }}"
      loop_control:
        label: "{{ item.name }}"

    - name: Render the per-service navigation
      ansible.builtin.template:
        src: docs/services-meta.js.j2
        dest: "{{ docs_site }}/content/technisch/services/_meta.js"
        mode: "0644"
```

- [ ] **Step 4: Write the per-service template**

`playbooks/templates/docs/service.md.j2`:

```jinja
{% set s = item -%}
{% set h = hostvars[s.host] if (s.host is defined and s.host in hostvars) else {} -%}
{# Het echte upstream-adres, niet wat er in de config staat. hostvars direct
   uitlezen mag vanuit de localhost-play; hosts.md.j2 doet het al. Een site met
   `upstream:` heeft geen inventory-host, vandaar de default. -#}
{% set up = s.upstream | default((h.ansible_host | default('?')) ~ ':' ~ (s.port | default('?'))) -%}
{% set flags = [] -%}
{% if s.https | default(false) %}{% set _ = flags.append('TLS-upstream') %}{% endif -%}
{% if s.auth | default(false) %}{% set _ = flags.append('achter tinyauth') %}{% endif -%}
{% if s.forwarded | default(false) %}{% set _ = flags.append('forwarded headers') %}{% endif -%}
{% if s.host_header | default(false) %}{% set _ = flags.append('host-header doorgegeven') %}{% endif -%}
---
title: {{ s.name }}
---

# {{ s.name }}

{{ s.desc | default('Niet gedocumenteerd.') }}

| Eigenschap | Waarde |
| --- | --- |
| URL | [{{ s.name }}.{{ caddy_domain }}](https://{{ s.name }}.{{ caddy_domain }}) |
| Upstream | `{{ up }}` |
| Host | {{ ('[' ~ s.host ~ '](/technisch/hosts/)') if s.host is defined else '— (vaste upstream)' }} |
| Poort | {{ ('`' ~ s.port ~ '`') if s.port is defined else '—' }} |
| Groepen | {{ (h.group_names | sort | join(', ')) if h.group_names is defined else '—' }} |
| Eigenschappen | {{ flags | join(' · ') if flags else '—' }} |

Gegenereerd uit `caddy_sites` in `inventory/host_vars/caddy/main.yml`.
```

There is deliberately no link to a Docker stack: `caddy_sites` does not record which stack a container belongs to, and `docker_stacks_list` is incomplete (`media-stack` is missing — see `TODO.md`). The host page is the bridge.

- [ ] **Step 5: Write the navigation template**

`playbooks/templates/docs/services-meta.js.j2`:

```jinja
// Geschreven door playbooks/docs.yml. Niet bewerken.
export default {
  index: 'Alle services',
{% for s in caddy_sites | sort(attribute='name') %}
  '{{ s.name }}': '{{ s.name }}',
{%- endfor %}
}
```

- [ ] **Step 6: Render and count**

```bash
cd /Users/rubenclaes/Development/homelab-ansible
ansible-playbook playbooks/docs.yml --start-at-task "Check the directory against the routes it claims" --step
```

Step through every render task, answer `n` before `npm ci`. Then:

```bash
ls docs-site/content/technisch/services/*.mdx | wc -l
```

Expected: `34` — the 33 services plus `index.mdx`.

- [ ] **Step 7: Spot-check three pages by hand**

```bash
cat docs-site/content/technisch/services/photos.mdx
cat docs-site/content/technisch/services/wizarr.mdx
cat docs-site/content/technisch/services/portainer.mdx
```

Expected:
- `photos` — Upstream is a real `192.168.0.x:2283`, not `?:2283`. Host links to `/technisch/hosts/`. Eigenschappen is `—`.
- `wizarr` — Eigenschappen reads `achter tinyauth`.
- `portainer` — Eigenschappen reads `TLS-upstream`.

If any upstream reads `?`, the dynamic inventory did not resolve that host — re-run with the homelab reachable before continuing.

- [ ] **Step 8: Build and verify all 33 pages exist**

```bash
cd docs-site && rm -rf out .next && npm run build
ls -d out/technisch/services/*/ | wc -l
```

Expected: `33`.

- [ ] **Step 9: Verify the sidebar and a page in the browser**

```bash
cd docs-site && npm run dev
```

Open `http://localhost:3000/technisch/services/photos`. Confirm:

1. The sidebar has `Technisch` → `Services` → `Alle services` plus the 33 names.
2. The page shows `photos` as the heading, the Dutch description beneath it, and the six-row table.
3. The URL link in the table opens `https://photos.neodata.be`.

Stop the dev server.

- [ ] **Step 10: Lint**

```bash
cd /Users/rubenclaes/Development/homelab-ansible
ansible-lint && ansible-playbook --syntax-check playbooks/docs.yml
```

Expected: both clean.

- [ ] **Step 11: Commit**

```bash
git add -A docs-site/content/technisch playbooks/templates/docs playbooks/docs.yml
git commit -m "Give every service a page of its own

33 pages, one per entry in caddy_sites. A service now has an address you
can link to, which a row in a table never had.

The directory is wiped and rebuilt on every run. Overwriting would leave
a deleted service's page behind, and a stale page looks live.

No link to a Docker stack: caddy_sites does not record which stack a
container belongs to and docker_stacks_list is incomplete, so that link
would be wrong for photos - the one service people would click.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: Cut the prose back

**Files:**
- Modify: `docs-site/content/index.mdx`
- Modify: `playbooks/templates/docs/hosts.md.j2`
- Modify: `playbooks/templates/docs/services.md.j2`
- Modify: `playbooks/templates/docs/containers.md.j2`
- Modify: `playbooks/templates/docs/stacks.md.j2`
- Modify: `README.md` (only if a convention is missing there)

- [ ] **Step 1: Rewrite the landing page**

`docs-site/content/index.mdx` — replace the whole file:

```mdx
---
title: Overzicht
---

import { Cards } from 'nextra/components'

# neodata.homelab

Eén Proxmox-host, een handvol LXC-guests, een Docker-host en twee Macs,
geconvergeerd door [homelab-ansible](https://github.com/rubenclaes/homelab-ansible).

<Cards>
  <Cards.Card title="Diensten — wat er draait, en waar je het vindt" href="/diensten/" arrow />
  <Cards.Card title="Technisch — hosts, containers, stacks, runbooks" href="/technisch/hosts/" arrow />
</Cards>

## Waarom het zo staat

De inventory wordt niet met de hand bijgehouden. Proxmox is de bron: maak een
guest aan en hij staat er de volgende run in, met het adres dat hij op dat
moment echt heeft.

Secrets zijn gesplitst op blast radius over twee vault-identiteiten. `infra`
bevat de credentials die de estate besturen — Proxmox, Cloudflare, PBS.
`stacks` bevat applicatielogins. Elke helft roteert los van de andere.

Pagina's onder Technisch worden gegenereerd uit de inventory en kunnen dus niet
uit de pas lopen. Runbooks zijn met de hand geschreven: daar staat de redenering
die code niet uitdrukt.
```

What went: the paragraph naming each role (the hosts page shows that), the four cards (now two), and `## Conventies` — handled in the next step.

- [ ] **Step 2: Make sure the conventions survive in the README**

The three bullets removed from `index.mdx` were:

```
- Elke Linux-host wordt benaderd als het `ansible`-serviceaccount, alleen met
  key, met sudo zonder wachtwoord. Geen enkele host accepteert een SSH-wachtwoord.
- `playbooks/site.yml` convergeert alles en mag op elk moment draaien. Wat
  provisioneert of herstart valt er bewust buiten.
- Niets wordt met de hand geconfigureerd. Was het de moeite om twee keer te
  doen, dan zit het in een rol.
```

Check each against `README.md`:

```bash
cd /Users/rubenclaes/Development/homelab-ansible
grep -n 'serviceaccount' README.md
grep -n 'site.yml' README.md
grep -n 'twee keer' README.md
```

For any that returns nothing, add that bullet to `README.md` under the section that covers conventions. A convention that exists in neither place is the one thing this step must not produce.

- [ ] **Step 3: Trim the host page's trailing prose**

In `playbooks/templates/docs/hosts.md.j2`, delete this paragraph entirely:

```
Elke Linux-host wordt benaderd als het `ansible`-serviceaccount, alleen met
key, en escaleert met sudo zonder wachtwoord. `mbp` is de control node en
beheert zichzelf.
```

Keep the paragraph about live addresses — it explains why the column is right while two containers run DHCP:

```
Adressen komen live uit Proxmox: het runtime-adres van de guest, niet wat er
in zijn config staat. Twee containers draaien DHCP en kloppen daardoor toch.
```

- [ ] **Step 4: Trim the services index**

In `playbooks/templates/docs/services.md.j2`, replace the two-sentence paragraph after the callout:

```
Elke service draait op `https://<naam>.{{ caddy_domain }}`, via Caddy.
Upstream-adressen komen uit `ansible_host` van de host zelf, dus een host
verhuizen past elke route aan die ernaar wijst.
```

with one line, now that each service has a page of its own:

```
Elke service draait op `https://<naam>.{{ caddy_domain }}`. Klik de naam voor
het upstream-adres en de instellingen.
```

Then make the service name in the table link to its page instead of to the live site. Change the row template to:

```jinja
| [{{ s.name }}](/technisch/services/{{ s.name }}/) | `{{ s.port | default(s.upstream) }}` | {{ s.desc | default('_niet gedocumenteerd_') }} | {% if s.https | default(false) %}TLS-upstream. {% endif %}{% if s.auth | default(false) %}Achter tinyauth. {% endif %}{% if s.forwarded | default(false) %}Forwarded headers. {% endif %}{% if s.host_header | default(false) %}Host-header doorgegeven. {% endif %} |
```

- [ ] **Step 5: Trim the containers page**

In `playbooks/templates/docs/containers.md.j2`, replace these two paragraphs:

```
Deze definities dienen om een verdwenen container **opnieuw te maken**.
`playbooks/proxmox-lxcs.yml` raakt een bestaande container nooit aan.

De adressen hieronder staan letterlijk in de inventory, niet afgeleid: een
container die nog niet bestaat staat ook niet in de Proxmox-inventory, dus
valt er niets af te leiden.
```

with one:

```
Om een verdwenen container **opnieuw te maken**; een bestaande wordt nooit
aangeraakt. De adressen staan letterlijk in de inventory omdat een container
die nog niet bestaat niets heeft om uit af te leiden.
```

- [ ] **Step 6: Trim the stacks page**

In `playbooks/templates/docs/stacks.md.j2`, replace:

```
Compose-bestanden staan in [rubenclaes/containers](https://github.com/rubenclaes/containers)
en worden met een read-only deploy key op `docker` gezet. De `.env` van elke
stack staat versleuteld onder de vault-identiteit `stacks` en wordt pas bij
het deployen weggeschreven.
```

with:

```
Compose-bestanden komen uit [rubenclaes/containers](https://github.com/rubenclaes/containers)
via een read-only deploy key. Elke `.env` staat versleuteld onder de
vault-identiteit `stacks` en wordt pas bij het deployen weggeschreven.
```

- [ ] **Step 7: Re-render and check the word count actually dropped**

```bash
cd /Users/rubenclaes/Development/homelab-ansible
ansible-playbook playbooks/docs.yml --start-at-task "Check the directory against the routes it claims" --step
```

Answer `n` before `npm ci`, then:

```bash
wc -w docs-site/content/index.mdx docs-site/content/technisch/hosts.mdx
```

Expected: `index.mdx` under 200 words (it was around 450).

- [ ] **Step 8: Build and check the links resolve**

```bash
cd docs-site && rm -rf out .next && npm run build
grep -o 'href="/diensten/"' out/index.html | head -1
grep -o 'href="/technisch/services/photos/"' out/technisch/services/index.html | head -1
```

Expected: both print a match. The second proves the services table now links to the per-service pages.

- [ ] **Step 9: Lint**

```bash
cd /Users/rubenclaes/Development/homelab-ansible
ansible-lint && ansible-playbook --syntax-check playbooks/docs.yml
```

Expected: both clean.

- [ ] **Step 10: Commit**

```bash
git add docs-site/content playbooks/templates/docs README.md
git commit -m "Cut the prose back to what a table cannot say

The landing page restated what the hosts page already shows. What stays
is the reasoning: why the inventory is live, and why the vault is split
on blast radius.

The services table now links each name to its own page rather than to
the live site, so the column of ports stops being the only way in.

Runbooks are untouched. Those are procedures; they need their words.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: Full run and publish

Nothing new is written here. This proves the whole playbook runs end to end and that what lands on `caddy` is what was built.

- [ ] **Step 1: Run the playbook from the top**

```bash
cd /Users/rubenclaes/Development/homelab-ansible
ansible-playbook playbooks/docs.yml
```

Expected: every play succeeds, including `npm ci`, `npm run build`, the tar, and the swap on `caddy`.

- [ ] **Step 2: Confirm the working tree is clean after the run**

```bash
git status --short docs-site/content
```

Expected: no output. A second render of committed generated pages must produce no diff — if it does, the templates are not deterministic and that needs fixing before this is done.

- [ ] **Step 3: Check what the live site actually serves**

```bash
for p in / /diensten/ /technisch/hosts/ /technisch/services/ /technisch/services/photos/ /technisch/runbooks/updates/; do
  printf '%-40s %s\n' "$p" "$(curl -s -o /dev/null -w '%{http_code}' "https://docs.neodata.be$p")"
done
```

Expected: `200` for all six. Run this from the home network or Tailscale — from anywhere else the Caddyfile returns `403` by design.

- [ ] **Step 4: Confirm the old URLs are gone from the server**

```bash
curl -s -o /dev/null -w '%{http_code}\n' https://docs.neodata.be/reference/hosts/
```

Expected: `404`. The publish step swaps a fresh directory in, so the old tree must not survive.

- [ ] **Step 5: Check search picked up the new pages**

Open `https://docs.neodata.be` and search for `photos`. Expected: the per-service page appears. Pagefind indexes `.next/server/app` after the build, so a missing result means the postbuild step ran before those pages existed.

- [ ] **Step 6: Open it on a phone**

Open `https://docs.neodata.be/diensten/` on a phone on the home wifi. Expected: two tiles per row, every blurb readable without zooming, no horizontal scroll. Tapping `Foto's` opens Immich.

- [ ] **Step 7: Commit anything outstanding and push the branch**

```bash
git status --short
git push -u origin docs-site-two-audiences
```

Expected: a clean tree before pushing.

---

## Self-review notes

Checked against the spec, section by section:

- **Informatiearchitectuur** → Task 1 (move, `_meta.js`), Task 6 (services folder).
- **`directory.yml`** → Task 3, with the nine tiles and both exclusions.
- **`desc` wordt Nederlands** → Task 2, 30 rewrites listed verbatim, plus the `books` fallback.
- **Validatie** → Task 3 Steps 3–5, including proving the assert fails.
- **Sjablonen** → Tasks 5 and 6. `services-meta.js.j2` is generated; `content/technisch/_meta.js` is hand-written in Task 1.
- **Upstream in het sjabloon** → Task 6 Step 4, with the `hostvars` caveat carried over.
- **Iconen** → Task 4, fallback exercised by the fixture in Step 5 and checked in Step 7.
- **Paginaontwerp** → Task 4 (tiles), Task 6 (property table).
- **Het inkorten** → Task 7, page by page. Runbooks untouched.
- **Verificatie** → the spec's six checks map to Task 3 Step 5, Task 6 Step 8, Task 8 Steps 1–6.

Names used consistently across tasks: `ServiceTiles`, `Icon`, `directory_categories`, `directory_services`, `tiles`, `docs_pages`. The `services` key in `content/technisch/_meta.js` is written in Task 1 against a file and reused in Task 6 against a folder — Nextra resolves both, and no edit is needed between them.
