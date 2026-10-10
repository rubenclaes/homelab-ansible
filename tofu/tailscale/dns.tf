# adguard (ct 107) is de DNS van de hele tailnet, via zijn 100.x-adres: een
# LAN-adres werkt alleen voor wie de subnet-route aanneemt, en dat doet hier
# geen enkel toestel. Zie netwerk/vpn.mdx. Het adres komt van het toestel
# zelf, zie policy.tf.
resource "tailscale_dns_configuration" "this" {
  magic_dns          = true
  override_local_dns = true

  nameservers {
    address = local.tailnet_ipv4.adguard
  }
}
