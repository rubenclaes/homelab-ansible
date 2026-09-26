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
# docs-site/content/docker/grimmory.mdx. Bestaande accounts koppelt hij op
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
