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
