# De toegangsregels van de tailnet. files/tailscale/policy.hujson is de bron;
# een wijziging gaat via `bin/tofu tailscale apply`. Tailscale draait bij elke
# apply de `tests` uit dat bestand, en weigert als er een faalt.
#
# Commentaar telt mee: de provider bewaart HuJSON zoals het is, dus een
# gewijzigd commentaar is ook een (onschuldige) wijziging in het plan.
locals {
  policy = file("${path.module}/../../files/tailscale/policy.hujson")

  # De policy noemt deze nodes bij hun 100.x-adres. Meldt er een zich opnieuw
  # aan, dan krijgt hij een ander adres en wijzen de regels in het niets.
  policy_pinned_nodes = {
    "mac-mini" = data.tailscale_device.mac_mini
    "adguard"  = data.tailscale_device.adguard
  }
}

resource "tailscale_acl" "this" {
  acl = local.policy

  lifecycle {
    precondition {
      condition = alltrue([
        for d in values(local.policy_pinned_nodes) :
        strcontains(local.policy, one([for a in d.addresses : a if strcontains(a, ".")]))
      ])
      error_message = "Een node heeft een ander 100.x-adres dan in policy.hujson staat: ${join(", ", [for n, d in local.policy_pinned_nodes : "${n} = ${one([for a in d.addresses : a if strcontains(a, ".")])}"])}. Pas policy.hujson (hosts en tests), dns.tf en de docs aan."
    }
  }
}
