# Tailscale: één sleutel per toestel, en de rol die zichzelf aanmeldt

Datum: 2026-09-22
Status: deel 3 van 4 (volgt op de toestellenlijst)

## Probleem

`roles/tailscale` installeert de client, maar meldt de node niet aan. Na een
herbouw staat er "authenticate once with `tailscale up`" in de uitvoer en
doet iemand dat met de hand, via een browser. De rol hield bewust geen
auth key vast: een herbruikbare sleutel in de repo is een sleutel die je
nooit meer durft te roteren.

Het alternatief dat wél past is een sleutel per toestel: eenmalig, vooraf
geautoriseerd, gemaakt op het moment dat hij nodig is, en daarna op.

## Doel

Een node die niet op de tailnet staat meldt zichzelf aan tijdens `site.yml`,
met een sleutel die alleen voor hem gemaakt is. En voor toestellen uit
`devices.yml` met een commandoregel is er één playbook dat zo'n sleutel
maakt en één keer toont.

## Beslissingen

| | |
| --- | --- |
| Credential in de repo | Een OAuth-client met scope `auth_keys`, niet een auth key |
| Sleutel | Eenmalig (`reusable: false`), `preauthorized: true`, 10 minuten geldig |
| Tag | `tag:homelab`; een OAuth-client kán alleen getagde sleutels maken |
| Tailnet | `-`, de tailnet van de credential zelf; de naam staat nergens |
| Wanneer | Alleen als `BackendState != Running`; een draaiende node blijft onaangeroerd |
| Zonder OAuth-client | De rol rapporteert, zoals voorheen; aanmelden blijft dan handwerk |

## Waarom een OAuth-client

Een persoonlijke API-token verloopt na negentig dagen en is gebonden aan een
gebruiker. Een OAuth-client verloopt niet en kan precies één ding: sleutels
maken die nodes toevoegen. Lekt hij, dan kan iemand getagde nodes toevoegen
— niets lezen, niets veranderen aan bestaande nodes. Dat is een kleinere
blast radius dan een herbruikbare auth key, die precies hetzelfde kan maar
ook nog werkt zonder API.

De client staat in `inventory/host_vars/tailscale/vault.yml`, onder `infra`,
als `vault_tailscale_oauth_client_id` en `vault_tailscale_oauth_client_secret`.
De `main.yml` ernaast verwijst ernaar.

## De rol

Na de bestaande statuscontrole:

1. Staat de node op `Running`, dan gebeurt er niets. De identiteit van de node
   leeft in `/var/lib/tailscale`; die maakt een converge-run niet opnieuw.
2. Anders, en mét OAuth-client: `mint_key.yml` wisselt de client om voor een
   API-token, maakt één sleutel met beschrijving `ansible-<host>`, en de rol
   draait `tailscale up --auth-key=…` plus `tailscale_up_extra_args`. Daarna
   leest hij de status opnieuw en eist `Running`.
3. Anders, zonder client: de oude melding, met erbij hoe je de client zet.

De sleutel gaat via `argv`, niet door een shell, en de taak staat op `no_log`.
De sleutel komt nergens op schijf; de beschrijving in de admin-console is het
enige spoor.

`tailscale_up_extra_args` is er omdat `tailscale up` weigert als een node al
prefs heeft (`--advertise-routes`) die je niet herhaalt. Wat de node
adverteerde, staat dus in de inventory, waar het toch al hoorde.

`--check` toont dat de node zou aanmelden en roept de API niet aan.

## Het playbook

`playbooks/tailscale-key.yml -e device=<naam>`: één sleutel voor één toestel
uit `devices.yml`, beschrijving `device-<naam>`, getoond in de uitvoer met het
commando erbij. Een naam die niet in de lijst staat wordt geweigerd — de lijst
is de bron, ook hier.

Het speelt op `hosts: tailscale` maar verbindt nergens mee: play-vars zetten
`ansible_connection: local` en `ansible_become: false`. Dat laatste overstemt
bewust de `linux`-groep, die anders `sudo` op het werkstation zou doen. Het
playbook zegt dat zelf in zijn kop, omdat README precies dit patroon als val
beschrijft.

Niet vanuit Semaphore: de sleutel staat in de uitvoer, en een takenlog
bewaart die.

## Wat dit niet oplost

Telefoons. De iOS- en Android-app melden aan via een browser en hebben geen
plek voor een sleutel; een auth key via configuratieprofiel vraagt een echte
MDM. Het playbook is voor de pc van de ouders, een NAS, een Raspberry Pi —
alles met `tailscale up`.

## Vereisten aan de tailnet

- In de policy: `tagOwners` met `tag:homelab`, en de OAuth-client mag die tag
  toekennen (dat kies je bij het aanmaken van de client).
- Een getagde node heeft geen eigenaar en zijn sleutel verloopt niet. Voor
  servers is dat de bedoeling.

## Verificatie

Tegen een nagemaakte API en een nagemaakte `tailscale`:

1. `NeedsLogin`, `--check`: één `changed` op het rapport, niets aangeroepen.
2. `NeedsLogin`, echt: token gewisseld, sleutel gemaakt met
   `expirySeconds` als getal en de tag, `tailscale up` met de sleutel én de
   extra argumenten, status daarna `Running`.
3. `Running`: `changed=0`, geen API-aanroep.
4. Zonder OAuth-client: alleen de melding.
5. `tailscale-key.yml` zonder `-e device`, met een onbekende naam, en met
   een bekende: de eerste twee stoppen met de lijst van namen, de derde toont
   de sleutel.
