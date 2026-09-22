# Toestellen: wat Ansible wel en niet van ze beheert

Datum: 2026-09-22
Status: vervangt de rol die `devices.yml` in deel 1 kreeg, en legt vast wat er
op 22-09 weer uit is gehaald

## Probleem

`devices.yml` was een lijst: het schreef op wat er in huis stond en welk adres
het hoorde te hebben. De spec van deel 1 noemde dat zelf een risico, `ip` was
"een bedoeling, geen meting", en niets dwong het af. Een lijst die niets doet
is werk dat je erin stopt en er niet uit krijgt.

De eerste reactie daarop was: laat het dan alles afdwingen. Er zijn twee
systemen in huis die een toestel zonder SSH kunnen configureren, UniFi en
AdGuard, en allebei hebben ze een API. Die kant is gebouwd, gemeten, en voor
de helft weer verwijderd. Dit document legt vast waarom, want de code is weg
en de afweging niet.

## Wat er blijft

`devices.yml` is de gewenste toestand van wat **AdGuard** over een toestel
moet weten, en verder niets.

| Wat | Waaruit |
| --- | --- |
| `<toestel>.home.arpa` | `ip` |
| `<host>.home.arpa` | `ansible_host` uit de inventory |
| Client met filterbeleid | het `dns`-blok |
| `.mobileconfig`-profiel | `devices_profile_types` |

## Wat eruit is, en waarom

Een rol die op de UniFi-gateway client-records aanmaakte, namen zette,
bandbreedtegroepen toewees en vaste adressen reserveerde. Hij werkte, was
idempotent en herkende drift per veld. Hij is verwijderd in commit
`cleanup`, en dat was de juiste beslissing.

De rekensom klopte niet. Een vast adres toekennen in het scherm kost twintig
seconden en gebeurt één keer per toestel. Daar stond tegenover: een apart
lokaal account, een vault-bestand, een gateway-adres in de inventory, en het
onderhoud van een API die Ubiquiti bezit en zonder aankondiging kan wijzigen.
Voor een handvol toestellen die een paar keer per jaar veranderen betaalt dat
zichzelf nooit terug.

De vuistregel die dit had moeten voorkomen: automatiseer wat je drie keer met
de hand hebt gedaan en waar je drie keer chagrijnig van werd. Een reservering
zetten voldoet daar niet aan.

## Waarom het AdGuard-beleid wél blijft

Dezelfde vraag, andere uitkomst, en het verschil is het noemen waard.

- Er komt geen enkele infrastructuur bij. De rol praat toch al met die API
  voor de rewrites, met dezelfde login.
- De instellingen zijn talrijk en priegelig. Een schema met zeven dagen
  opnieuw intikken in een webscherm is precies het soort werk waar een fout
  in sluipt.
- Ze driften. Iemand zet in het scherm iets uit en niemand weet het nog. Een
  run zet het terug en noemt het veld. Dat terugzetten ís de kracht van
  Ansible; een reservering die nooit vanzelf verandert heeft dat niet nodig.
- Het is beleid waar over te twijfelen valt. Kunnen zien wat er vorige maand
  stond en waarom, is meer waard dan de klikken die het bespaart.

### `allowed` is een toestemming, geen verbod

AdGuard slaat per client een schema van *inactiviteit* op: de vensters waarin
de geblokkeerde diensten niet geblokkeerd zijn. De veldnaam volgt die
betekenis in plaats van hem te verbergen, want een schema dat het omgekeerde
doet van wat er staat, merk je pas als het te laat is.

Een dag die ontbreekt is de hele dag dicht. Een venster loopt niet door
middernacht; `21:00` tot `07:00` zou leeg zijn en dus een verbod van
vierentwintig uur. Daar staat een assert op, omdat AdGuard het zonder klagen
zou accepteren. Intern zijn de grenzen milliseconden sinds middernacht; dat
is een API-detail en hoort niet in een bestand dat een mens bewerkt.

## Eigenaarschap van de clients

Additief en reconciliërend, nooit verwijderend.

Bij de rewrites kan verwijderen wel: daar bezit de rol een hele zone, dus een
naam onder die zone die niemand vraagt hoort er niet. Een client is anders.
Hij draagt instellingen die een mens in het scherm kan hebben aangeraakt, en
er is geen veld dat zegt "Ansible heeft dit gemaakt". In plaats daarvan noemt
de taak bij elke run de clients die hij níét beheert, hetzelfde patroon als
`cleanup.yml`: eerst rapporteren, pas opruimen op commando.

## Hoe je het draait

Er is geen apart playbook meer. Het beleid zit in de `adguard`-rol, dus:

```bash
ansible-playbook playbooks/site.yml --tags dns --check --diff
ansible-playbook playbooks/site.yml --tags dns
```

Eén playbook minder is ook opruimen. Een aparte `devices.yml` deed niets wat
deze tag niet al doet.

## Buiten scope, en dat blijft zo

Gastvouchers, een toestel blokkeren, VLAN- en firewalltoewijzing. De API kan
het allemaal. Geen ervan is drie keer met de hand gedaan en vervelend
bevonden, dus geen ervan wordt gebouwd tot dat wel zo is.
