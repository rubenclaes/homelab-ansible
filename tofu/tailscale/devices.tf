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
#
# Geen tags op ct 108: hij staat op 25-09 als jouw toestel op de tailnet,
# zonder tag. Een tag zetten is geen overname maar een wijziging (het toestel
# gaat dan van jou naar de tag), dus dat is een aparte beslissing.
resource "tailscale_device_subnet_routes" "tailscale" {
  device_id = data.tailscale_device.tailscale.node_id
  routes    = ["192.168.0.0/24"]
}

# adguard: DNS voor de hele tailnet, en de policy geeft iedereen :53 op
# tag:homelab. Zonder deze tag lost *.neodata.be onderweg niet op.
resource "tailscale_device_tags" "adguard" {
  device_id = data.tailscale_device.adguard.node_id
  tags      = ["tag:homelab"]
}
