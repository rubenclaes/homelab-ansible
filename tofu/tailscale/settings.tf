# De instellingen van de tailnet zelf, die anders alleen in de console staan.
# Het `import`-blok neemt de bestaande over: niets wordt nieuw gemaakt.
# Wat hier niet staat, blijft zoals het is. Een andere waarde dan nu vraagt de
# scope `feature_settings` op de OAuth-client `opentofu`, en die heeft hij niet.
import {
  to = tailscale_tailnet_settings.this
  id = "tailnet_settings"
}

resource "tailscale_tailnet_settings" "this" {
  # "Prevent edits in the admin console": de policy komt alleen uit git.
  # Noodgeval: zie "Noodgeval zonder laptop" op de docs-pagina OpenTofu.
  acls_externally_managed_on = true
  acls_external_link         = "https://github.com/rubenclaes/homelab-ansible/blob/master/files/tailscale/policy.hujson"

  # Nieuwe toestellen werken meteen. Een member mag alleen bij Caddy, DNS en
  # Plex; een goedkeuring per Apple TV zou de familie laten wachten op een
  # klik waar je geen melding van krijgt.
  devices_approval_on = false
}
