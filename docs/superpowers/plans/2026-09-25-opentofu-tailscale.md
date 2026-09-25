# OpenTofu, deel 1: de basis en Tailscale — uitvoeringsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** De Tailscale-policy, de DNS-instellingen, de subnet-route van ct 108 en de tags van de nodes staan in git, en `bin/tofu tailscale apply` zet ze in Tailscale; `plan` is leeg tegen de echte tailnet.

**Architecture:** Eén OpenTofu-project per systeem onder `tofu/`, hier `tofu/tailscale/`. State in Cloudflare R2 met een slotbestand en OpenTofu-versleuteling. `bin/tofu` haalt de geheimen uit een gevaulte `tofu/secrets.env` (vault `infra`) en zet ze als env-variabelen. Bestaande dingen worden met `import`-blokken overgenomen tot `plan` leeg is; pas daarna verandert er iets.

**Tech Stack:** OpenTofu 1.12 (Homebrew), provider `tailscale/tailscale` 0.29.x, Cloudflare R2 (S3-backend), Ansible Vault, bash.

**Spec:** `docs/superpowers/specs/2026-09-25-opentofu-tailscale-design.md`

## Global Constraints

- `required_version = ">= 1.10"`; provider `tailscale/tailscale` op `~> 0.29`; `.terraform.lock.hcl` in git, met hashes voor `darwin_arm64` en `linux_amd64`.
- State: bucket `homelab-tofu-state`, key `tailscale/terraform.tfstate`, `use_lockfile = true`.
- Versleuteling: `pbkdf2` + `aes_gcm`, `enforced = true` voor state én plan. Passphrase ≥ 16 tekens, via `TF_VAR_state_passphrase`.
- Geheimen alleen in `tofu/secrets.env` (vault-id `infra`). Nooit in een `.tf`-bestand, nooit op de commandline.
- `tofu` draait alleen op de mbp, met de hand. Geen Semaphore-template.
- OpenTofu maakt of verwijdert geen Tailscale-toestellen; aanmelden blijft bij `roles/tailscale` en NeoGate.
- Niets verandert in Tailscale vóór Task 6. Tot dan is terug gaan: `tofu/` weggooien en de R2-object verwijderen.
- Taal van commentaar en docs: Nederlands, zoals de rest van de repo.

## Review Focus

- `tofu/secrets.env` ontbreekt of de vault gaat niet open → `bin/tofu` moet stoppen met een duidelijke melding, niet `tofu` draaien zonder sleutels. Test in Task 1, stap 2 en 4.
- Passphrase leeg of verkeerd → OpenTofu moet weigeren, niet een leesbare state schrijven. Test in Task 3, stap 6.
- `policy.hujson` in git wijkt af van de console bij de import → het eerste `apply` zou stilletjes de console-regels overschrijven. Test: Task 4 legt de console vast en `plan` moet leeg zijn vóór Task 6.
- Een regel die iemand buitensluit of te veel geeft → Tailscale moet weigeren. Test: de `tests` in `policy.hujson` (Task 6, stap 3) plus een echt familie-account (Task 6, stap 5).
- Twee runs tegelijk → de tweede moet op het slot stuiten. Test in Task 5, stap 6.

---

### Task 1: Gereedschap — OpenTofu, `bin/tofu`, vault-controle, `.gitignore`

**Files:**
- Modify: `inventory/host_vars/mbp.yml` (lijst `macos_brew_packages_extra`)
- Modify: `bin/check-vaulted` (lijst `patterns`)
- Modify: `.gitignore`
- Create: `bin/tofu`

**Interfaces:**
- Produces: `bin/tofu <systeem> <tofu-argumenten...>` — draait `tofu -chdir=tofu/<systeem>` met de variabelen uit `tofu/secrets.env`. Stopt met exit 1 als het systeem, het bestand of een verplichte variabele ontbreekt.

- [ ] **Step 1: OpenTofu installeren en in de mbp-lijst zetten**

In `inventory/host_vars/mbp.yml`, in `macos_brew_packages_extra`, alfabetisch tussen `nvm` en `pnpm` (let op: `ollama` staat ertussen, dus na `ollama`):

```yaml
  - ollama
  - opentofu
  - pnpm
```

Run: `brew install opentofu && tofu version`
Expected: `OpenTofu v1.12.x` (of hoger).

- [ ] **Step 2: Test dat `bin/tofu` nog niet bestaat**

Run: `bin/tofu tailscale version; echo "exit=$?"`
Expected: `no such file or directory`, `exit=127`.

- [ ] **Step 3: `bin/tofu` schrijven**

Create `bin/tofu`:

```bash
#!/usr/bin/env bash
# OpenTofu met de geheimen uit de vault.
#
#     bin/tofu tailscale plan
#     bin/tofu tailscale apply
#
# De geheimen staan in tofu/secrets.env, versleuteld met de vault-id `infra`
# (zelfde wachtwoord als de rest). Dit script opent hem, zet elke regel als
# env-variabele en draait tofu in tofu/<systeem>. Zo staat er geen geheim in
# een .tf-bestand en niets in je shellgeschiedenis.
#
# Eén map en één state per systeem: een fout in tailscale raakt proxmox niet.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"

system="${1:-}"
if [[ -z "$system" ]]; then
	echo "gebruik: bin/tofu <systeem> <tofu-commando> ..." >&2
	echo "systemen: $(cd "$repo_root/tofu" 2>/dev/null && ls -d */ 2>/dev/null | tr -d / | tr '\n' ' ')" >&2
	exit 1
fi
shift

dir="$repo_root/tofu/$system"
if [[ ! -d "$dir" ]]; then
	echo "bin/tofu: geen map tofu/$system" >&2
	exit 1
fi

secrets_file="$repo_root/tofu/secrets.env"
if [[ ! -f "$secrets_file" ]]; then
	echo "bin/tofu: tofu/secrets.env ontbreekt. Zie het runbook 'Tailscale-regels aanpassen'." >&2
	exit 1
fi

# Eerst in een variabele, niet `source <(...)`: faalt ansible-vault, dan stopt
# set -e hier, in plaats van tofu te starten zonder sleutels.
secrets="$(cd "$repo_root" && ansible-vault view tofu/secrets.env)"
set -a
# shellcheck disable=SC1091
source /dev/stdin <<<"$secrets"
set +a

# Wat elk systeem nodig heeft: de state in R2 en de versleuteling. De sleutels
# van een provider controleert die provider zelf.
for var in AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_ENDPOINT_URL_S3 TF_VAR_state_passphrase; do
	if [[ -z "${!var:-}" ]]; then
		echo "bin/tofu: $var ontbreekt in tofu/secrets.env" >&2
		exit 1
	fi
done

exec tofu -chdir="$dir" "$@"
```

Run: `chmod +x bin/tofu`

- [ ] **Step 4: Testen zonder map en zonder geheimen**

Run: `bin/tofu; echo "exit=$?"`
Expected: `gebruik: bin/tofu <systeem> ...`, `exit=1`.

Run: `bin/tofu bestaatniet plan; echo "exit=$?"`
Expected: `bin/tofu: geen map tofu/bestaatniet`, `exit=1`.

Run: `mkdir -p tofu/tailscale && bin/tofu tailscale version; echo "exit=$?"`
Expected: `bin/tofu: tofu/secrets.env ontbreekt...`, `exit=1`. (`tofu/tailscale` blijft staan voor Task 3.)

- [ ] **Step 5: `tofu/secrets.env` in de vault-controle**

In `bin/check-vaulted`, in `patterns`, na `'roles/semaphore/files/config.json'`:

```bash
	# De geheimen van OpenTofu: R2-sleutel, state-passphrase, provider-clients.
	'tofu/secrets.env'
```

Test dat hij een leesbaar bestand weigert:

Run: `printf 'X=1\n' > tofu/secrets.env && bin/check-vaulted; echo "exit=$?"; rm tofu/secrets.env`
Expected: `PLAINTEXT  tofu/secrets.env`, `exit=1`.

Run: `bin/check-vaulted; echo "exit=$?"`
Expected: `exit=0`.

- [ ] **Step 6: `.gitignore`**

Onderaan `.gitignore`:

```gitignore
# OpenTofu: providers en werkbestanden. De state staat in R2, nooit hier.
# .terraform.lock.hcl hoort WEL in git.
.terraform/
*.tfstate
*.tfstate.*
*.tfplan
```

Run: `git check-ignore -v tofu/tailscale/.terraform/x tofu/tailscale/a.tfplan`
Expected: beide regels gematcht.

- [ ] **Step 7: Commit**

```bash
git add bin/tofu bin/check-vaulted .gitignore inventory/host_vars/mbp.yml
git commit -m "feat: bin/tofu wrapper for OpenTofu with vaulted secrets"
```

---

### Task 2: Handstappen in de consoles en `tofu/secrets.env` (Ruben)

Dit kan alleen Ruben: het gaat om aanmelden in Cloudflare en Tailscale en om geheimen. Een agent die dit plan uitvoert, stopt hier en vraagt Ruben om deze taak, en gaat pas verder als stap 5 groen is.

**Files:**
- Create: `tofu/secrets.env` (gevault, vault-id `infra`)

**Interfaces:**
- Produces: `tofu/secrets.env` met precies deze zes variabelen: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_ENDPOINT_URL_S3`, `TF_VAR_state_passphrase`, `TAILSCALE_OAUTH_CLIENT_ID`, `TAILSCALE_OAUTH_CLIENT_SECRET`.

- [ ] **Step 1: R2-bucket en sleutel (Cloudflare)**

| Scherm | Wat | Waarde |
| --- | --- | --- |
| Cloudflare → **R2 Object Storage** → **Create bucket** | naam | `homelab-tofu-state`, locatie Automatic |
| R2 → **Manage API tokens** → **Create User API token** | rechten | **Object Read & Write** |
| | bucket | **Apply to specific buckets only** → `homelab-tofu-state` |
| na aanmaken | noteer | Access Key ID, Secret Access Key, en het endpoint `https://<account-id>.r2.cloudflarestorage.com` |

- [ ] **Step 2: OAuth-client voor OpenTofu (Tailscale)**

| Scherm | Wat | Waarde |
| --- | --- | --- |
| Tailscale admin → **Settings** → **Trust credentials** (of **OAuth clients**) → **Generate** | beschrijving | `opentofu` |
| | scopes, allemaal **Write** | `policy_file`, `dns`, `devices:core`, `devices:routes` |
| | tags (gevraagd bij `devices:core`) | `tag:homelab` |
| na aanmaken | noteer | Client ID en Client secret |

De bestaande client (voor auth keys) blijft zoals hij is.

- [ ] **Step 3: Passphrase**

Een nieuwe passphrase van minstens 16 tekens, bv. uit de wachtwoordgenerator van Vaultwarden. Zet hem ook in Vaultwarden als "OpenTofu state passphrase": zonder is de state onleesbaar, ook voor jou.

- [ ] **Step 4: Het bestand aanmaken**

Run: `ansible-vault create --encrypt-vault-id infra tofu/secrets.env`

Inhoud (waarden invullen, geen aanhalingstekens nodig tenzij er een spatie in zit):

```bash
# R2 (Cloudflare): state van OpenTofu, token alleen voor bucket homelab-tofu-state
AWS_ACCESS_KEY_ID=
AWS_SECRET_ACCESS_KEY=
AWS_ENDPOINT_URL_S3=https://<account-id>.r2.cloudflarestorage.com
# Versleuteling van de state (ook in Vaultwarden)
TF_VAR_state_passphrase=
# Tailscale: OAuth-client "opentofu"
TAILSCALE_OAUTH_CLIENT_ID=
TAILSCALE_OAUTH_CLIENT_SECRET=
```

- [ ] **Step 5: Controleren**

Run: `bin/check-vaulted`
Expected: `encrypted  tofu/secrets.env`, exit 0.

Run: `bin/tofu tailscale version; echo "exit=$?"`
Expected: `OpenTofu v1.12.x`, `exit=0` (de map bestaat sinds Task 1, stap 4).

- [ ] **Step 6: Commit**

```bash
git add tofu/secrets.env
git commit -m "chore: vaulted secrets for OpenTofu"
```

---

### Task 3: Het project `tofu/tailscale` — versies, backend, versleuteling, provider

**Files:**
- Create: `tofu/tailscale/versions.tf`
- Create: `tofu/tailscale/backend.tf`
- Create: `tofu/tailscale/providers.tf`
- Create: `tofu/tailscale/.terraform.lock.hcl` (door `tofu`)
- Modify: `.githooks/pre-commit`

**Interfaces:**
- Consumes: `bin/tofu` (Task 1), `tofu/secrets.env` (Task 2).
- Produces: een geïnitialiseerd project; `var.state_passphrase` (string, sensitive); provider `tailscale` die zijn sleutels uit `TAILSCALE_OAUTH_CLIENT_*` leest.

- [ ] **Step 1: `versions.tf`**

```hcl
terraform {
  required_version = ">= 1.10"

  required_providers {
    tailscale = {
      source  = "tailscale/tailscale"
      version = "~> 0.29"
    }
  }
}
```

- [ ] **Step 2: `backend.tf`**

```hcl
# De state staat in Cloudflare R2, niet in git (geen slot, en hij bevat
# geheimen) en niet op de homelab (ligt pve01 plat, dan is de kaart ook weg).
#
# Het endpoint en de sleutel komen uit env (AWS_ENDPOINT_URL_S3,
# AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY), gezet door bin/tofu.
#
# R2 is geen AWS: de skip_*-regels zetten de AWS-controles uit die R2 niet
# kent, en skip_s3_checksum is nodig omdat R2 de nieuwe checksums van de
# AWS-SDK weigert.

variable "state_passphrase" {
  description = "Passphrase voor de versleuteling van state en plan. Uit tofu/secrets.env."
  type        = string
  sensitive   = true
}

terraform {
  backend "s3" {
    bucket = "homelab-tofu-state"
    key    = "tailscale/terraform.tfstate"
    region = "auto"

    use_lockfile = true

    use_path_style              = true
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_s3_checksum            = true
  }

  # Cloudflare ziet alleen versleutelde bytes. `enforced` weigert een
  # leesbare state of plan te schrijven, ook per ongeluk.
  encryption {
    key_provider "pbkdf2" "main" {
      passphrase = var.state_passphrase
    }

    method "aes_gcm" "main" {
      keys = key_provider.pbkdf2.main
    }

    state {
      method   = method.aes_gcm.main
      enforced = true
    }

    plan {
      method   = method.aes_gcm.main
      enforced = true
    }
  }
}
```

- [ ] **Step 3: `providers.tf`**

```hcl
# De sleutels komen uit TAILSCALE_OAUTH_CLIENT_ID en
# TAILSCALE_OAUTH_CLIENT_SECRET (bin/tofu). Het is de client "opentofu", niet
# die van roles/tailscale: twee clients, elk zo weinig mogelijk rechten.
provider "tailscale" {}
```

- [ ] **Step 4: Opmaak en init**

Run: `tofu fmt -check -recursive tofu/`
Expected: geen uitvoer, exit 0.

Run: `bin/tofu tailscale init`
Expected: `Successfully configured the backend "s3"!` en `OpenTofu has been successfully initialized!`.

- [ ] **Step 5: Lock-bestand voor mac én linux**

Zo werkt hetzelfde lock-bestand later ook in Semaphore (linux).

Run: `bin/tofu tailscale providers lock -platform=darwin_arm64 -platform=linux_amd64`
Expected: `Success! OpenTofu has updated the lock file.` en `tofu/tailscale/.terraform.lock.hcl` bestaat.

- [ ] **Step 6: Versleuteling afdwingen — test**

Eerst een lege state schrijven, zodat er iets in R2 staat:

Run: `bin/tofu tailscale apply -auto-approve`
Expected: `Apply complete! Resources: 0 added, 0 changed, 0 destroyed.`

In Cloudflare → R2 → `homelab-tofu-state` → `tailscale/terraform.tfstate` → **Download**, dan `head -c 300 ~/Downloads/terraform.tfstate`
Expected: JSON met `"encrypted_data"`, geen `"resources"` in leesbare vorm.

Met een verkeerde passphrase moet hij weigeren:

Run: `bin/tofu tailscale plan -var state_passphrase=verkeerd-maar-lang-genoeg; echo "exit=$?"`
Expected: fout over het ontsleutelen van de state, `exit=1`. (`-var` gaat voor op `TF_VAR_state_passphrase` uit `bin/tofu`.)

- [ ] **Step 7: Pre-commit: opmaak en geldigheid**

In `.githooks/pre-commit`, vóór `exit $fail`:

```bash
# 3. OpenTofu: opmaak en geldigheid, alleen voor een project waar iets van
#    gestaged is. Zonder backend (-backend=false), dus zonder R2 of geheimen;
#    de passphrase is een dummy, want validate leest geen state.
tofu_dirs="$(git diff --cached --name-only -- 'tofu/*/*' | cut -d/ -f1-2 | sort -u)"
for d in $tofu_dirs; do
	[[ -d "$d" ]] || continue
	if ! tofu fmt -check "$d" >/dev/null; then
		echo "pre-commit: $d is niet opgemaakt. Draai: tofu fmt $d" >&2
		fail=1
	fi
	if ! TF_VAR_state_passphrase=pre-commit-validate-only \
		tofu -chdir="$d" init -backend=false -input=false >/dev/null 2>&1 ||
		! TF_VAR_state_passphrase=pre-commit-validate-only \
		tofu -chdir="$d" validate -no-color >&2; then
		echo "pre-commit: $d is niet geldig. Draai: tofu -chdir=$d validate" >&2
		fail=1
	fi
done
```

Test dat hij een slecht opgemaakt bestand weigert:

Run: `printf 'locals {\nx=1\n}\n' > tofu/tailscale/zz.tf && git add tofu/tailscale/zz.tf && .githooks/pre-commit; echo "exit=$?"`
Expected: `pre-commit: tofu/tailscale is niet opgemaakt`, `exit=1`.

Run: `git rm -q --cached tofu/tailscale/zz.tf && rm tofu/tailscale/zz.tf`

Daarna, met de echte bestanden gestaged:

Run: `git add tofu/tailscale .githooks/pre-commit && .githooks/pre-commit; echo "exit=$?"`
Expected: `exit=0`.

Run: `bin/tofu tailscale init` (zet de backend terug na `init -backend=false` van de hook)
Expected: `OpenTofu has been successfully initialized!`.

- [ ] **Step 8: Commit**

```bash
git add tofu/tailscale/versions.tf tofu/tailscale/backend.tf tofu/tailscale/providers.tf tofu/tailscale/.terraform.lock.hcl .githooks/pre-commit
git commit -m "feat: tofu/tailscale project with encrypted R2 state"
```

---

### Task 4: De policy vastleggen zoals hij in de console staat, en importeren

**Files:**
- Modify: `files/tailscale/policy.hujson` (wordt precies de console)
- Create: `tofu/tailscale/policy.tf`
- Create (tijdelijk): `tofu/tailscale/console.tf`

**Interfaces:**
- Consumes: het project uit Task 3.
- Produces: `tailscale_acl.this` in de state, met `acl = file("${path.module}/../../files/tailscale/policy.hujson")`; een lege `plan` voor die resource.

- [ ] **Step 1: De console uitlezen**

Create `tofu/tailscale/console.tf` (tijdelijk, gaat weg in stap 4):

```hcl
# TIJDELIJK: leest de policy zoals hij nu in de console staat, zodat
# policy.hujson er vóór de import precies gelijk aan wordt.
data "tailscale_acl" "console" {}

output "console_policy" {
  value = data.tailscale_acl.console.hujson
}
```

Run: `bin/tofu tailscale apply -auto-approve`
Expected: `Apply complete! Resources: 0 added...` en een output `console_policy`.

- [ ] **Step 2: De repo-versie bewaren en de console-versie neerzetten**

Run:
```bash
scratch="$(mktemp -d)"
cp files/tailscale/policy.hujson "$scratch/policy.repo.hujson"
bin/tofu tailscale output -raw console_policy > files/tailscale/policy.hujson
echo "$scratch"
git diff --stat files/tailscale/policy.hujson
```

Expected: een pad in `$scratch` (noteer het, Task 6 heeft het nodig) en een diff. Lees de diff helemaal: dat is precies wat de console mist of anders heeft dan de repo (verwacht, uit TODO A2: de `mac-mini:32400`-regel, de test met Maarten, funnel alleen voor jou). Iets anders dan die punten? Noteer het voor Task 6.

- [ ] **Step 3: `policy.tf` met import**

Create `tofu/tailscale/policy.tf`:

```hcl
# De toegangsregels van de tailnet. files/tailscale/policy.hujson is de bron;
# een wijziging gaat via `bin/tofu tailscale apply`. Tailscale draait bij elke
# apply de `tests` uit dat bestand, en weigert als er een faalt.
#
# Commentaar telt mee: de provider bewaart HuJSON zoals het is, dus een
# gewijzigd commentaar is ook een (onschuldige) wijziging in het plan.
resource "tailscale_acl" "this" {
  acl = file("${path.module}/../../files/tailscale/policy.hujson")
}

import {
  to = tailscale_acl.this
  id = "acl"
}
```

Run: `bin/tofu tailscale plan`
Expected: `Plan: 1 to import, 0 to add, 0 to change, 0 to destroy.` Staat er `update in-place` bij `tailscale_acl.this`: dan is `policy.hujson` niet gelijk aan de console. Terug naar stap 2; niet verder.

- [ ] **Step 4: Importeren en de tijdelijke lezer weghalen**

Run: `bin/tofu tailscale apply`
Expected: bij de vraag, alleen `1 to import`; `yes`. Daarna `Apply complete! Resources: 1 imported, 0 added, 0 changed, 0 destroyed.`

Run: `rm tofu/tailscale/console.tf` en haal het `import`-blok uit `policy.tf` (alleen het `resource`-blok en het commentaar blijven).

Run: `bin/tofu tailscale plan`
Expected: `No changes. Your infrastructure matches the configuration.`

- [ ] **Step 5: Commit**

```bash
git add files/tailscale/policy.hujson tofu/tailscale/policy.tf
git commit -m "feat: tailscale policy imported into OpenTofu, file equals console"
```

---

### Task 5: DNS, de route van ct 108 en de tags importeren — leeg plan

**Files:**
- Create: `tofu/tailscale/dns.tf`
- Create: `tofu/tailscale/devices.tf`
- Create (tijdelijk): `tofu/tailscale/imports.tf`

**Interfaces:**
- Consumes: het project uit Task 3.
- Produces: `tailscale_dns_configuration.this`, `tailscale_device_subnet_routes.tailscale`, `tailscale_device_tags.tailscale`, `tailscale_device_tags.adguard` in de state; data sources `data.tailscale_device.tailscale` en `data.tailscale_device.adguard`.

- [ ] **Step 1: De namen van de nodes nakijken**

Run: `tailscale status | grep -E ' (tailscale|adguard) '`
Expected: twee regels. Hun volledige naam is `<naam>.brill-atlas.ts.net`. Heet een node anders (bv. `tailscale-1`), gebruik die naam hieronder.

- [ ] **Step 2: `devices.tf` en `dns.tf` met wat we verwachten**

Create `tofu/tailscale/devices.tf`:

```hcl
# De nodes zelf maakt of verwijdert OpenTofu niet: aanmelden doet
# roles/tailscale. Hier alleen wat de console erop zet: route en tags.

data "tailscale_device" "tailscale" {
  name = "tailscale.brill-atlas.ts.net"
}

data "tailscale_device" "adguard" {
  name = "adguard.brill-atlas.ts.net"
}

# ct 108 biedt het thuisnetwerk aan (--advertise-routes in roles/tailscale).
# Aanbieden doet de node, goedkeuren gebeurt hier. Een route die hier niet
# staat, wordt bij de volgende apply afgekeurd.
resource "tailscale_device_subnet_routes" "tailscale" {
  device_id = data.tailscale_device.tailscale.node_id
  routes    = ["192.168.0.0/24"]
}

resource "tailscale_device_tags" "tailscale" {
  device_id = data.tailscale_device.tailscale.node_id
  tags      = ["tag:homelab"]
}

# adguard: DNS voor de hele tailnet, en de policy geeft iedereen :53 op
# tag:homelab. Zonder deze tag lost *.neodata.be onderweg niet op.
resource "tailscale_device_tags" "adguard" {
  device_id = data.tailscale_device.adguard.node_id
  tags      = ["tag:homelab"]
}
```

Create `tofu/tailscale/dns.tf`:

```hcl
# adguard (ct 107) is de DNS van de hele tailnet, via zijn 100.x-adres: een
# LAN-adres werkt alleen voor wie de subnet-route aanneemt, en dat doet hier
# geen enkel toestel. Zie homelab/netwerk.mdx.
resource "tailscale_dns_configuration" "this" {
  magic_dns          = true
  override_local_dns = true

  nameservers {
    address = "100.84.46.18"
  }
}
```

Create `tofu/tailscale/imports.tf` (tijdelijk):

```hcl
# TIJDELIJK: neemt de bestaande instellingen over. Weg zodra plan leeg is.
import {
  to = tailscale_dns_configuration.this
  id = "dns_configuration"
}

import {
  to = tailscale_device_subnet_routes.tailscale
  id = data.tailscale_device.tailscale.node_id
}

import {
  to = tailscale_device_tags.tailscale
  id = data.tailscale_device.tailscale.node_id
}

import {
  to = tailscale_device_tags.adguard
  id = data.tailscale_device.adguard.node_id
}
```

- [ ] **Step 3: Plan lezen en de code gelijkzetten met de werkelijkheid**

Run: `bin/tofu tailscale plan`
Expected: `4 to import`. Staat er ook `to change` bij een van de vier, dan wijkt de code af van wat er echt staat. De werkelijkheid wint hier: pas de `.tf` aan tot het plan alleen `4 to import, 0 to add, 0 to change, 0 to destroy` zegt. Typische afwijkingen:

| Plan zegt | Pas aan |
| --- | --- |
| `search_paths` erbij in de state | voeg `search_paths = [...]` toe met die waarden |
| `split_dns` erbij | voeg het `split_dns`-blok toe zoals in de state |
| `override_local_dns = false` | zet het op `false` |
| routes met ook `0.0.0.0/0`, `::/0` | ct 108 is ook exit node: voeg ze toe aan `routes` |
| een extra tag | voeg hem toe aan `tags` |

Faalt het plan met "import id must be known" bij de devices: vervang die drie `id`'s door de letterlijke node-ID uit `echo 'data.tailscale_device.tailscale.node_id' | bin/tofu tailscale console` (en idem voor `adguard`).

- [ ] **Step 4: Importeren**

Run: `bin/tofu tailscale apply`
Expected: `Resources: 4 imported, 0 added, 0 changed, 0 destroyed.`

- [ ] **Step 5: Tijdelijke imports weg, plan leeg**

Run: `rm tofu/tailscale/imports.tf && bin/tofu tailscale plan`
Expected: `No changes. Your infrastructure matches the configuration.`

- [ ] **Step 6: Het slot testen**

Terminal 1: `bin/tofu tailscale apply` en laat hem op de `yes`-vraag staan.
Terminal 2: `bin/tofu tailscale plan -lock-timeout=5s; echo "exit=$?"`
Expected in terminal 2: `Error acquiring the state lock`, `exit=1`. Terminal 1: `no`.

- [ ] **Step 7: Commit**

```bash
git add tofu/tailscale/dns.tf tofu/tailscale/devices.tf
git commit -m "feat: tailscale dns, subnet route and tags imported into OpenTofu"
```

---

### Task 6: Eerste echte wijziging — de A2-regels, en de console dicht

**Files:**
- Modify: `files/tailscale/policy.hujson`

**Interfaces:**
- Consumes: `$scratch/policy.repo.hujson` uit Task 4, stap 2.
- Produces: een policy in Tailscale gelijk aan de repo-versie van vóór Task 4.

- [ ] **Step 1: De repo-versie terugzetten**

Run: `cp "$scratch/policy.repo.hujson" files/tailscale/policy.hujson` (of `git show HEAD~3:files/tailscale/policy.hujson > files/tailscale/policy.hujson` als `$scratch` weg is — controleer met `git log --oneline -- files/tailscale/policy.hujson` welke commit de versie van vóór de import is).

- [ ] **Step 2: De header aanpassen**

In `files/tailscale/policy.hujson`, de eerste zes regels vervangen door:

```hujson
// De toegangsregels van de tailnet (brill-atlas.ts.net).
//
// DIT IS DE BRON. OpenTofu zet dit bestand in Tailscale:
//
//     bin/tofu tailscale plan     # wat zou er veranderen
//     bin/tofu tailscale apply    # doen
//
// In de console kan je de regels niet meer aanpassen ("edits beperken").
// Tailscale draait bij elke apply de `tests` onderaan, en weigert als er een
// faalt. Zie het runbook "Tailscale-regels aanpassen".
```

De rest van het commentaar ("Waarom deze regels: ...") blijft.

- [ ] **Step 3: Plan en apply**

Run: `bin/tofu tailscale plan`
Expected: `1 to change`, alleen `tailscale_acl.this`. De diff toont de header, en de punten uit Task 4, stap 2 (`mac-mini:32400`, de test met Maarten, funnel alleen voor jou). Niets anders.

Run: `bin/tofu tailscale apply`
Expected: `Apply complete! Resources: 0 added, 1 changed, 0 destroyed.` Faalt hij met een `test failed`: de regels en de tests spreken elkaar tegen; lees welke test, pas het bestand aan, opnieuw.

- [ ] **Step 4: Plan leeg**

Run: `bin/tofu tailscale plan`
Expected: `No changes.`

- [ ] **Step 5: Met een echt familie-account testen (Ruben)**

Op een toestel met een familie-account op de tailnet (bv. dat van Maarten):

| Test | Verwacht |
| --- | --- |
| `https://plex.neodata.be` of de Plex-app | werkt |
| `https://photos.neodata.be` | werkt |
| `http://100.74.124.12:32400/web` | werkt |
| `ssh 100.74.124.12` | time-out |
| `https://192.168.0.10:8006` | time-out |

- [ ] **Step 6: De console dichtzetten (Ruben)**

| Scherm | Wat | Waarde |
| --- | --- | --- |
| Tailscale admin → **Access controls** → **Policy file management** (of **Settings** → **Policy file**) | **Prevent edits in the admin console** | aan |

Controleren: in **Access controls** kan je de editor niet meer aanpassen, en `bin/tofu tailscale plan` zegt nog steeds `No changes.`

- [ ] **Step 7: Commit**

```bash
git add files/tailscale/policy.hujson
git commit -m "feat: tailscale policy from git: plex for family, funnel only for me"
```

---

### Task 7: Docs en TODO

**Files:**
- Modify: `docs-site/content/runbooks/toegang/toestellen.mdx` (nieuwe `##`-sectie + rij in de geval-tabel + 1-2 regels in "Goed om te weten")
- Modify: `docs-site/content/runbooks/toegang/index.mdx` (rij in "Welk geval ben jij?")
- Modify: `docs-site/content/homelab/netwerk.mdx:180-195` (de console is niet meer de bron)
- Modify: `TODO.md` (A2, B)

- [ ] **Step 1: Sectie "Tailscale-regels aanpassen" in `toestellen.mdx`**

Rij in de geval-tabel bovenaan, na de rij "Iemand moet aan het **hele thuisnetwerk**":

```markdown
| Je wil **veranderen wie waar mag** op de tailnet | Maarten moet ook bij Audiobookshelf, iemand mag niet meer bij Plex | [Tailscale-regels aanpassen](#tailscale-regels-aanpassen) |
```

Nieuwe sectie, vóór `## Goed om te weten`:

````mdx
## Tailscale-regels aanpassen

De regels staan in `files/tailscale/policy.hujson` en OpenTofu zet ze in
Tailscale. In de console kan je ze niet meer aanpassen.

<Steps>

#### Eenmalig op een nieuwe computer

`brew install opentofu`, de vault-wachtwoorden zoals in de README, en dan:

```bash
bin/tofu tailscale init
```

#### Pas het bestand aan

`files/tailscale/policy.hujson`. Voeg bij een nieuwe regel ook een regel in
`tests` toe: wie mag erbij, wie niet. Zo weigert Tailscale een fout.

#### Kijk wat er zou veranderen

```bash
bin/tofu tailscale plan
```

Alleen `tailscale_acl.this` mag veranderen. Iets anders? Stop en kijk waarom.

#### Doen

```bash
bin/tofu tailscale apply
```

Faalt het met `test failed`: een regel en een test spreken elkaar tegen.

#### Commit en push

</Steps>

Ook DNS (de nameserver van de tailnet), de route van ct 108 en de tags van de
nodes staan zo in `tofu/tailscale/`. Zelfde stappen.
````

In `## Goed om te weten` van dezelfde pagina:

```markdown
- **Waarom OpenTofu en niet de console?** Git beslist: elke wijziging heeft
  een diff en een reden, en `plan` toont vooraf wat er gebeurt. De state staat
  versleuteld in Cloudflare R2, niet op de homelab: ligt pve01 plat, dan weet
  OpenTofu nog wat er moet staan. De passphrase staat in Vaultwarden.
- **Noodgeval zonder laptop?** Zet in de Tailscale-console "Prevent edits in
  the admin console" even uit, pas aan, en zet daarna `policy.hujson` gelijk
  tot `bin/tofu tailscale plan` leeg is.
```

- [ ] **Step 2: Rij in `runbooks/toegang/index.mdx`**

Na de rij met "Tailscale-sleutel":

```markdown
| Je wil **veranderen wie waar mag** op de tailnet | Maarten moet ook bij Audiobookshelf | [Tailscale-regels aanpassen](/runbooks/toegang/toestellen/#tailscale-regels-aanpassen) |
```

- [ ] **Step 3: `homelab/netwerk.mdx`**

In "Wie mag wat via Tailscale": "(Access controls in de console)" → "(`files/tailscale/policy.hujson`)", een rij voor Plex toevoegen:

```markdown
| iedereen anders op de tailnet | de Mac mini `100.74.124.12`, poort 32400 | Plex rechtstreeks, voor de Tailscale-boxen bij de tv's |
```

En de alinea "De console is de bron. ..." vervangen door:

```markdown
Git is de bron. OpenTofu zet `files/tailscale/policy.hujson` in Tailscale, en
de console is dicht voor wijzigingen. Hoe: [Tailscale-regels
aanpassen](/runbooks/toegang/toestellen/#tailscale-regels-aanpassen).
```

- [ ] **Step 4: TODO.md**

- A2: de punten "nodeAttrs → funnel" en "Eenmalig nakijken dat de console gelijk is aan `policy.hujson`" afvinken, en de `mac-mini:32400`-regel en de familie-test uit het eerste punt (gedaan in Task 6).
- B: "State in een bucket buiten het huis" met zijn drie subpunten, en "Tailscale eerst" met zijn drie subpunten afvinken. Onder B een regel: "Deel 1 (basis + Tailscale) klaar op <datum>; spec en plan in `docs/superpowers/`. Volgende: deel 2, Proxmox."

- [ ] **Step 5: Docs bouwen**

Run: `cd docs-site && npm run build`
Expected: build zonder fouten (geen gebroken MDX).

- [ ] **Step 6: Commit en push**

```bash
git add docs-site/content TODO.md
git commit -m "docs: tailscale rules via OpenTofu"
git push
```

Daarna `ansible-playbook playbooks/docs.yml` zodat docs.neodata.be de nieuwe versie toont.
