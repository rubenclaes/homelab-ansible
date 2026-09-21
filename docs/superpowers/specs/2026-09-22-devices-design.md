# Toestellen: een lijst voor alles zonder SSH

Datum: 2026-09-22
Status: deel 1 van 4 (zie "Buiten scope")

## Probleem

De inventory kent tien machines en beheert ze allemaal. Alles daarbuiten
bestaat niet: geen enkele telefoon, tablet, TV, printer of console komt voor in
deze repo.

Dat is begrijpelijk — Ansible kan er niet op inloggen, dus viel er niets te
beheren. Maar het gevolg is dat er nergens staat wat er in huis hangt, van wie
het is, of welk adres het hoort te hebben. Bij een router die opnieuw
geconfigureerd moet worden is die kennis weg.

## Doel

Eén lijst met wat er in huis staat en geen SSH heeft, plus een pagina die hem
toont. Niet meer dan dat.

De waarde zit niet in deze twee dingen, maar in wat erop kan leunen: DNS-namen,
Tailscale-sleutels en configuratieprofielen komen straks alle drie uit dezelfde
lijst. Daarom is dit stuk klein en het datamodel het belangrijkste eraan.

## Beslissingen

| | |
| --- | --- |
| Rol van de lijst | Bron van waarheid, niet een register achteraf |
| Sleutel | Het MAC-adres, niet het IP |
| Afbakening | Alleen wat geen SSH heeft |
| Plaats | `inventory/group_vars/all/devices.yml`, gewone lijst |
| Pagina | Gegenereerd, onder Technisch |
| Taal | Comments Engels (zoals `lxcs.yml` en `vms.yml`); pagina Nederlands |

## Afbakening

Machines met SSH — de acht guests, `pve01`, de twee Macs — staan al in de
inventory en blijven daar. Eén feit op één plek: hun adres komt live uit
Proxmox en mag niet op een tweede plaats overgeschreven worden.

`devices.yml` gaat dus uitsluitend over toestellen waar Ansible niet op kan
inloggen.

## Datamodel

`inventory/group_vars/all/devices.yml`:

```yaml
---
# Everything in the house that Ansible cannot log into: phones, tablets, the
# TV, the printer, the parents' PC. Machines with SSH live in the inventory
# and stay there - one fact, one place.
#
# The MAC is the identifier, not the IP. Same reason pve_vms records them: a
# new MAC means a new DHCP lease. The router at 192.168.0.1 hands out the
# addresses; `ip` here is the reservation set there, written down so a rebuilt
# router can be put back the way it was.
#
# A device with no reservation simply has no `ip`. That is normal for a guest's
# phone and is not a gap.
devices:
  iphone-ruben:
    owner: Ruben
    type: phone
    mac: "aa:bb:cc:dd:ee:ff"
    ip: 192.168.0.60

  tv-woonkamer:
    owner: gedeeld
    type: tv
    mac: "11:22:33:44:55:66"
    ip: 192.168.0.70
    note: "Chromecast ingebouwd; praat met Plex"

  printer:
    owner: gedeeld
    type: printer
    mac: "77:88:99:aa:bb:cc"
```

De sleutel is een korte naam zonder spaties, die straks ook de bestandsnaam van
een profiel wordt.

| Veld | Verplicht | Waarvoor |
| --- | --- | --- |
| `owner` | ja | Wie het toestel heeft. Vrije tekst; `gedeeld` voor huisdingen |
| `type` | ja | Groepeert de pagina, en bepaalt straks wie een profiel krijgt |
| `mac` | ja | De identiteit. Kleine letters, dubbele punten |
| `ip` | nee | De reservering in de router. Afwezig = geen reservering |
| `note` | nee | Wat je over een half jaar vergeten bent |

`type` is vrije tekst, geen vaste lijst. Een enum zou nu al bepalen welke
soorten toestellen mogen bestaan, en daar is geen reden voor.

### Wat er bewust niet in zit

Geen `tailnet:`, geen `dns:`, geen `profile:`. Die horen bij de latere stukken.
Een vlag die nu niets doet, durft over een half jaar niemand meer weg te halen.

## Validatie

`docs.yml` krijgt een `assert`, naast die voor `directory_services`:

- elk `mac` voldoet aan `^([0-9a-f]{2}:){5}[0-9a-f]{2}$` — kleine letters,
  zodat twee schrijfwijzen niet als twee toestellen tellen
- geen twee toestellen delen een `mac`
- geen twee toestellen delen een `ip`
- **geen `ip` botst met de `ansible_host` van een machine in de inventory**

Die laatste is de reden dat deze assert bestaat. Reserveer je per ongeluk
`192.168.0.25` voor de printer, dan is dat het adres van `caddy`, en dat merk je
normaal pas als de DNS eruit ligt. Nu faalt de run ervoor.

De controle leest `hostvars` van alle inventory-hosts. Dat mag vanuit de
localhost-play — `hosts.md.j2` doet het al — zolang de variabele zelf geen
template bevat.

## Generatie

| Sjabloon | Rendert naar |
| --- | --- |
| `playbooks/templates/docs/toestellen.md.j2` | `docs-site/content/technisch/toestellen.mdx` |

`devices` staat in `group_vars/all` en is dus gewoon beschikbaar in de
localhost-play; nagemeten met `ansible localhost -m debug`. Anders dan
`caddy_sites` hoeft het niet via `hostvars['caddy']` gelezen te worden, en komt
er dus ook geen play-variabele bij.

`content/technisch/_meta.js` is met de hand geschreven en krijgt er één sleutel
bij: `toestellen: 'Toestellen'`, na `stacks` en vóór `services`.

## Paginaontwerp

`/technisch/toestellen/`. Onder Technisch, niet onder Diensten — MAC-adressen
zijn geen informatie voor het gezin.

Per `type` een kop, daaronder een tabel, net zoals `services.md.j2` per host
groepeert. Kolommen: Toestel, Van wie, MAC, Adres. Een `note` komt als regel
onder de tabel van dat type, niet als vijfde kolom — dan blijft de tabel leesbaar
op een telefoon.

Een toestel zonder `ip` krijgt `—`.

Onderaan twee regels: waar de pagina vandaan komt, en dat machines mét SSH onder
**Hosts** staan. Zonder die tweede regel zoekt iemand hier naar `macmini`.

Types verschijnen alfabetisch. Dat is wat Jinja's `groupby` sowieso doet — het
sorteert op het groepeerveld — en het is deterministisch, wat de controle op
"tweede run, geen diff" nodig heeft. Een eigen volgorde afdwingen zou een tweede
lijst betekenen die met de eerste uit de pas kan lopen.

## Buiten scope

De drie stukken die hierop leunen, elk met een eigen spec:

2. **DNS-namen in AdGuard.** Via de REST API, en uitsluitend de rewrite-lijst.
   `roles/adguard` zegt nu expliciet dat het `AdGuardHome.yaml` niet beheert,
   omdat dat bestand het adminwachtwoord, de upstreams en alle filterregels
   bevat en via het webscherm bewerkt wordt. Die keuze blijft staan: de API
   raakt alleen de rewrites aan, dus er ontstaat geen gevecht om eigenaarschap.
3. **Tailscale pre-auth keys** per toestel. De rol installeert nu wel maar
   authenticeert niet.
4. **`.mobileconfig`-profielen** genereren en serveren.

Ook buiten scope: het invullen van de lijst zelf. De spec levert de structuur en
drie voorbeeldregels; de echte MAC-adressen komen van de eigenaar. Ze later uit
de ARP-tabel van een host halen is een aparte stap, geen onderdeel hiervan.

En: de router wordt niet aangeraakt. Reserveringen zet je daar met de hand. De
lijst legt vast wat er hoort te staan, hij dwingt het niet af.

## Risico's

- **De lijst kan uit de pas lopen met de router.** Niets controleert of een
  reservering echt bestaat. Dat is bewust — de router heeft geen API die deze
  repo gebruikt — maar het betekent dat `ip` een bedoeling is, geen meting. De
  comment in het bestand zegt dat met zoveel woorden.
- **Een handmatig ingevuld MAC-adres kan fout zijn.** De assert controleert de
  vorm, niet of het toestel bestaat. Een typefout levert een regel op die nooit
  ergens mee overeenkomt; bij stuk 2 en 3 wordt dat pas zichtbaar.
- **De pagina groeit niet mee met het huis.** Iemand moet hem bijhouden. Dat is
  de prijs van een lijst over dingen waar je niet op kan inloggen.

## Verificatie

1. `ansible-lint` en `ansible-playbook --syntax-check playbooks/docs.yml` schoon.
2. `ansible localhost -m debug -a var=devices` toont de lijst.
3. De assert faalt aantoonbaar: zet tijdelijk een `ip` op het adres van `caddy`
   en bevestig dat de run stopt vóór het renderen, met een bruikbare melding.
4. De assert faalt op een dubbel MAC-adres en op een MAC in hoofdletters.
5. `docs.yml` draait door; `docs-site/out/technisch/toestellen/index.html`
   bestaat en toont de drie voorbeeldtoestellen, gegroepeerd per type.
6. Een tweede run laat geen diff achter in `docs-site/content/`.
7. Op telefoonbreedte valt de tabel niet buiten beeld.
