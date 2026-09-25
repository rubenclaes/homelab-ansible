# De VM's op pve01. Elk anders, dus elk een eigen blok.
#
# De waarde van een VM is zijn schijf, niet zijn vorm. Deze blokken houden de
# vorm juist (cores, geheugen, schijfgrootte, MAC); de inhoud komt uit PBS.
# Een MAC verandert nooit zomaar: een nieuwe MAC is een nieuw DHCP-adres, en
# haos herkent zichzelf eraan.

# PBS. scsi1 IS de back-updatastore: backup = false, anders probeert vzdump de
# back-ups in de back-ups te zetten.
resource "proxmox_virtual_environment_vm" "pbs" {
  node_name     = local.node
  vm_id         = 100
  name          = "pbs"
  on_boot       = true
  scsi_hardware = "virtio-scsi-single"
  boot_order    = ["scsi0", "ide2", "net0"]

  agent {
    enabled = true
  }

  cpu {
    cores   = 2
    sockets = 1
    type    = "host"
  }

  memory {
    dedicated = 4096
    floating  = 1024
  }

  disk {
    interface    = "scsi0"
    datastore_id = "local-lvm"
    size         = 32
    iothread     = true
  }

  disk {
    interface    = "scsi1"
    datastore_id = "vm-hdd"
    size         = 320
    iothread     = true
    discard      = "on"
    backup       = false
  }

  # ide2 (de installatie-ISO van PBS) staat hier bewust niet: de provider leest
  # hem bij een import niet terug en zou hem dan leeg of weg willen zetten.
  # Niets heeft hem nodig; zonder dit blok raakt OpenTofu hem niet aan.

  network_device {
    bridge      = "vmbr0"
    model       = "virtio"
    mac_address = "BC:24:11:3D:B4:6A"
    firewall    = true
  }

  operating_system {
    type = "l26"
  }

  lifecycle {
    prevent_destroy = true
    # De HTML-kaart van de community-scripts. Niets leest hem.
    ignore_changes = [description]
  }
}

# Home Assistant OS, van een community-script.
resource "proxmox_virtual_environment_vm" "haos" {
  node_name     = local.node
  vm_id         = 101
  name          = "haos"
  on_boot       = true
  bios          = "ovmf"
  machine       = "q35"
  scsi_hardware = "virtio-scsi-pci"
  boot_order    = ["scsi0"]
  tablet_device = false
  tags          = ["community-script"]

  agent {
    enabled = true
  }

  cpu {
    cores   = 2
    sockets = 1
    type    = "host"
  }

  memory {
    dedicated = 2048
  }

  efi_disk {
    datastore_id = "vm-hdd"
    type         = "4m"
  }

  disk {
    interface    = "scsi0"
    datastore_id = "vm-hdd"
    size         = 50
    discard      = "on"
    ssd          = true
  }

  network_device {
    bridge      = "vmbr0"
    model       = "virtio"
    mac_address = "02:8C:F5:A4:E6:15"
  }

  serial_device {
    device = "socket"
  }

  operating_system {
    type = "l26"
  }

  lifecycle {
    prevent_destroy = true
    # De HTML-kaart van de community-scripts. Niets leest hem.
    ignore_changes = [description]
  }
}

# Grafana, Prometheus, Loki (github.com/rubenclaes/monitoring-stack).
resource "proxmox_virtual_environment_vm" "grafana" {
  node_name     = local.node
  vm_id         = 102
  name          = "docker-grafana-stack"
  on_boot       = true
  bios          = "ovmf"
  machine       = "q35"
  scsi_hardware = "virtio-scsi-pci"
  boot_order    = ["scsi0"]
  tablet_device = false
  tags          = ["community-script"]

  agent {
    enabled = true
  }

  cpu {
    cores   = 2
    sockets = 1
    type    = "host"
  }

  memory {
    dedicated = 4048
  }

  efi_disk {
    datastore_id = "vm-hdd"
  }

  disk {
    interface    = "scsi0"
    datastore_id = "vm-hdd"
    size         = 100
    discard      = "on"
    ssd          = true
  }

  network_device {
    bridge      = "vmbr0"
    model       = "virtio"
    mac_address = "BC:24:11:4B:CD:E4"
  }

  serial_device {
    device = "socket"
  }

  operating_system {
    type = "l26"
  }

  lifecycle {
    prevent_destroy = true
    # De HTML-kaart van de community-scripts. Niets leest hem.
    ignore_changes = [description]
  }
}

# De Docker-host: alle stacks uit github.com/rubenclaes/containers.
resource "proxmox_virtual_environment_vm" "docker" {
  node_name     = local.node
  vm_id         = 103
  name          = "docker"
  on_boot       = true
  bios          = "ovmf"
  machine       = "q35"
  scsi_hardware = "virtio-scsi-pci"
  boot_order    = ["scsi0"]
  tablet_device = false
  tags          = ["community-script"]

  agent {
    enabled = true
  }

  cpu {
    cores = 6
    type  = "host"
  }

  # Was 28672 tot 23-09. De containers gebruikten ~4,2 GB; de rest vulde
  # Linux met cache die een VM zonder balloon nooit teruggeeft. 16 GB is dat
  # gebruik plus ruimte voor de pieken van immich-machine-learning.
  memory {
    dedicated = 16384
  }

  efi_disk {
    datastore_id = "vm-hdd"
  }

  disk {
    interface    = "scsi0"
    datastore_id = "vm-hdd"
    size         = 100
    discard      = "on"
    ssd          = true
  }

  network_device {
    bridge      = "vmbr0"
    model       = "virtio"
    mac_address = "02:12:F8:7B:9D:7D"
  }

  serial_device {
    device = "socket"
  }

  operating_system {
    type = "l26"
  }

  lifecycle {
    prevent_destroy = true
    # De HTML-kaart van de community-scripts. Niets leest hem.
    ignore_changes = [description]
  }
}
