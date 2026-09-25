# De Debian-containers op pve01. Eén regel per container; wat ze delen staat
# in het resource-blok eronder.
#
# Een nieuwe container: een regel erbij (volgende vrije vm_id, vast adres,
# MAC mag weg: Proxmox kiest er dan een), `bin/tofu proxmox apply`, daarna
# `ansible-playbook playbooks/new-guest.yml -e guest=<naam>`.
#
# ntfy (ct 109) staat hier niet: die maakt roles/proxmox_oci, uit een image.
locals {
  containers = {
    semaphore = {
      vm_id  = 104
      cores  = 2
      memory = 2048
      swap   = 512
      # 16G: Semaphore bouwt de docs-site (node_modules, .next) en houdt per
      # template een clone van de repo.
      disk        = { datastore = "local-lvm", size = 16 }
      ip          = "192.168.0.30/24"
      ipv6_auto   = false
      mac         = "BC:24:11:C6:BD:4E"
      keyctl      = false
      dns_servers = ["192.168.0.29"]
      # Zonder dit erft hij `search neodata.be` van pve01, en praat hij voor
      # zijn eigen publieke naam met zichzelf in plaats van met Caddy.
      searchdomain = "home.arpa"
      tags         = []
    }
    caddy = {
      vm_id        = 106
      cores        = 1
      memory       = 512
      swap         = 512
      disk         = { datastore = "vm-hdd", size = 6 }
      ip           = "192.168.0.25/24"
      ipv6_auto    = true
      mac          = "BC:24:11:B4:E6:74"
      keyctl       = true
      dns_servers  = ["192.168.0.29"]
      searchdomain = "home.arpa"
      tags         = ["community-script", "webserver"]
    }
    adguard = {
      vm_id     = 107
      cores     = 1
      memory    = 512
      swap      = 512
      disk      = { datastore = "vm-hdd", size = 2 }
      ip        = "192.168.0.29/24"
      ipv6_auto = true
      mac       = "BC:24:11:46:1E:BC"
      keyctl    = true
      # AdGuard IS de DNS van het huis; zelf vraagt hij het na bij 1.1.1.1,
      # niet bij zichzelf.
      dns_servers  = ["1.1.1.1"]
      searchdomain = null
      tags         = ["adblock", "community-script"]
    }
    tailscale = {
      vm_id        = 108
      cores        = 4
      memory       = 1024
      swap         = 1024
      disk         = { datastore = "vm-hdd", size = 8 }
      ip           = "192.168.0.50/24"
      ipv6_auto    = false
      mac          = "BC:24:11:7B:FA:28"
      keyctl       = false
      dns_servers  = null
      searchdomain = null
      tags         = []
    }
  }

  # Alleen gebruikt bij het aanmaken van een nieuwe container.
  lxc_template   = "local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst"
  ansible_pubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHLNyIywwfWQG5AzOf6ZGXYDIeNz3gcthJnpkQPdoFRq ansible@neodata"
}

resource "proxmox_virtual_environment_container" "this" {
  for_each = local.containers

  node_name     = local.node
  vm_id         = each.value.vm_id
  unprivileged  = true
  start_on_boot = true
  tags          = each.value.tags

  cpu {
    cores = each.value.cores
  }

  memory {
    dedicated = each.value.memory
    swap      = each.value.swap
  }

  disk {
    datastore_id = each.value.disk.datastore
    size         = each.value.disk.size
  }

  # nesting voor systemd; keyctl voor Docker-achtige dingen in caddy/adguard.
  # Een vlag behalve nesting veranderen mag alleen root@pam: dat moet dus met
  # de hand, ook al staat het hier. Voor een NIEUWE container met keyctl is
  # dat niet getest (caddy en adguard kregen het van een script als root);
  # weigert apply, zie docs "Een nieuwe container".
  features {
    nesting = true
    keyctl  = each.value.keyctl
  }

  # Proxmox' standaard, zo overgenomen: zonder dit blok wil de provider hem weghalen.
  console {
    type      = "tty"
    tty_count = 2
  }

  network_interface {
    name        = "eth0"
    bridge      = "vmbr0"
    mac_address = each.value.mac
  }

  initialization {
    hostname = each.key

    ip_config {
      ipv4 {
        address = each.value.ip
        gateway = "192.168.0.1"
      }

      dynamic "ipv6" {
        for_each = each.value.ipv6_auto ? [1] : []
        content {
          address = "auto"
        }
      }
    }

    dynamic "dns" {
      for_each = each.value.dns_servers != null || each.value.searchdomain != null ? [1] : []
      content {
        servers = each.value.dns_servers
        domain  = each.value.searchdomain
      }
    }

    # Zodat new-guest.yml er als root in kan om het ansible-account te maken.
    user_account {
      keys = [local.ansible_pubkey]
    }
  }

  operating_system {
    template_file_id = local.lxc_template
    type             = "debian"
  }

  lifecycle {
    # Een lege container in de plaats van een draaiende: nooit.
    prevent_destroy = true

    ignore_changes = [
      # De HTML-kaart van de community-scripts op caddy en adguard. Niets
      # leest hem; hem weghalen is een wijziging zonder nut.
      description,
      # Het template telt alleen bij het aanmaken; een bestaande container
      # leest Proxmox niet terug naar een template.
      operating_system[0].template_file_id,
      # Idem: de sleutel wordt eenmalig in root gezet. Proxmox geeft hem
      # niet terug, dus zonder deze regel wil elk plan hem opnieuw zetten.
      initialization[0].user_account,
    ]
  }
}
