# Toestellen en DNS: wat de repo beheert, en wat niet

Datum: 2026-09-22
Vervangt: de vier losse specs van deze branch, en de rol die `devices.yml`
kreeg in de toestellenspec van 21-09.

## Probleem

Twee dingen die bij elkaar horen. De inventory kende alleen machines met SSH,
dus telefoons, de TV en de printer bestonden nergens. En AdGuard werd helemaal
niet beheerd: `roles/adguard` installeerde de binary en liet de rest met opzet
aan het webscherm, omdat `AdGuardHome.yaml` het adminwachtwoord, de upstreams
en alle filterregels bevat.

De eerste poging maakte er een lijst van. Die lijst deed niets, en een lijst
die niets doet is werk dat je erin stopt en er niet uit krijgt.

## Wat de repo nu beheert

| Wat | Waaruit | Hoe |
| --- | --- | --- |
| `<host>.home.arpa` | `ansible_host` uit de inventory | AdGuard REST API |
| `<toestel>.home.arpa` | `ip` uit `devices.yml` | AdGuard REST API |
| Filterbeleid per toestel | het `dns`-blok | AdGuard REST API |
| Aanmelden op de tailnet | eenmalige sleutel via de Tailscale-API | `roles/tailscale` |

`AdGuardHome.yaml` wordt één keer gelezen, voor de webpoort, en nooit
geschreven. Het scherm blijft eigenaar van alles wat hier niet staat.

## Beslissingen

**`home.arpa`, niet `neodata.be`.** `semaphore` is zowel een host als een
Caddy-route. Een rewrite in het publieke domein zou die route omleiden naar de
achterkant. RFC 8375 reserveert `home.arpa` precies hiervoor: het lost nooit op
het internet op, dus een query die lekt is onschuldig.

**De rewrites verwijderen wel, de clients niet.** Bij de rewrites bezit de rol
een hele zone, dus een naam daarbinnen die niemand vraagt hoort er niet. Een
client draagt instellingen die een mens in het scherm kan hebben aangeraakt en
er is geen veld dat zegt "Ansible heeft dit gemaakt". Daarom noemt elke run de
clients die hij níét beheert, in plaats van ze weg te gooien.

**`dns.allowed` is een toestemming, geen verbod.** AdGuard bewaart een schema
van *inactiviteit*: de vensters waarin de geblokkeerde diensten niet
geblokkeerd zijn. De veldnaam volgt die betekenis in plaats van hem te
verbergen. Een dag die ontbreekt is de hele dag dicht, en een venster loopt
niet door middernacht; `21:00` tot `07:00` zou leeg zijn en dus een verbod van
vierentwintig uur. Daar staat een assert op, want AdGuard accepteert het
zonder klagen. Intern zijn de grenzen milliseconden sinds middernacht, een
API-detail dat niet hoort in een bestand dat een mens bewerkt.

**Tailscale meldt zichzelf aan, met een sleutel die daarna op is.** In de repo
staat alleen een OAuth-client met scope `auth_keys`. Lekt die, dan kan iemand
getagde nodes toevoegen en verder niets. Een node die al `Running` is wordt
nooit aangeraakt; zijn identiteit leeft in `/var/lib/tailscale` en die maakt een
converge-run niet opnieuw.

## Wat er gebouwd is en weer weggehaald

**De UniFi-rol.** Hij maakte client-records op de gateway aan, zette namen en
bandbreedtegroepen, en reserveerde vaste adressen. Hij werkte en was
idempotent. Hij is verwijderd.

De rekensom klopte niet. Een vast adres toekennen in het scherm kost twintig
seconden en gebeurt één keer per toestel. Daartegenover stonden een apart
lokaal account, een vault-bestand, een gateway in de inventory, en het
onderhoud van een API die Ubiquiti bezit en zonder aankondiging kan wijzigen.

**De telefoonprofielen.** Een `.mobileconfig` per telefoon, met de toestelnaam
als AdGuard-client-ID, zodat het querylog de telefoon bij naam kent wat zijn
MAC ook is. Ook gebouwd, ook weer weg. Het genereerde een bestand dat je
vervolgens met de hand op het toestel aantikt, dus de automatisering hield op
vóór het apparaat. En het sleepte een publiek bereikbare `dns.<domein>` mee,
plus een schakelaar in AdGuard, voor iets wat nog nooit gebruikt was.

De regel die beide had moeten voorkomen, en die vanaf nu geldt: **automatiseer
wat je drie keer met de hand hebt gedaan en waar je drie keer chagrijnig van
werd.** Het AdGuard-beleid haalt die lat wel, want het komt langs dezelfde API
met dezelfde login, het is priegelig genoeg om fouten in te maken, en het
drift zodra iemand in het scherm iets omzet. Een reservering en een profiel
halen hem niet.

## Buiten scope, en dat blijft zo

De router. Gastvouchers, een toestel blokkeren, VLAN- en firewalltoewijzing.
De API kan het allemaal; geen ervan haalt de lat hierboven.

## Verificatie

Tegen een nagemaakte AdGuard en een nagemaakte Tailscale-API: eerste run maakt
aan, tweede run `changed=0`, drift die in het scherm is aangebracht wordt per
veldnaam herkend en teruggezet, een met de hand gemaakte client wordt gemeld
en niet aangeraakt. Een omgekeerd venster, een MAC met hoofdletters en een
sleutel met een underscore stoppen de run voordat er iets geschreven wordt.
`--check` schrijft niets en meldt wel wat het zou doen.

Niet geverifieerd: de echte apparatuur. De eerste run daar hoort met
`--check --diff`.
