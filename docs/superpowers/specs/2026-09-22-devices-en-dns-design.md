# DNS-namen in AdGuard, en waarom de toestellenlijst weer weg is

Datum: 2026-09-22
Vervangt: de toestellenspec van 21-09 en de vier losse specs die daarop volgden.

## Wat de repo beheert

| Wat | Waaruit | Hoe |
| --- | --- | --- |
| `<host>.home.arpa` | `ansible_host` uit de inventory | AdGuard REST API |
| Aanmelden op de tailnet | eenmalige sleutel via de Tailscale-API | `roles/tailscale` |

Meer niet. `AdGuardHome.yaml` wordt één keer gelezen, voor de webpoort, en
nooit geschreven: het bevat het adminwachtwoord, de upstreams en alle
filterregels, en het webscherm blijft daar eigenaar van.

**`home.arpa` en niet `neodata.be`,** omdat `semaphore` zowel een host als een
Caddy-route is. Een rewrite in het publieke domein zou die route omleiden naar
de achterkant. RFC 8375 reserveert `home.arpa` hiervoor: het lost nooit op het
internet op, dus een query die lekt is onschuldig.

**De rol bezit die hele zone.** Een naam erbinnen die de inventory niet vraagt
wordt verwijderd, een rewrite erbuiten blijft staan. Dat kan alleen omdat de
zone van de rol is; bij iets waar een mens ook aan zit, zou verwijderen op
afwezigheid vroeg of laat handwerk weggooien.

**Tailscale meldt zichzelf aan** met een sleutel die daarna op is. In de repo
staat alleen een OAuth-client met scope `auth_keys`; lekt die, dan kan iemand
getagde nodes toevoegen en verder niets. Een node die al `Running` is wordt
nooit aangeraakt: zijn identiteit leeft in `/var/lib/tailscale` en die maakt
een converge-run niet opnieuw.

## Wat er gebouwd is en weer weggehaald

Drie keer hetzelfde patroon, en het is de moeite waard dat op te schrijven
zodat het geen vierde keer gebeurt.

**Een UniFi-rol** die client-records aanmaakte, namen zette,
bandbreedtegroepen toewees en vaste adressen reserveerde. Werkte, was
idempotent. Een vast adres toekennen kost twintig seconden klikken en gebeurt
één keer per toestel; daartegenover stonden een apart account, een
vault-bestand en het onderhoud van een API die Ubiquiti bezit.

**Telefoonprofielen**, een `.mobileconfig` per toestel met de naam als
AdGuard-client-ID. Het genereerde een bestand dat je daarna met de hand op het
toestel aantikt, dus de automatisering hield op vóór het apparaat. En het
sleepte een publiek bereikbare `dns.<domein>` mee voor iets dat nog nooit
gebruikt was.

**De toestellenlijst zelf**, `devices.yml`, met een filterbeleid per toestel in
AdGuard. Dit was de laatste en de leerzaamste. De lijst was een tweede kopie
van wat de UniFi-gateway al weet: elk toestel in huis staat daar met zijn
MAC-adres, zijn naam en zijn reservering. Een tweede lijst bijhouden naast een
lijst die altijd klopt, levert alleen een kans op dat ze uit elkaar lopen.

Wat ermee meeging: `roles/adguard/tasks/clients.yml`,
`playbooks/tasks/check_devices.yml`, het toestellensjabloon en zijn pagina.
Samen ongeveer 370 regels die niets deden zolang de lijst leeg was.

Filterbeleid per toestel is daarmee geen repo-ding meer. Wil je het, dan klik
je het in AdGuard, net zoals een reservering in UniFi. Komt de behoefte er
echt, dan staat `clients.yml` in de git-geschiedenis.

## De regel die hieruit volgt

**Automatiseer wat je drie keer met de hand hebt gedaan en waar je drie keer
chagrijnig van werd.**

Geen van de drie haalde die lat. De namen voor de hosts wel, en die kosten
niets extra: ze komen uit de inventory die er toch al is. Dat is het verschil
waar het op aankomt. Automatisering die leunt op gegevens die je al hebt is
gratis; automatisering die om een nieuwe lijst vraagt, betaalt die lijst voor
altijd terug in onderhoud.

## Buiten scope, en dat blijft zo

De router, en alles wat daarin staat. Gastvouchers, toestellen blokkeren,
VLAN- en firewalltoewijzing. Filterbeleid per toestel.

## Verificatie

Tegen een nagemaakte AdGuard: eerste run zet de namen van de hosts met een
`ansible_host`, verwijdert een verouderde naam en een uitgeschakelde binnen de
zone, en laat een `*.neodata.be`-rewrite onaangeroerd. Tweede run
`changed=0`. `--check` schrijft niets en meldt wel wat het zou doen.

Tegen een nagemaakte Tailscale-API: een ontbrekend of ongeldig label stopt de
run, een geldig label levert één eenmalige sleutel met de juiste tag.

Niet geverifieerd: de echte apparatuur. De eerste run daar hoort met
`--check --diff`.
