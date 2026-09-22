# DNS-namen in AdGuard: alleen de rewrite-lijst, via de API

Datum: 2026-09-22
Status: deel 2 van 4 (volgt op de toestellenlijst)

## Probleem

Een toestel of host is in dit huis alleen bij zijn adres bekend. Wie de
printer wil bereiken typt `192.168.0.71`, en wie een LXC herbouwt zoekt het
nieuwe adres op in Proxmox. De kennis staat inmiddels op één plek — de
inventory voor hosts, `devices.yml` voor de rest — maar niets vertaalt die
naar namen.

AdGuard Home kan dat, met rewrites. Maar `roles/adguard` zegt expliciet dat het
`AdGuardHome.yaml` niet beheert: dat bestand bevat het adminwachtwoord, de
upstreams en alle filterregels, en het wordt via het webscherm bewerkt. Zou de
rol het templaten, dan vecht hij met het scherm om eigenaarschap en wint er
één, ten koste van de ander.

## Doel

Elke host uit de inventory en elk toestel met een adres uit `devices.yml`
krijgt een naam in AdGuard, uit die twee lijsten, zonder dat de rol één byte
in `AdGuardHome.yaml` schrijft.

## Beslissingen

| | |
| --- | --- |
| Kanaal | De REST API (`/control/rewrite/*`), Basic auth met de UI-login |
| Eigenaarschap | Alleen de rewrite-lijst, en daarin alleen namen onder één zone |
| Zone | `home.arpa` (RFC 8375), instelbaar als `adguard_rewrite_domain` |
| Bron | `hostvars[*].ansible_host` én `devices[*].ip`, beide als `<naam>.<zone>` |
| Poort van de API | Gelezen uit `http.address` in `AdGuardHome.yaml`, niet gegokt |
| Zonder credentials | De run faalt, met een melding die zegt wat er moet komen |

## Waarom `home.arpa` en niet `neodata.be`

`semaphore` is zowel een host als een route. `semaphore.neodata.be` hoort bij
Caddy; een rewrite naar het LXC-adres zou die route omleiden naar de
achterkant. Elke host die ook een `caddy_sites`-naam draagt heeft dat
probleem. Een eigen zone maakt het onmogelijk, en `home.arpa` is precies
daarvoor gereserveerd: het lost nooit op het publieke internet op, dus een
query die naar buiten lekt is onschuldig.

## Eigenaarschap, precies

De rol leest de hele lijst, maar kijkt alleen naar entries waarvan het domein
op `.home.arpa` eindigt. Daarbinnen convergeert hij:

- een gewenste naam die ontbreekt wordt toegevoegd;
- een naam onder de zone die niemand meer vraagt — een verhuisd toestel, een
  hernoemde host — wordt verwijderd;
- een uitgeschakelde entry telt als afwezig: eerst weg, dan opnieuw erbij,
  ingeschakeld. Eerst verwijderen, omdat `add` blind toevoegt en `delete` op
  domein+antwoord matcht — andersom zouden allebei verdwijnen.

Buiten de zone raakt hij niets aan. Een `*.neodata.be`-rewrite die met de hand
in het scherm staat blijft precies zo staan.

## Wat de rol nog wel leest

`AdGuardHome.yaml` wordt één keer gelezen, voor de poort van het webscherm.
Dat is lezen, niet bezitten; de setup-wizard kiest die poort en de rol volgt.
Het bestand bevat de wachtwoordhash, dus elke taak die de inhoud draagt staat
op `no_log`; alleen de poort overleeft als fact.

Bestaat het bestand niet, dan is de wizard nog niet doorlopen. De rol zegt
dat, met het adres om hem te openen, in plaats van te struikelen over een
ontbrekend bestand.

## Credentials

`inventory/host_vars/adguard/main.yml` verwijst naar `vault_adguard_api_user`
en `vault_adguard_api_password`; de `vault.yml` ernaast maakt de eigenaar,
onder de identiteit `infra`. Zonder die file faalt de rol met een assert die
het commando geeft.

Falen, niet overslaan: een rewrite-lijst die stilletjes niet meer wordt
toegepast is erger dan een rode run. Dat is dezelfde afweging als bij een
geplande job die stil faalt.

## Controles

- Elke gewenste naam moet een geldige DNS-naam zijn (kleine letters, cijfers,
  koppeltekens). De API antwoordt anders met een 400 zonder naam; de rol
  noemt hem wél.
- `docs.yml` controleert al dat geen `devices[*].ip` botst met een
  `ansible_host`, en krijgt er één regel bij: de sleutel van een toestel moet
  een geldig label zijn, want hij wordt er nu een.
- `--check` roept de API niet aan, maar toont wél wat er zou veranderen: het
  rapport-taakje staat vóór de API-taken en telt als `changed`.

## Buiten scope

Het `enabled`-schakelaartje van de rewrite-functie als geheel, AdGuard-clients
(namen bij client-ID's), en alles wat verder in `AdGuardHome.yaml` staat.

## Verificatie

Tegen een nagemaakte API, met een lijst die een verouderde naam, een
uitgeschakelde gewenste naam en een `*.neodata.be`-rewrite bevat:

1. Eerste run: verouderde naam weg, uitgeschakelde naam weg en opnieuw erbij,
   ontbrekende namen erbij, de wildcard onaangeroerd.
2. Tweede run: `changed=0`.
3. `--check` na een toegevoegd toestel: `changed=1` op het rapport, de
   API-taken overgeslagen.
4. Een host met een underscore in zijn naam stopt de run vóór de API, met
   die naam in de melding.
