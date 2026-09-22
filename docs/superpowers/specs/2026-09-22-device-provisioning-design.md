# Toestellen provisionen: van register naar gewenste toestand

Datum: 2026-09-22
Status: vervangt de rol die `devices.yml` in deel 1 kreeg

## Probleem

`devices.yml` was een lijst: het schreef op wat er in huis stond en welk adres
het hoorde te hebben. De spec van deel 1 noemde dat zelf een risico, `ip` was
"een bedoeling, geen meting", en niets dwong het af.

Een lijst die niets doet, is werk dat je erin stopt en er niet uit krijgt. En
het was ook niet nodig: er zijn twee systemen in huis die een toestel zonder
SSH wél kunnen configureren, en allebei hebben ze een API.

## Doel

Van `devices.yml` de gewenste toestand van een toestel maken, en die
doorzetten. Eén commit en één run moeten volstaan om een toestel dat je nog
niet hebt volledig in te richten.

## Beslissingen

| | |
| --- | --- |
| UniFi | Maakt het client-record op MAC, zet naam, bandbreedtegroep en reservering |
| AdGuard | Maakt de DNS-naam (deel 2) en een client met filterbeleid |
| Aansturing | `playbooks/devices.yml`, bewust buiten `site.yml` |
| Verwijderen | Geen van beide rollen verwijdert ooit iets |
| Credentials | Lokaal UniFi-account, geen cloudlogin: die vraagt een tweede factor |

## De sleutel is dat UniFi vooruit kan werken

Het endpoint dat dit mogelijk maakt is `POST .../group/user`: het maakt een
client aan op een MAC-adres dat nog nooit verbinding heeft gemaakt. Daarna zet
`PUT .../rest/user/<id>` er een naam, een groep en een vaste reservering op.

Daardoor is de volgorde omgekeerd ten opzichte van wat een register doet. Je
schrijft het toestel eerst op, draait het playbook, en pas daarna gaat het voor
het eerst aan. Op dat moment gelden de naam, het adres, de bandbreedtelimiet,
de DNS-naam en het filterbeleid al.

## Wat er per toestel te declareren valt

Boven op `owner`, `type`, `mac` en `ip`:

| Veld | Doet |
| --- | --- |
| `group` | Bandbreedtegroep op de gateway, bij naam |
| `dns.filtering` | Adblocking aan of uit voor dit toestel |
| `dns.safebrowsing`, `dns.parental` | AdGuards eigen schakelaars |
| `dns.safe_search` | Forceert safe search op alle zoekmachines die AdGuard kent |
| `dns.blocked_services` | Dienst-ID's zoals AdGuard ze spelt |
| `dns.allowed` | Het venster waarin die diensten juist *niet* geblokkeerd zijn |
| `dns.upstreams` | Andere resolver voor dit toestel |

Zonder `dns`-blok krijgt een toestel nog steeds een client, met
`use_global_settings`. Dat is geen lege huls: de client bestaat om het
querylog leesbaar te maken, en dat is op zichzelf de moeite.

### `allowed` is een toestemming, geen verbod

AdGuard slaat per client een schema van *inactiviteit* op: de vensters waarin
de geblokkeerde diensten niet geblokkeerd zijn. De veldnaam volgt die
betekenis in plaats van hem te verbergen, want een schema dat het omgekeerde
doet van wat er staat, merk je pas als het te laat is.

Een dag die ontbreekt is de hele dag dicht. Een venster loopt niet door
middernacht; `21:00` tot `07:00` zou een leeg venster zijn en dus een verbod
van vierentwintig uur. Daar staat een assert op, omdat AdGuard het zonder
klagen zou accepteren.

Intern zijn de grenzen milliseconden sinds middernacht. Dat is een
API-detail en hoort niet in een bestand dat een mens bewerkt, dus het
sjabloon rekent het om.

## Eigenaarschap

Beide rollen zijn additief en reconciliërend, en verwijderen nooit.

Bij de rewrites uit deel 2 kon dat wel: daar bezit de rol een hele zone, dus
een naam onder die zone die niemand vraagt hoort er niet. Een client is anders.
Hij draagt instellingen die een mens in het scherm kan hebben aangeraakt, en er
is geen veld dat zegt "Ansible heeft dit gemaakt". Verwijderen bij afwezigheid
zou daarom vroeg of laat iets weggooien dat met de hand is gezet.

In plaats daarvan noemt de AdGuard-taak bij elke run de clients die hij níét
beheert. Zo is het zichtbaar zonder destructief te zijn, hetzelfde patroon als
`cleanup.yml`: eerst rapporteren, pas opruimen op commando.

## Waarom buiten `site.yml`

De UniFi-play schrijft DHCP-reserveringen. Een toestel houdt zijn huidige adres
tot de volgende lease-vernieuwing, dus het is niet meteen verstorend, maar het
verandert wel wat de gateway uitdeelt. Dit is provisioning, en de conventie van
deze repo is dat provisioning niet in het playbook zit dat op elk moment mag
draaien.

De AdGuard-helft is wel veilig en zit daarom óók in de `adguard`-rol, zodat
`site.yml` beleidsdrift terugdraait. `devices.yml` draait hem nog eens; dat is
één idempotente ronde en het maakt "nieuw toestel" één commando.

## Verificatie

Tegen een nagemaakte AdGuard en een nagemaakte gateway:

1. Lege systemen: vier clients aangemaakt, vier reserveringen gezet.
2. Tweede run: `changed=0`, aan beide kanten.
3. Drift in het scherm aangebracht (dienst weggehaald, parental uit, adres uit
   de ids): de run noemt precies die velden en zet ze terug.
4. Een groepswissel op een bestaand toestel wordt herkend en doorgevoerd.
5. Een client die met de hand is gemaakt wordt gerapporteerd en niet aangeraakt.
6. Een bandbreedtegroep die niet bestaat stopt de run, met de groepen die er
   wél zijn in de melding.
7. Een venster dat omkeert, een MAC met hoofdletters en een sleutel met een
   underscore stoppen de run vóór er iets geschreven wordt.
8. `--check` schrijft niets en meldt wel wat het zou doen.

## Buiten scope

Gastvouchers, een toestel blokkeren en firewall- of VLAN-toewijzing. Alle drie
kan de API; ze horen bij een volgend stuk. En de gateway zelf wordt niet
geconfigureerd: dit raakt uitsluitend client-records.
