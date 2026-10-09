# De OIDC-clients: welke apps via Pocket ID mogen inloggen. Gebruikers,
# groepen en passkeys blijven in de UI; dit is enkel wat een app nodig heeft.
#
# Een vaste client_id, zodat hij in de .env van de app kan staan zonder eerst
# hier te kijken. Het secret geeft Pocket ID alleen bij het aanmaken: het staat
# in de (versleutelde) state en je haalt het op met
#
#     bin/tofu pocketid output -raw outline_client_secret
#
# Vervang je de client (taint, of een wijziging die hem opnieuw maakt), dan is
# er een nieuw secret en moet de .env van de app mee.

resource "pocketid_client" "outline" {
  name       = "Outline"
  client_id  = "outline"
  launch_url = "https://wiki.neodata.be"

  callback_urls = ["https://wiki.neodata.be/auth/oidc.callback"]

  is_public    = false
  pkce_enabled = true

  allowed_user_groups = [
    pocketid_group.gezin.id,
    pocketid_group.familie.id,
  ]
}

output "outline_client_secret" {
  value     = pocketid_client.outline.client_secret
  sensitive = true
}

# Immich koppelt een bestaand account op mailadres. De config staat in de
# containers-repo (stacks/media, configs.immich); het secret in media.env
# als IMMICH_OIDC_CLIENT_SECRET.
resource "pocketid_client" "immich" {
  name       = "Immich"
  client_id  = "immich"
  launch_url = "https://photos.neodata.be"

  callback_urls = [
    "https://photos.neodata.be/auth/login",
    "https://photos.neodata.be/user-settings",
    # De app op iOS en Android.
    "app.immich:///oauth-callback",
  ]

  is_public    = false
  pkce_enabled = true

  allowed_user_groups = [
    pocketid_group.gezin.id,
    pocketid_group.familie.id,
  ]
}

output "immich_client_secret" {
  value     = pocketid_client.immich.client_secret
  sensitive = true
}

# Audiobookshelf heeft geen configbestand: roles/audiobookshelf zet zijn
# OIDC-instellingen via de API. Het secret staat in host_vars/docker/vault.yml
# als vault_audiobookshelf_oidc_client_secret.
resource "pocketid_client" "audiobookshelf" {
  name       = "Audiobookshelf"
  client_id  = "audiobookshelf"
  launch_url = "https://audiobooks.neodata.be"

  callback_urls = [
    "https://audiobooks.neodata.be/auth/openid/callback",
    # De app op iOS en Android gaat via deze omweg terug naar de app.
    "https://audiobooks.neodata.be/auth/openid/mobile-redirect",
  ]

  is_public    = false
  pkce_enabled = true

  allowed_user_groups = [
    pocketid_group.gezin.id,
    pocketid_group.familie.id,
  ]
}

output "audiobookshelf_client_secret" {
  value     = pocketid_client.audiobookshelf.client_secret
  sensitive = true
}

# Grimmory: een public client met PKCE, dus geen secret. Zijn instellingen
# staan alleen in zijn eigen database; je zet ze met de hand, zie
# docs-site/content/homelab/diensten/books.mdx. Bestaande accounts koppelt hij op
# gebruikersnaam, hoofdlettergevoelig.
resource "pocketid_client" "grimmory" {
  name       = "Grimmory"
  client_id  = "grimmory"
  launch_url = "https://books.neodata.be"

  callback_urls = ["https://books.neodata.be/oauth2-callback"]

  is_public    = true
  pkce_enabled = true

  allowed_user_groups = [
    pocketid_group.gezin.id,
    pocketid_group.familie.id,
  ]
}

# Home Assistant kan zelf geen OIDC: de integratie auth_oidc (HACS,
# github.com/christiaangoossens/hass-oidc-auth) doet het. Een public client
# met PKCE, dus geen secret. De config staat in de repo
# home-assistant-config, onder auth_oidc in configuration.yaml. `admin` wordt
# admin in Home Assistant, `gezin` gewone gebruiker. Een bestaand account
# koppelt hij op gebruikersnaam.
resource "pocketid_client" "homeassistant" {
  name       = "Home Assistant"
  client_id  = "homeassistant"
  launch_url = "https://haos.neodata.be"

  callback_urls = ["https://haos.neodata.be/auth/oidc/callback"]

  is_public    = true
  pkce_enabled = true

  allowed_user_groups = [
    pocketid_group.admin.id,
    pocketid_group.gezin.id,
  ]
}

# --- Beheer: alleen `admin` ---

# Grafana: de instellingen staan als GF_*-variabelen in de compose van de
# monitoring-stack-repo; het secret in monitoring.env als
# GRAFANA_OIDC_CLIENT_SECRET. De rol volgt uit de groep: `admin` wordt
# GrafanaAdmin. De lokale `admin` blijft de noodtoegang.
resource "pocketid_client" "grafana" {
  name       = "Grafana"
  client_id  = "grafana"
  launch_url = "https://monitoring.neodata.be"

  callback_urls = ["https://monitoring.neodata.be/login/generic_oauth"]

  is_public    = false
  pkce_enabled = true

  allowed_user_groups = [pocketid_group.admin.id]
}

output "grafana_client_secret" {
  value     = pocketid_client.grafana.client_secret
  sensitive = true
}

# Semaphore: de instellingen staan in roles/semaphore/files/config.json
# (versleuteld), onder oidc_providers.pocketid, samen met het secret.
# Semaphore stuurt geen PKCE mee, dus die staat hier uit; anders weigert
# Pocket ID de login. Het koppelt op mailadres en weigert een lokaal account
# met hetzelfde adres: de lokale `admin` heeft daarom een eigen adres.
resource "pocketid_client" "semaphore" {
  name       = "Semaphore"
  client_id  = "semaphore"
  launch_url = "https://semaphore.neodata.be"

  callback_urls = ["https://semaphore.neodata.be/api/auth/oidc/pocketid/redirect"]

  is_public                 = false
  pkce_enabled              = false
  requires_reauthentication = true

  allowed_user_groups = [pocketid_group.admin.id]
}

output "semaphore_client_secret" {
  value     = pocketid_client.semaphore.client_secret
  sensitive = true
}

# Proxmox VE: de realm `pocketid` staat in tofu/proxmox/oidc.tf. Het secret
# gaat daarheen via TF_VAR_pocketid_proxmox_client_secret in
# tofu/secrets.env. Proxmox stuurt je terug naar het adres waarop je hem
# opende, dus beide staan hier: via Caddy en rechtstreeks.
resource "pocketid_client" "proxmox" {
  name       = "Proxmox VE"
  client_id  = "proxmox"
  launch_url = "https://proxmox.neodata.be"

  callback_urls = [
    "https://proxmox.neodata.be",
    "https://192.168.0.10:8006",
  ]

  is_public                 = false
  pkce_enabled              = false
  requires_reauthentication = true

  allowed_user_groups = [pocketid_group.admin.id]
}

output "proxmox_client_secret" {
  value     = pocketid_client.proxmox.client_secret
  sensitive = true
}

# Proxmox Backup Server: realm `pocketid` via roles/pbs (tasks/oidc.yml); het
# secret in host_vars/pbs/vault.yml als vault_pbs_oidc_client_secret. PBS
# leest geen groepen: wie admin is, staat bij naam in pbs_oidc.admins.
resource "pocketid_client" "pbs" {
  name       = "Proxmox Backup Server"
  client_id  = "pbs"
  launch_url = "https://backup.neodata.be"

  callback_urls = [
    "https://backup.neodata.be",
    "https://192.168.0.181:8007",
  ]

  is_public                 = false
  pkce_enabled              = false
  requires_reauthentication = true

  allowed_user_groups = [pocketid_group.admin.id]
}

output "pbs_client_secret" {
  value     = pocketid_client.pbs.client_secret
  sensitive = true
}

# Arcane: OIDC_* in de compose van de containers-repo (stacks/arcane), het
# secret in arcane.env als ARCANE_OIDC_CLIENT_SECRET. Arcane stuurt PKCE mee;
# de groep `admin` wordt admin in Arcane via OIDC_ROLE_MAPPINGS.
resource "pocketid_client" "arcane" {
  name       = "Arcane"
  client_id  = "arcane"
  launch_url = "https://arcane.neodata.be"

  callback_urls = ["https://arcane.neodata.be/auth/oidc/callback"]

  is_public                 = false
  pkce_enabled              = true
  requires_reauthentication = true

  allowed_user_groups = [pocketid_group.admin.id]
}

output "arcane_client_secret" {
  value     = pocketid_client.arcane.client_secret
  sensitive = true
}

# --- Forward-auth ---

# oauth2-proxy op de Caddy-container: de login voor apps zonder eigen OIDC.
# Welke groep per app mag, zegt Caddy per site (`auth:` in caddy_sites);
# hier staan dus alle groepen die ooit ergens binnen mogen. Het secret in
# host_vars/caddy/vault.yml als vault_oauth2_proxy_client_secret.
resource "pocketid_client" "oauth2_proxy" {
  name       = "Forward-auth (oauth2-proxy)"
  client_id  = "oauth2-proxy"
  launch_url = "https://home.neodata.be"

  callback_urls = ["https://auth.neodata.be/oauth2/callback"]

  is_public    = false
  pkce_enabled = true

  allowed_user_groups = [
    pocketid_group.admin.id,
    pocketid_group.gezin.id,
    pocketid_group.gast.id,
  ]
}

output "oauth2_proxy_client_secret" {
  value     = pocketid_client.oauth2_proxy.client_secret
  sensitive = true
}

# Shelfmark: AUTH_METHOD en OIDC_* in de compose van de containers-repo
# (stacks/media), het secret in media.env als SHELFMARK_OIDC_CLIENT_SECRET.
# PKCE doet hij zelf. Admin wordt wie in de groep `admin` zit.
resource "pocketid_client" "shelfmark" {
  name       = "Shelfmark"
  client_id  = "shelfmark"
  launch_url = "https://shelfmark.neodata.be"

  callback_urls = ["https://shelfmark.neodata.be/api/auth/oidc/callback"]

  is_public    = false
  pkce_enabled = true

  allowed_user_groups = [pocketid_group.gezin.id]
}

output "shelfmark_client_secret" {
  value     = pocketid_client.shelfmark.client_secret
  sensitive = true
}

# Vaultwarden: SSO_* in de compose van de containers-repo (stacks/vaultwarden),
# het secret in vaultwarden.env als VW_SSO_CLIENT_SECRET. Pocket ID vervangt
# alleen het inloggen: de kluis opent nog altijd met het hoofdwachtwoord.
resource "pocketid_client" "vaultwarden" {
  name       = "Vaultwarden"
  client_id  = "vaultwarden"
  launch_url = "https://vault.neodata.be"

  callback_urls = ["https://vault.neodata.be/identity/connect/oidc-signin"]

  is_public    = false
  pkce_enabled = true

  allowed_user_groups = [pocketid_group.gezin.id]
}

output "vaultwarden_client_secret" {
  value     = pocketid_client.vaultwarden.client_secret
  sensitive = true
}

# RomM: OIDC_* in de compose van de containers-repo (stacks/romm), het secret
# in romm.env als ROMM_OIDC_CLIENT_SECRET. RomM leest de groups-claim: `admin`
# wordt admin in RomM, de rest een gewone gebruiker. RomM stuurt altijd PKCE.
resource "pocketid_client" "romm" {
  name       = "RomM"
  client_id  = "romm"
  launch_url = "https://games.neodata.be"

  callback_urls = ["https://games.neodata.be/api/oauth/openid"]

  is_public    = false
  pkce_enabled = true

  allowed_user_groups = [
    pocketid_group.admin.id,
    pocketid_group.gezin.id,
    pocketid_group.familie.id,
    pocketid_group.gast.id,
  ]
}

output "romm_client_secret" {
  value     = pocketid_client.romm.client_secret
  sensitive = true
}
