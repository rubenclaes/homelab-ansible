# DNS-profielen voor de telefoons

Datum: 2026-09-22
Status: deel 4 van 4 (volgt op de toestellenlijst)

## Probleem

AdGuard herkent een client aan zijn adres. Voor een LXC klopt dat; voor een
telefoon niet: iOS en Android wisselen per netwerk van MAC-adres, dus de
reservering in de router — en daarmee de naam uit deel 2 — treft de telefoon
alleen als hij toevallig zijn echte adres gebruikt. In de querylog staat dan
een willekeurig adres, en de vraag "wat vraagt de iPhone eigenlijk op"
blijft onbeantwoord.

AdGuard heeft daar iets voor: DNS-over-HTTPS met een client-ID in het pad,
`/dns-query/<id>`. De telefoon zegt dan zelf wie hij is, wat zijn adres ook
is. Op Apple-toestellen zet je dat met een `.mobileconfig`, en AdGuard heeft
zelfs een knop die er een maakt. Maar die knop kent de toestellenlijst niet.

## Doel

Voor elk toestel van type `phone` een `.mobileconfig` met de sleutel uit
`devices.yml` als client-ID, gegenereerd door `docs.yml` en te downloaden van
de documentatiesite.

## Beslissingen

| | |
| --- | --- |
| Inhoud | Dezelfde payload als AdGuards eigen generator (`com.apple.dnsSettings.managed`, DoH) |
| UUID's | Afgeleid van de toestelnaam (`to_uuid`), zodat een tweede run niets verandert |
| Ingang | `https://dns.<domein>/dns-query/<toestel>`, via Caddy naar AdGuards webpoort |
| Wie | `devices_profile_types: [phone]` — het type bepaalt het, zoals de toestellenspec voorzag |
| Waar actief | Altijd, tenzij `devices_profile_ssids` de thuisnetwerken noemt |
| Serveren | `docs-site/public/profielen/<toestel>.mobileconfig`, dus `docs.<domein>/profielen/…` |

## Waarom niet AdGuards eigen knop

Die maakt bij elke aanroep nieuwe UUID's en kent geen on-demand-regels. Een
eigen sjabloon is vijftig regels plist, geeft een deterministische uitvoer —
de "tweede run, geen diff"-controle die de hele documentatiesite al heeft —
en kan het profiel tot de thuis-wifi beperken. De payload zelf is
overgenomen uit `internal/home/mobileconfig.go`, zodat wat iOS te zien krijgt
hetzelfde is als wat AdGuard zelf zou geven.

## De ingang: `dns.<domein>`

Niet als `caddy_sites`-entry, maar als vaste site in de Caddyfile, naast
`docs.` en `report.`. Alleen `/dns-query` en `/dns-query/*` gaan door naar
AdGuard; de rest krijgt 403. AdGuards beheerscherm zit op dezelfde poort, en
een gegenereerde route zou het hele scherm op het internet zetten. Het
upstream-adres staat in `caddy_doh_upstream`, gevormd zoals
`caddy_tinyauth_upstream`, mét dezelfde waarschuwing over lezen vanuit
localhost.

Geen `client_ip`-beperking: een telefoon buitenshuis heeft het adres dat hij
heeft, en dáár is het profiel juist voor.

Aan AdGuards kant moet één schakelaar om, met de hand, in het scherm:
*Encryptie → Sta onversleutelde DNS-over-HTTPS toe*. Caddy beëindigt de TLS,
AdGuard krijgt gewone HTTP. Dat is configuratie in `AdGuardHome.yaml`, en die
blijft van het scherm — precies zoals deel 2 afsprak.

## Het profiel op de telefoon

Safari downloadt, Instellingen installeert. Caddy geeft `.mobileconfig` het
type `application/x-apple-aspen-config` mee, anders toont iOS een tekstbestand.
De stappen staan op de toestellenpagina, onder het kopje *Telefoonprofielen*,
naast de link per toestel.

## Altijd aan, of alleen thuis

Standaard staat het profiel altijd aan — dat is ook wat AdGuards knop doet.
Buitenshuis loopt elke DNS-vraag dan naar `dns.<domein>`. Dat is de bedoeling
(adblocking overal) maar ook het risico: iOS valt niet terug op gewone DNS
als de versleutelde server niet antwoordt. Is Caddy van buiten niet
bereikbaar, dan heeft de telefoon buitenshuis geen DNS.

`devices_profile_ssids` beperkt het profiel tot de genoemde wifi-netwerken;
elders doet iOS `Disconnect` en gebruikt de telefoon de DNS van het netwerk.
De pagina zegt welke van de twee geldt.

## Opruimen

`public/profielen/` wordt per run geleegd en opnieuw gevuld, zoals de
servicepagina's: een telefoon die uit de lijst gaat laat geen downloadbaar
profiel achter.

## Buiten scope

Android (geen profielen; daar typ je `dns.<domein>` in als privé-DNS, zonder
client-ID). AdGuard-clients met een leesbare naam bij het ID — het ID is de
toestelnaam zelf, dus de querylog is al leesbaar. Het toevoegen van
`ServerAddresses` aan het profiel; `dns.<domein>` moet gewoon resolven, zoals
elke andere `*.<domein>`-naam.

## Verificatie

1. `docs.yml` rendert `public/profielen/iphone-ruben.mobileconfig`;
   `plistlib` leest het zonder fout en toont de DoH-URL met het client-ID.
2. Met `devices_profile_ssids` gevuld, inclusief een `&` in een naam: twee
   on-demand-regels, de SSID's correct ge-escaped.
3. Twee runs, geen diff — de UUID's zijn per toestel constant.
4. De site bouwt en `out/profielen/` bevat het bestand; de toestellenpagina
   linkt ernaar.
5. Op de telefoon: na installatie verschijnen de vragen in de querylog onder
   de toestelnaam. Dat kan alleen de eigenaar controleren.
