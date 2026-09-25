# Rechtstreeks naar pve01, niet via proxmox.neodata.be: dat loopt over Caddy
# en AdGuard, en dat zijn containers die je hiermee misschien net herstelt.
# `insecure`, want pve01 heeft zijn eigen self-signed certificaat; dit is het
# LAN.
#
# Het token komt uit PROXMOX_VE_API_TOKEN (bin/tofu): tofu@pve met rol
# OpenTofu. Niet dat van Ansible, en nooit root@pam.
provider "proxmox" {
  endpoint = "https://192.168.0.10:8006/"
  insecure = true
}

locals {
  node = "pve01"
  # Zelfde bestand als Ansible leest (roles/proxmox_oci): één plek.
  guest_network = yamldecode(file("${path.module}/../../inventory/group_vars/proxmox/guest_network.yml")).pve_guest_network
}
