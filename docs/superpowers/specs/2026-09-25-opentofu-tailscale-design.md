# OpenTofu, deel 1: de basis en Tailscale

25-09-2026. Samen met Ruben afgesproken.

## Doel

Git beslist, Tailscale volgt. De toegangsregels, de DNS-instellingen, de
subnet-route van ct 108 en de tags van de tailnet staan in deze repo, en
OpenTofu zet ze in Tailscale. Klikken in de console en daarna overtikken in
`policy.hujson` stopt.

Dit is deel 1 van TODO B. Deel 2 (Proxmox: guests, gebruikers, rechten) en
deel 3 (PBS) krijgen elk een eigen spec, en bouwen op de basis hier.

Klaar als:

- `bin/tofu tailscale plan` zegt **No changes** tegen de echte tailnet.
- Een wijziging in `files/tailscale/policy.hujson` komt via `bin/tofu
  tailscale apply` in de console, en de `tests` in dat bestand worden daarbij
  door Tailscale gecontroleerd.
- In de console staat "edits beperken" aan.
- De state staat versleuteld in R2, met een slot.

## Beslist

| Vraag | Keuze | Waarom |
| --- | --- | --- |
| Waar draait `tofu` | alleen op de mbp, met de hand | begin eenvoudig; een geplande `plan` in Semaphore kan later |
| Eén project of één per systeem | één map en één state per systeem: `tofu/tailscale/`, later `tofu/proxmox/` | klein en snel, en een fout in het ene raakt het andere niet |
| Waar staat de state | Cloudflare R2, bucket `homelab-tofu-state`, key `<systeem>/terraform.tfstate` | niet in git (geen slot), niet op de homelab (ligt pve01 plat, dan is de kaart ook weg) |
| Slot | `use_lockfile = true` in de `s3`-backend | slot als bestand naast de state, geen database nodig (OpenTofu ≥ 1.10) |
| Versleuteling van de state | `encryption`-blok, `pbkdf2`, `enforced = true`, ook voor plan-bestanden | de state bevat geheimen; zo leest Cloudflare alleen bytes. `enforced` weigert per ongeluk een leesbare state te schrijven |
| Geheimen | één gevaulte `tofu/secrets.env` (vault `infra`), `bin/tofu` zet ze als env-variabelen | één kluis, één wachtwoord, geen tweede systeem zoals SOPS |
| Tailscale-toegang | een nieuwe OAuth-client alleen voor OpenTofu: scopes `policy_file`, `dns`, `devices:core`, `devices:routes` (tag `tag:homelab`) | de bestaande client maakt alleen sleutels. Twee clients, elk zo weinig mogelijk rechten |
| Waar staan de regels | `files/tailscale/policy.hujson`, zelfde bestand en formaat | OpenTofu leest het met `file()`; de commentaren blijven, want Tailscale bewaart HuJSON zoals het is |
| Versies | `required_version = ">= 1.10"`, provider `tailscale/tailscale` vast op een minor (`~> 0.x`), `.terraform.lock.hcl` in git | dezelfde provider op elke machine, met controlesom |

## Hoe het eruitziet

```
tofu/
  secrets.env            # gevault (infra): R2-sleutel, passphrase, OAuth-client
  tailscale/
    versions.tf          # required_version, provider-versie
    backend.tf           # R2 + slot + versleuteling
    providers.tf         # tailscale-provider, leest zijn sleutels uit env
    policy.tf            # tailscale_acl uit files/tailscale/policy.hujson
    dns.tf               # globale nameserver (adguard), MagicDNS, zoekdomein
    devices.tf           # subnet-route van ct 108, tags van de nodes
    .terraform.lock.hcl
bin/tofu                 # wrapper
```

### `bin/tofu`

Ongeveer tien regels bash:

1. `ansible-vault view tofu/secrets.env` (de identiteiten uit `ansible.cfg`,
   dus hetzelfde wachtwoord als voor de rest) en de regels exporteren.
2. `tofu -chdir=tofu/<systeem> <rest>`.

Gebruik: `bin/tofu tailscale plan`, `bin/tofu tailscale apply`.

Wat in `secrets.env` staat:

| Variabele | Voor |
| --- | --- |
| `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` | de R2-token, alleen voor die ene bucket |
| `AWS_ENDPOINT_URL_S3` | het R2-endpoint; zo staat het account-ID niet in git |
| `TF_VAR_state_passphrase` | de versleuteling van de state |
| `TAILSCALE_OAUTH_CLIENT_ID`, `TAILSCALE_OAUTH_CLIENT_SECRET` | de OpenTofu-client |

De backend en het `encryption`-blok lezen `var.state_passphrase`; dat mag
sinds OpenTofu 1.8 (early evaluation). Geen geheim in een `.tf`-bestand, geen
geheim in de shellgeschiedenis.

### Wat OpenTofu in Tailscale beheert

| Resource | Wat |
| --- | --- |
| `tailscale_acl` | de hele policy uit `policy.hujson` |
| DNS | adguard (`100.84.46.18`) als globale nameserver, MagicDNS, het zoekdomein zoals nu in de console |
| `tailscale_device_subnet_routes` | ct 108: `192.168.0.0/24` goedgekeurd |
| `tailscale_device_tags` | `tag:homelab` op `tailscale` en `adguard` |

De nodes zelf zoekt OpenTofu op met een `data "tailscale_device"` op naam; hij
maakt of verwijdert geen toestellen. Aanmelden blijft bij Ansible
(`roles/tailscale`) en NeoGate. NeoGate nodigt alleen mensen uit en raakt de
policy niet, dus die twee zitten elkaar niet in de weg.

## Stappen

Niets verandert in Tailscale voor stap 6. Tot dan is terug gaan: de map
`tofu/` weggooien.

1. **Handstappen in de consoles** (kunnen niet anders, de rest volgt uit
   git):
   - Cloudflare: bucket `homelab-tofu-state` in R2, en een API-token met
     Object Read & Write op alleen die bucket.
   - Tailscale: een nieuwe OAuth-client met `policy_file`, `dns`,
     `devices:core`, `devices:routes`.
   - Een passphrase van minstens 16 tekens, ook in de wachtwoordkluis (zonder
     passphrase is de state onleesbaar, ook voor jou).
   - De zes waarden in `tofu/secrets.env`, versleuteld met
     `--encrypt-vault-id infra`.
2. **Tooling**: `opentofu` in de Homebrew-lijst van de mbp; `bin/tofu`;
   `tofu/secrets.env` in `bin/check-vaulted`; `.terraform/`, `*.tfstate*` en
   `*.tfplan` in `.gitignore`.
3. **Console = repo**: de huidige policy uit de console naast
   `policy.hujson` leggen. TODO A2 zegt dat de repo al regels heeft die de
   console misschien nog niet heeft (`mac-mini:32400`, de test met Maarten,
   funnel alleen voor jou). Voor de import moet `policy.hujson` **precies de
   console** zijn; die verschillen komen terug in stap 6. Alleen de
   commentaren mogen verschillen.
4. **Code en import**: de `.tf`-bestanden, `tofu init`, dan `tofu import`
   voor de policy, de DNS, de route van ct 108 en de tags.
5. **Leeg plan**: `bin/tofu tailscale plan` moet **No changes** zeggen. Zegt
   hij iets anders, dan de code aanpassen tot het leeg is. Pas daarna iets
   veranderen.
6. **Eerste echte wijziging**: de A2-regels van stap 3 terug in
   `policy.hujson`, `plan`, `apply`. De `tests` moeten slagen, anders weigert
   Tailscale.
7. **Console dicht**: in de Tailscale-console "edits beperken" aan
   (policy file management), zodat niemand er nog buiten git om iets wijzigt.
8. **Controle vóór commit**: `.githooks/pre-commit` draait `tofu fmt -check`
   en `tofu validate` als er iets onder `tofu/` gewijzigd is.
9. **Docs en TODO**:
   - Runbook: sectie "Tailscale-regels aanpassen" op de bestaande pagina
     `runbooks/toegang/toestellen.mdx` (de runbook-stijl: een nieuw geval is
     een sectie, geen nieuwe pagina), met wat eenmalig op een nieuwe computer
     moet.
   - `homelab/netwerk.mdx`: de console is niet meer de bron.
   - De header van `policy.hujson`: "GEEN PLAYBOOK LEEST DIT BESTAND" wordt
     "dit is de bron, OpenTofu zet het in Tailscale".
   - TODO: A2's "console → git" en de Tailscale-punten in B afvinken.

## Testen

- Stap 5: `plan` leeg na de import.
- Stap 6: na `apply` nog een `plan`: weer leeg.
- De `tests` in `policy.hujson` (worden door Tailscale bij elke apply
  gecontroleerd): jij mag alles, `tag:work` niet naar Proxmox, Maarten wel
  naar Plex en Caddy maar niet naar SSH en Proxmox.
- Met een familie-account: Plex en `*.neodata.be` werken, `:22` en Proxmox
  niet (dit stond al in A2).
- `bin/check-vaulted` groen met `tofu/secrets.env` erbij.
- Tweede terminal tegelijk `plan` laten draaien tijdens een `apply`: die moet
  op het slot wachten of weigeren.

## Goed om te weten

- **R2 heeft geen versiegeschiedenis.** Gaat de state kapot, dan is de
  oplossing opnieuw importeren. Dat is hier aanvaardbaar: alles wat deze
  state kent is te importeren.
- **Kwijt de passphrase = state kwijt.** Dan weer importeren, met een
  nieuwe state. Daarom staat hij ook in de wachtwoordkluis, niet alleen in
  de vault.
- **"Edits beperken" geldt ook voor jou.** Een snelle wijziging in de console
  kan dan niet meer; alles gaat via git. Nood: de instelling tijdelijk
  uitzetten, en achteraf `policy.hujson` gelijkzetten tot `plan` leeg is.
- **Niet in dit deel:** Proxmox (deel 2), PBS (deel 3), de `/dev/net/tun`-
  regels van ct 107 en 108 (hoort bij deel 2), een geplande `plan` in
  Semaphore.
