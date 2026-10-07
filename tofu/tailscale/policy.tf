# De toegangsregels van de tailnet. files/tailscale/policy.hujson is de bron;
# een wijziging gaat via `bin/tofu tailscale apply`. Tailscale draait bij elke
# apply de `tests` uit dat bestand, en weigert als er een faalt.
#
# Commentaar telt mee: de provider bewaart HuJSON zoals het is, dus een
# gewijzigd commentaar is ook een (onschuldige) wijziging in het plan.
locals {
  # De policy en dns.tf noemen deze nodes bij hun 100.x-adres. Dat komt van
  # het toestel zelf en staat nergens met de hand: meldt er een zich opnieuw
  # aan, dan toont het volgende plan (en dus tofu-drift.yml) het nieuwe adres
  # in de policy en de DNS, en zet apply het recht.
  tailnet_ipv4 = {
    for name, d in {
      mac_mini = data.tailscale_device.mac_mini
      adguard  = data.tailscale_device.adguard
    } : name => one([for a in d.addresses : a if strcontains(a, ".")])
  }

  policy = templatefile("${path.module}/../../files/tailscale/policy.hujson", local.tailnet_ipv4)
}

resource "tailscale_acl" "this" {
  acl = local.policy
}
