# De nodes zelf maakt of verwijdert OpenTofu niet: aanmelden doet
# roles/tailscale. Hier alleen wat de console erop zet: route, tags en het
# verlopen van de sleutel.

data "tailscale_device" "tailscale" {
  name = "tailscale.brill-atlas.ts.net"
}

data "tailscale_device" "adguard" {
  name = "adguard.brill-atlas.ts.net"
}

# Optioneel, en daarom een lijst en geen `tailscale_device`: tussen het wissen
# van een oude Mini en het aanmelden van de nieuwe staat er geen mac-mini op
# de tailnet. Een `tailscale_device` faalt dan, en met hem het hele plan
# (policy, DNS, settings) en dus elke ochtend tofu-drift.yml.
data "tailscale_devices" "mac_mini" {
  name_prefix = "mac-mini."
}

locals {
  mac_mini = one([for d in data.tailscale_devices.mac_mini.devices : d if d.name == "mac-mini.brill-atlas.ts.net"])

  # Het adres dat de Mini in de console vast krijgt (runbook "Een nieuwe Mac
  # mini"): Plex en de familie kennen hem zo. Ook zolang hij er niet is,
  # zodat de regels in de policy geldig blijven.
  mac_mini_ipv4_reserved = "100.74.124.12"
}

# ct 108 biedt het thuisnetwerk aan (--advertise-routes in roles/tailscale).
# Aanbieden doet de node, goedkeuren gebeurt hier. Een route die hier niet
# staat, wordt bij de volgende apply afgekeurd. Na een herbouw is het een
# nieuwe node: `bin/tofu tailscale apply` keurt zijn route dan opnieuw goed.
resource "tailscale_device_subnet_routes" "tailscale" {
  device_id = data.tailscale_device.tailscale.node_id
  routes    = ["192.168.0.0/24"]
}

# Dezelfde tag die roles/tailscale een herbouwde ct 108 geeft, zodat een
# herbouw niets verandert. Een getagde node verloopt niet en hangt niet aan
# jouw account.
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

# De Mac mini is jouw toestel (geen tag: het is ook gewoon je Mac) en zou dus
# na 180 dagen verlopen. Plex voor de familie ligt dan stil tot je opnieuw
# inlogt.
resource "tailscale_device_key" "mac_mini" {
  count               = local.mac_mini == null ? 0 : 1
  device_id           = local.mac_mini.node_id
  key_expiry_disabled = true
}

moved {
  from = tailscale_device_key.mac_mini
  to   = tailscale_device_key.mac_mini[0]
}
