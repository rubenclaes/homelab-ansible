# docs-site: een Homelab-deel naast Technisch

Datum: 2026-09-23
Status: ontwerp

## Probleem

`docs.neodata.be` beschrijft alleen wat Ansible doet. Wat daarbuiten gebeurt —
een toestel in UniFi zetten, iemand een WireGuard-profiel geven, iemand Immich
geven via NeoGate, toegang weer intrekken, een site deblokkeren — staat
nergens, of verspreid over runbooks die per tool georganiseerd zijn.

## Doel

Een deel **Homelab** met pagina's per situatie ("ik wil…"), niet per tool.
Voor de beheerder alleen. Alleen wat vandaag werkt; wat nog gebouwd moet
worden gaat naar `TODO.md`, niet in de docs.

Snel vinden is het criterium: elke pagina is vanaf Overzicht in twee klikken
bereikbaar.

## Beslissingen

| | |
| --- | --- |
| Publiek | Alleen de beheerder |
| Inhoud | Alleen wat vandaag werkt |
| Indeling | Op onderwerp: Toestellen, Toegang, Internet en DNS |
| Instap | Eén startpagina `Homelab` met één "Ik wil…"-tabel; geen tussenpagina per groep |
| Technisch | Ongewijzigd; Homelab linkt ernaar in plaats van te herhalen |
| Stijl | Runbook-stijl: stappen, klikwerk als tabel scherm · wat · waarom, het waarom onderaan |
| Hernoemen | "Welk geval?" in Nieuwe machine en Dienst toevoegen wordt "Start hier" |

## Structuur

```
content/homelab/
  index.mdx                     Start hier: één tabel "Ik wil… → pagina"
  toestellen/
    nieuw-toestel.mdx           UniFi: naam + vast adres
    toestel-kwijt.mdx           wat je intrekt: WireGuard-profiel, Tailscale-machine, NeoGate
  toegang/
    van-buitenaf.mdx            WireGuard of Tailscale: wanneer welke
    diensten-geven.mdx          NeoGate: uitnodigen, diensten aanvinken
    vpn-geven.mdx               WireGuard-profiel in UniFi, of Tailscale via NeoGate
    gast-op-bezoek.mdx          gewone wifi; wat meteen werkt, wat via NeoGate
    toegang-afnemen.mdx         NeoGate + Tailscale-console + UniFi-profiel
  internet-en-dns/
    blokkeren.mdx               snel in AdGuard, blijvend via de inventory
```

`content/_meta.js` krijgt `homelab: 'Homelab'` tussen `index` en `technisch`.
De Overzicht-pagina krijgt de Homelab-pagina's in zijn "Ik zoek…"-tabel.

## Feiten waar de pagina's op steunen

- Toegang tot diensten gaat altijd via NeoGate (`neogate.neodata.be`, pagina
  "Gezin"). Plugins: Plex, Jellyfin, Immich, Tailscale, Seerr, Grimmory.
- NeoGate trekt bij Tailscale alleen de uitnodiging in. Een aanvaarde
  uitnodiging blijft een lid van de tailnet; "Toegang afnemen" heeft daarom
  een stap in de Tailscale-console.
- WireGuard "Neodata VPN" staat in UniFi: `vpn.neodata.be:51820`,
  `10.10.30.0/24`, DNS `192.168.0.29`. Anderen krijgen soms een profiel.
- Tailscale komt niet op het LAN (`--accept-routes` uit); van buitenaf naar
  `192.168.0.x` is WireGuard.
- Er is geen gastennetwerk. Gasten komen op het gewone wifi.
- AdGuard-blocklists staan in `inventory/host_vars/adguard/main.yml`; de rol
  haalt lijsten weg die daar niet in staan. Per-client instellingen blijven in
  het AdGuard-scherm.
- UniFi wordt met de hand beheerd; de UniFi-rol is bewust weggehaald
  (`2026-09-22-devices-en-dns-design.md`).

## Buiten scope → `TODO.md`

- Een apart gastennetwerk
- NeoGate die Tailscale-leden echt verwijdert, niet alleen de uitnodiging
- Meldingen via ntfy (`2026-09-23-ntfy-oci-design.md`)
- Apple MDM, en daarmee "Mac of iPhone klaarzetten"

## Controle

- `next build` in `docs-site` slaagt
- Elke interne link en elk anker bestaat in de gebouwde `out/`
- Elke Homelab-pagina staat in de tabel op `homelab/index.mdx` en Overzicht
  linkt naar die pagina
