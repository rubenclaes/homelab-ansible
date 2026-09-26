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
}

output "outline_client_secret" {
  value     = pocketid_client.outline.client_secret
  sensitive = true
}
