# OpenTofu, deel 2: Proxmox — uitvoeringsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** De vier VM's, de vier Debian-containers en de gebruiker/rol/ACL van Ansible op pve01 staan in `tofu/proxmox/`, `bin/tofu proxmox plan` is leeg, en de Ansible-afschriften en -rollen die dat deden zijn weg zonder dat iets breekt.

**Architecture:** Eigen project `tofu/proxmox/` met dezelfde R2-backend en versleuteling als `tofu/tailscale/`. VM's als vier losse blokken, containers als één `for_each` over een map. Alles eerst met `import`-blokken overgenomen tot het plan leeg is; pas daarna gaan de oude bronnen weg. De `/dev/net/tun`-regels gaan naar een kleine Ansible-rol die als root op pve01 draait. Wie `pve_lxcs` las, leest voortaan de live feiten uit de dynamische inventory.

**Tech Stack:** OpenTofu 1.12, provider `bpg/proxmox` 0.114.x, Proxmox VE 9.2, Ansible (community.proxmox inventory), bash.

**Spec:** `docs/superpowers/specs/2026-09-25-opentofu-proxmox-design.md`

## Global Constraints

- Provider `bpg/proxmox` op `~> 0.114`; `required_version = ">= 1.10"`; lock-bestand in git.
- State: bucket `homelab-tofu-state`, key `proxmox/terraform.tfstate`, `use_lockfile = true`, versleuteling zoals `tofu/tailscale/backend.tf` (pbkdf2 + aes_gcm, `enforced` voor state en plan).
- Endpoint `https://192.168.0.10:8006/`, `insecure = true`. Node heet `pve01`.
- OpenTofu praat als `tofu@pve` via `PROXMOX_VE_API_TOKEN` uit `tofu/secrets.env`. Nooit `root@pam`.
- Elke guest en de gebruiker `ansible@pve`: `lifecycle { prevent_destroy = true }`.
- `ignore_changes` alleen met per regel een commentaar waarom. Nooit om een plan stil te krijgen dat een echte afwijking toont.
- **Nooit** `apply` op een plan met `must be replaced`, `destroy`, of `create` voor een guest die al bestaat. Pas dan de code aan.
- Niets verandert op pve01 vóór Task 6. Tot dan is terug gaan: `tofu/proxmox/` weggooien en de state-key in R2 verwijderen.
- Niet in OpenTofu: `tofu@pve` zelf, `root@pam`, `rubenclaes@pam`, ntfy (ct 109), storage/back-upjobs/meldingen/netwerk.
- Taal van commentaar en docs: Nederlands.

## Review Focus

- Een import die `replace` wil voor een VM of container → apply zou een lege schijf geven. Test: elk import-plan moet `N to import, 0 to add, 0 to change, 0 to destroy` zijn (Task 3, 4, 5), en `plan -destroy` weigert (Task 6).
- Een nieuwe container zonder SSH-sleutel of met een verkeerd template → `new-guest.yml` kan er niet in. Test: Task 5 stap 5 plant een tijdelijke container en toont `user_account` en template in het plan (niet toepassen).
- Na het weghalen van `pve_lxcs` breken `restore-drill.yml`, `docs.yml` of `proxmox_oci` stil. Test: Task 8 draait elk van die drie echt of in `--check`.
- `tofu@pve` mist een privilege → import of plan faalt halverwege met 403. Test: Task 2 stap 6 leest alle drie de soorten objecten.
- De `/dev/net/tun`-taak schrijft in een snapshot-sectie of dubbel → Tailscale start niet na herbouw. Test: Task 7 droogloop meldt niets, en de taak weigert een config met `[`-secties.

---

### Task 1: `tofu@pve` aanmaken (Ruben)

Handstap, beveiligingsgevoelig: een agent stopt hier en vraagt Ruben.

**Files:**
- Modify: `tofu/secrets.env` (gevault, `infra`)

**Interfaces:**
- Produces: `PROXMOX_VE_API_TOKEN=tofu@pve!opentofu=<uuid>` in `tofu/secrets.env`.

- [ ] **Step 1: Gebruiker, rol, ACL en token op pve01**

Als root op pve01 (`ssh pve01`, dan `sudo -i`):

```bash
pveum user add tofu@pve --comment "OpenTofu (homelab-ansible, tofu/proxmox)"
pveum role add OpenTofu -privs "Datastore.AllocateSpace,Datastore.AllocateTemplate,Datastore.Audit,Pool.Audit,SDN.Audit,SDN.Use,Sys.Audit,Sys.Modify,User.Modify,Permissions.Modify,Realm.AllocateUser,VM.Allocate,VM.Audit,VM.Clone,VM.Config.CDROM,VM.Config.CPU,VM.Config.Cloudinit,VM.Config.Disk,VM.Config.HWType,VM.Config.Memory,VM.Config.Network,VM.Config.Options,VM.GuestAgent.Audit,VM.PowerMgmt"
pveum aclmod / -user tofu@pve -role OpenTofu
pveum user token add tofu@pve opentofu --privsep=0
```

Het laatste commando toont het geheim **één keer**. Kopieer `full-tokenid` en `value`.

- [ ] **Step 2: In `tofu/secrets.env`**

Run: `ansible-vault edit tofu/secrets.env` en voeg toe:

```bash
# Proxmox: token van tofu@pve (rol OpenTofu), niet dat van Ansible
PROXMOX_VE_API_TOKEN=tofu@pve!opentofu=<value>
```

- [ ] **Step 3: Controleren en committen**

Run: `bin/check-vaulted`
Expected: `encrypted  tofu/secrets.env`, exit 0.

```bash
git add tofu/secrets.env
git commit -m "chore: proxmox token for OpenTofu"
```

---

### Task 2: Het project `tofu/proxmox`

**Files:**
- Create: `tofu/proxmox/versions.tf`, `tofu/proxmox/backend.tf`, `tofu/proxmox/providers.tf`, `tofu/proxmox/.terraform.lock.hcl`

**Interfaces:**
- Consumes: `bin/tofu`, `PROXMOX_VE_API_TOKEN` (Task 1).
- Produces: een geïnitialiseerd project; `local.node = "pve01"` (in `providers.tf`).

- [ ] **Step 1: `versions.tf`**

```hcl
terraform {
  required_version = ">= 1.10"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.114"
    }
  }
}
```

- [ ] **Step 2: `backend.tf`**

Kopie van `tofu/tailscale/backend.tf` met één verschil, de key:

```hcl
    key    = "proxmox/terraform.tfstate"
```

(De rest letterlijk gelijk, inclusief het commentaar, `variable "state_passphrase"` en het `encryption`-blok. Elk project heeft zijn eigen backend-blok nodig; OpenTofu kent geen gedeeld backend.)

- [ ] **Step 3: `providers.tf`**

```hcl
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
}
```

- [ ] **Step 4: Opmaak, init, lock**

Run: `tofu fmt -check -recursive tofu/ && bin/tofu proxmox init`
Expected: `OpenTofu has been successfully initialized!`

Run: `bin/tofu proxmox providers lock -platform=darwin_arm64 -platform=linux_amd64`
Expected: `Success!`

- [ ] **Step 5: Lege state schrijven**

Run: `bin/tofu proxmox apply -auto-approve`
Expected: `Apply complete! Resources: 0 added, 0 changed, 0 destroyed.`

- [ ] **Step 6: Kan het token alles lezen wat we gaan beheren?**

Create `tofu/proxmox/zz_probe.tf` (tijdelijk):

```hcl
data "proxmox_virtual_environment_vms" "all" { node_name = local.node }
data "proxmox_virtual_environment_containers" "all" { node_name = local.node }
data "proxmox_virtual_environment_user" "ansible" { user_id = "ansible@pve" }
data "proxmox_virtual_environment_role" "ansible" { role_id = "AnsibleAutomation" }

output "zz_probe" {
  value = {
    vms        = sort([for v in data.proxmox_virtual_environment_vms.all.vms : v.vm_id])
    containers = sort([for c in data.proxmox_virtual_environment_containers.all.containers : c.vm_id])
    user       = data.proxmox_virtual_environment_user.ansible.comment
    role       = length(data.proxmox_virtual_environment_role.ansible.privileges)
  }
}
```

Run: `bin/tofu proxmox plan`
Expected: output met `vms = [100, 101, 102, 103]`, `containers = [104, 106, 107, 108, 109]`, `user = "Ansible automation"`, `role = 14`. Een 403: het ontbrekende privilege aan rol `OpenTofu` toevoegen (Task 1, stap 1), opnieuw.

Run: `rm tofu/proxmox/zz_probe.tf`

- [ ] **Step 7: Commit**

```bash
git add tofu/proxmox/versions.tf tofu/proxmox/backend.tf tofu/proxmox/providers.tf tofu/proxmox/.terraform.lock.hcl
git commit -m "feat: tofu/proxmox project"
```

---

### Task 3: Gebruiker, rol en ACL van Ansible importeren

**Files:**
- Create: `tofu/proxmox/access.tf`

**Interfaces:**
- Produces: `proxmox_virtual_environment_user.ansible`, `proxmox_virtual_environment_role.ansible`, `proxmox_virtual_environment_acl.ansible`.

- [ ] **Step 1: `access.tf` met import**

```hcl
# De Proxmox-gebruiker van Ansible. De dynamische inventory, report.yml en
# roles/proxmox_oci praten als ansible@pve!automation.
#
# Het token zelf staat hier niet: een tokengeheim kan je niet importeren, en
# het bestaat al. Verdwijnt deze gebruiker, dan is ook het token weg en ziet
# Ansible geen enkele guest meer; daarom prevent_destroy.

resource "proxmox_virtual_environment_user" "ansible" {
  user_id = "ansible@pve"
  comment = "Ansible automation"
  enabled = true

  lifecycle {
    prevent_destroy = true
  }
}

# Wat Ansible mag. Een privilege weghalen kan iets breken dat je pas later
# merkt: kijk eerst wie het gebruikt (grep in roles/ en playbooks/).
#   - VM.Config.Options: env en entrypoint van de OCI-containers (ntfy)
#   - VM.GuestAgent.Audit: de adressen van de VM's voor de inventory
resource "proxmox_virtual_environment_role" "ansible" {
  role_id = "AnsibleAutomation"
  privileges = [
    "Datastore.AllocateSpace",
    "Datastore.AllocateTemplate",
    "Datastore.Audit",
    "SDN.Use",
    "Sys.Audit",
    "VM.Allocate",
    "VM.Audit",
    "VM.Config.CPU",
    "VM.Config.Disk",
    "VM.Config.Memory",
    "VM.Config.Network",
    "VM.Config.Options",
    "VM.GuestAgent.Audit",
    "VM.PowerMgmt",
  ]
}

resource "proxmox_virtual_environment_acl" "ansible" {
  path      = "/"
  user_id   = proxmox_virtual_environment_user.ansible.user_id
  role_id   = proxmox_virtual_environment_role.ansible.role_id
  propagate = true
}

import {
  to = proxmox_virtual_environment_user.ansible
  id = "ansible@pve"
}

import {
  to = proxmox_virtual_environment_role.ansible
  id = "AnsibleAutomation"
}

import {
  to = proxmox_virtual_environment_acl.ansible
  id = "/?ansible@pve?AnsibleAutomation"
}
```

- [ ] **Step 2: Plan**

Run: `bin/tofu proxmox plan`
Expected: `Plan: 3 to import, 0 to add, 0 to change, 0 to destroy.` Een `~` bij een van de drie: de code wijkt af van pve01; pas de code aan (pve01 wint), opnieuw.

- [ ] **Step 3: Importeren, import-blokken weg, leeg plan**

Run: `bin/tofu proxmox plan -out=p.tfplan && bin/tofu proxmox apply p.tfplan && rm tofu/proxmox/p.tfplan`
Expected: `Resources: 3 imported, 0 added, 0 changed, 0 destroyed.`

Haal de drie `import`-blokken uit `access.tf`.

Run: `bin/tofu proxmox plan -detailed-exitcode; echo "exit=$?"`
Expected: `No changes.`, `exit=0`.

- [ ] **Step 4: Commit**

```bash
git add tofu/proxmox/access.tf
git commit -m "feat: ansible@pve, its role and ACL imported into OpenTofu"
```

---

### Task 4: De vier containers importeren

**Files:**
- Create: `tofu/proxmox/containers.tf`

**Interfaces:**
- Produces: `proxmox_virtual_environment_container.this["semaphore"|"caddy"|"adguard"|"tailscale"]`; `local.containers` (map); `local.lxc_template`; `local.ansible_pubkey`.

- [ ] **Step 1: `containers.tf` met import**

De waarden komen van `pct config` op 25-09, niet uit `lxcs.yml` (dat liep op een paar plekken achter).

```hcl
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
  # de hand, ook al staat het hier.
  features {
    nesting = true
    keyctl  = each.value.keyctl
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
      # Het template telt alleen bij het aanmaken; een bestaande container
      # leest Proxmox niet terug naar een template.
      operating_system[0].template_file_id,
      # Idem: de sleutel wordt eenmalig in root gezet. Proxmox geeft hem
      # niet terug, dus zonder deze regel wil elk plan hem opnieuw zetten.
      initialization[0].user_account,
    ]
  }
}

import {
  for_each = local.containers
  to       = proxmox_virtual_environment_container.this[each.key]
  id       = "${local.node}/${each.value.vm_id}"
}
```

- [ ] **Step 2: Plan lezen en de code gelijkzetten met pve01**

Run: `bin/tofu proxmox plan -no-color > /tmp/claude-501/p4.txt; grep -E "Plan:|must be replaced|will be updated" /tmp/claude-501/p4.txt`
Expected: `Plan: 4 to import, 0 to add, 0 to change, 0 to destroy.`

Toont het een `~` of `-/+`: lees welk veld, en pas de code aan zodat ze pve01 beschrijft. De werkelijkheid wint. Typisch:

| Plan zegt | Doe |
| --- | --- |
| `console` / `cmode` bij 104 | `console { type = "tty" }` in het blok (voor alle vier; `tty` is ook de standaard) |
| `description` met HTML (helper-scripts) | `description` in `ignore_changes`, commentaar: "HTML van de community-scripts, met de hand" |
| `timezone` | de provider kent het veld niet; staat het in het plan, `ignore_changes` met reden "met de hand gezet door de helper-scripts" |
| `-/+` op `disk` bij 108 (`basevol`, een ex-template) | **niet toepassen.** Stop en meld: dit vraagt een beslissing, geen brede `ignore_changes` |
| `network_interface` `firewall`/`mtu` | overnemen zoals pve01 ze heeft |

Nooit verder met een `must be replaced` in het plan.

- [ ] **Step 3: Importeren, import-blok weg, leeg plan**

Run: `bin/tofu proxmox plan -out=p.tfplan && bin/tofu proxmox apply p.tfplan && rm tofu/proxmox/p.tfplan`
Expected: `Resources: 4 imported, 0 added, 0 changed, 0 destroyed.`

Haal het `import`-blok weg.

Run: `bin/tofu proxmox plan -detailed-exitcode; echo "exit=$?"`
Expected: `No changes.`, `exit=0`.

- [ ] **Step 4: Commit**

```bash
git add tofu/proxmox/containers.tf
git commit -m "feat: LXC containers 104-108 imported into OpenTofu"
```

---

### Task 5: De vier VM's importeren

**Files:**
- Create: `tofu/proxmox/vms.tf`

**Interfaces:**
- Produces: `proxmox_virtual_environment_vm.pbs|haos|grafana|docker`.

- [ ] **Step 1: `vms.tf` met import**

Waarden van `qm config` op 25-09.

```hcl
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

  cdrom {
    interface = "ide2"
    file_id   = "local:iso/proxmox-backup-server_4.2-1.iso"
  }

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
  }
}

import {
  to = proxmox_virtual_environment_vm.pbs
  id = "pve01/100"
}

import {
  to = proxmox_virtual_environment_vm.haos
  id = "pve01/101"
}

import {
  to = proxmox_virtual_environment_vm.grafana
  id = "pve01/102"
}

import {
  to = proxmox_virtual_environment_vm.docker
  id = "pve01/103"
}
```

- [ ] **Step 2: Plan lezen en gelijkzetten**

Run: `bin/tofu proxmox plan -no-color > /tmp/claude-501/p5.txt; grep -E "Plan:|must be replaced|will be updated|forces replacement" /tmp/claude-501/p5.txt`
Expected: `Plan: 4 to import, 0 to add, 0 to change, 0 to destroy.`

Een VM heeft veel velden; verwacht een paar rondes. Werk per VM, en neem pve01 over:

| Plan zegt | Doe |
| --- | --- |
| `description` (HTML van de helper-scripts) | `ignore_changes = [description]`, commentaar "HTML van de community-scripts" |
| `efi_disk.type` / `file_format` / `pre_enrolled_keys` | de waarde uit het plan (de "state"-kant) letterlijk overnemen |
| `smbios` / `vmgenid` / `uuid` | overnemen als blok (`smbios { uuid = "..." }`), niet negeren: een andere UUID ziet de guest als nieuwe hardware |
| `numa`, `sockets`, `keyboard_layout`, `vga`, `kvm_arguments` met een default die afwijkt | de waarde van pve01 overnemen |
| `disk.file_format` / `aio` / `cache` / `replicate` | overnemen |
| `started` / `stop_on_destroy` / timeouts | provider-instellingen, geen Proxmox-config: ze horen niet in een diff; staat er toch iets, overnemen |
| `forces replacement` op een disk | **stop**. Nooit toepassen. Meestal `datastore_id` of `interface` verkeerd; controleer tegen `qm config` |

- [ ] **Step 3: Importeren, import-blokken weg, leeg plan**

Run: `bin/tofu proxmox plan -out=p.tfplan && bin/tofu proxmox apply p.tfplan && rm tofu/proxmox/p.tfplan`
Expected: `Resources: 4 imported, 0 added, 0 changed, 0 destroyed.`

Haal de vier `import`-blokken weg.

Run: `bin/tofu proxmox plan -detailed-exitcode; echo "exit=$?"`
Expected: `No changes.`, `exit=0`.

- [ ] **Step 4: Commit**

```bash
git add tofu/proxmox/vms.tf
git commit -m "feat: VMs 100-103 imported into OpenTofu"
```

- [ ] **Step 5: Een nieuwe container: wat zou er gebeuren? (niet toepassen)**

Voeg tijdelijk aan `local.containers` toe:

```hcl
    zztest = {
      vm_id = 198, cores = 1, memory = 256, swap = 0
      disk = { datastore = "vm-hdd", size = 2 }
      ip = "192.168.0.198/24", ipv6_auto = false, mac = null, keyctl = false
      dns_servers = null, searchdomain = "home.arpa", tags = []
    }
```

Run: `bin/tofu proxmox plan -no-color | grep -E "Plan:|template_file_id|keys|hostname"`
Expected: `Plan: 1 to add, 0 to change, 0 to destroy.`, met `template_file_id = "local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst"`, de `ansible@neodata`-sleutel en `hostname = "zztest"`.

Haal `zztest` weer weg. Run: `bin/tofu proxmox plan -detailed-exitcode; echo "exit=$?"` → `exit=0`.

---

### Task 6: De vangnetten bewijzen

**Files:** geen.

- [ ] **Step 1: `prevent_destroy` weigert**

Run: `bin/tofu proxmox plan -destroy -no-color > /tmp/claude-501/p6.txt 2>&1; echo "exit=$?"; grep -c "Instance cannot be destroyed" /tmp/claude-501/p6.txt`
Expected: `exit=1` en een telling van 9 (vier VM's, vier containers, ansible@pve).

- [ ] **Step 2: Een echte, onschuldige wijziging**

Zet op `caddy` een extra tag: `tags = ["community-script", "webserver", "tofu"]`.

Run: `bin/tofu proxmox plan -no-color | grep -E "Plan:|tags"`
Expected: `Plan: 0 to add, 1 to change, 0 to destroy.`, alleen `tags` van `proxmox_virtual_environment_container.this["caddy"]`.

Run: `bin/tofu proxmox apply` (`yes`), en controleer: `ssh pve01 sudo pct config 106 | grep tags` → bevat `tofu`.

Zet de tag terug weg, `bin/tofu proxmox apply`, dan `bin/tofu proxmox plan -detailed-exitcode; echo "exit=$?"` → `exit=0`.

- [ ] **Step 3: Tailscale nog steeds leeg**

Run: `bin/tofu tailscale plan -detailed-exitcode; echo "exit=$?"`
Expected: `exit=0`.

---

### Task 7: `/dev/net/tun` naar Ansible

**Files:**
- Create: `roles/proxmox_tun/tasks/main.yml`, `roles/proxmox_tun/handlers/main.yml`, `roles/proxmox_tun/defaults/main.yml`, `roles/proxmox_tun/meta/main.yml`
- Modify: `playbooks/proxmox-datacenter.yml` (rol erbij)
- Modify: `inventory/group_vars/proxmox/lxcs.yml` (lijst `pve_tun_guests`, en de oude commentaren bij 107/108 weg)

**Interfaces:**
- Consumes: `pve_tun_guests: [107, 108]`.

- [ ] **Step 1: De rol**

`roles/proxmox_tun/defaults/main.yml`:

```yaml
---
# Containers die /dev/net/tun krijgen (Tailscale). Staat in
# inventory/group_vars/proxmox/lxcs.yml.
pve_tun_guests: []
```

`roles/proxmox_tun/meta/main.yml`:

```yaml
---
galaxy_info:
  author: rubenclaes
  description: /dev/net/tun in LXC-containers op Proxmox, voor Tailscale
  license: MIT
  min_ansible_version: "2.17"
  platforms:
    - name: Debian
dependencies: []
```

`roles/proxmox_tun/tasks/main.yml`:

```yaml
---
# /dev/net/tun in een container, voor Tailscale. Zonder start tailscaled niet
# en faalt hij stil in een herstartlus.
#
# Waarom hier en niet in OpenTofu: een apparaat doorgeven mag van Proxmox
# alleen root@pam, en een API-token telt niet als root. Ansible is hier root
# via SSH. En niet met `pct set`: die weigert rauwe lxc-sleutels op deze
# versie ("400 unable to parse option").
#
# Geschreven met grep en een append in plaats van lineinfile: /etc/pve is
# pmxcfs, en daar faalt het tijdelijke bestand + chmod van lineinfile.

- name: Refuse a config with snapshot sections
  ansible.builtin.command: grep -c '^\[' /etc/pve/lxc/{{ item }}.conf
  register: proxmox_tun_sections
  changed_when: false
  failed_when: proxmox_tun_sections.stdout | int > 0
  check_mode: false
  loop: "{{ pve_tun_guests }}"

- name: Read which tun lines are present
  ansible.builtin.command: grep -cxF -e '{{ proxmox_tun_lines[0] }}' -e '{{ proxmox_tun_lines[1] }}' /etc/pve/lxc/{{ item }}.conf
  register: proxmox_tun_present
  changed_when: false
  failed_when: false
  check_mode: false
  loop: "{{ pve_tun_guests }}"

- name: Add the tun lines
  ansible.builtin.shell: >-
    printf '%s\n' '{{ proxmox_tun_lines[0] }}' '{{ proxmox_tun_lines[1] }}'
    >> /etc/pve/lxc/{{ item.item }}.conf
  when: item.stdout | int == 0
  loop: "{{ proxmox_tun_present.results }}"
  loop_control:
    label: "{{ item.item }}"
  changed_when: true
  notify: Reboot tun containers

- name: Refuse a half-configured container
  ansible.builtin.assert:
    that: item.stdout | int in [0, 2]
    fail_msg: >-
      ct {{ item.item }} heeft maar één van de twee tun-regels. Kijk in
      /etc/pve/lxc/{{ item.item }}.conf en zet ze met de hand gelijk.
    quiet: true
  loop: "{{ proxmox_tun_present.results }}"
  loop_control:
    label: "{{ item.item }}"
```

In `defaults/main.yml` ook de twee regels:

```yaml
proxmox_tun_lines:
  - "lxc.cgroup2.devices.allow: c 10:200 rwm"
  - "lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file"
```

`roles/proxmox_tun/handlers/main.yml`:

```yaml
---
# Een mount-entry geldt pas na een start. Alleen de containers die nieuwe
# regels kregen; voor adguard is dat even geen DNS.
- name: Reboot tun containers
  ansible.builtin.command: pct reboot {{ item.item }}
  loop: "{{ proxmox_tun_present.results | selectattr('stdout', 'eq', '0') | list }}"
  loop_control:
    label: "{{ item.item }}"
  changed_when: true
```

- [ ] **Step 2: In de inventory en het playbook**

In `inventory/group_vars/proxmox/lxcs.yml`, onder `pve_oci_lxcs` (vóór `drill_vmid`):

```yaml
# Containers die /dev/net/tun krijgen, voor Tailscale: adguard (107, DNS van
# de tailnet) en tailscale (108, subnet-router). Zie roles/proxmox_tun.
pve_tun_guests: [107, 108]
```

In `playbooks/proxmox-datacenter.yml`, `roles:` wordt:

```yaml
  roles:
    - proxmox_datacenter
    - proxmox_tun
```

- [ ] **Step 3: Droogloop: niets te doen**

Run: `ansible-playbook playbooks/proxmox-datacenter.yml --check --diff`
Expected: `failed=0`, en `changed=0` voor de `proxmox_tun`-taken (de regels staan er al op 107 en 108).

- [ ] **Step 4: Echte run en lint**

Run: `ansible-playbook playbooks/proxmox-datacenter.yml && ansible-lint roles/proxmox_tun playbooks/proxmox-datacenter.yml`
Expected: `changed=0` voor proxmox_tun, lint zonder fouten.

- [ ] **Step 5: Commit**

```bash
git add roles/proxmox_tun playbooks/proxmox-datacenter.yml inventory/group_vars/proxmox/lxcs.yml
git commit -m "feat: proxmox_tun role sets /dev/net/tun for 107 and 108"
```

---

### Task 8: Opruimen aan de Ansible-kant

**Files:**
- Delete: `inventory/group_vars/proxmox/vms.yml`, `inventory/group_vars/proxmox/access.yml`, `roles/proxmox_lxc/`, `roles/proxmox_access/`, `playbooks/proxmox-lxcs.yml`
- Modify: `inventory/group_vars/proxmox/lxcs.yml` (`pve_lxcs` en `pve_lxc_defaults` weg, `pve_guest_network` erbij)
- Modify: `roles/proxmox_oci/tasks/container.yml:150-157`, `roles/proxmox_oci/tasks/main.yml:3-5`
- Modify: `playbooks/proxmox-access.yml` (alleen de controle blijft)
- Modify: `playbooks/new-guest.yml`, `playbooks/restore-drill.yml`, `playbooks/docs.yml`, `playbooks/templates/docs/machines.md.j2`, `playbooks/site.yml:9`, `inventory/group_vars/proxmox/main.yml:5-8`

**Interfaces:**
- Consumes: de dynamische inventory: groep `proxmox_all_lxc`, `appliances`; hostvars `proxmox_vmid`, `proxmox_cores`, `proxmox_memory`, `proxmox_rootfs.size` (bv. `"2G"`), `ansible_host`.
- Produces: `pve_guest_network: {bridge, gateway, searchdomain}`.

- [ ] **Step 1: Eerst een basis: wat is groen vóór het opruimen?**

Run: `ansible-playbook playbooks/site.yml --check --limit 'all:!mbp:!semaphore' > /tmp/claude-501/before.txt 2>&1; tail -20 /tmp/claude-501/before.txt`
Expected: `failed=0` overal. Noteer de `changed`-tellers; na het opruimen moeten ze gelijk zijn.

- [ ] **Step 2: `lxcs.yml`**

Vervang het blok `pve_lxc_defaults:` … tot en met de hele `pve_lxcs:`-lijst door:

```yaml
# Het netwerk van de containers die Ansible nog zelf maakt (ntfy, via
# roles/proxmox_oci). De Debian-containers maakt OpenTofu (tofu/proxmox/);
# daar staan dezelfde drie waarden. Eén plek zodra ntfy ook verhuist.
pve_guest_network:
  bridge: vmbr0
  gateway: 192.168.0.1
  # Zonder erft een container `search neodata.be` van pve01 en praat hij
  # voor zijn eigen publieke naam met zichzelf in plaats van met Caddy.
  searchdomain: home.arpa
```

Pas de header-commentaar van het bestand aan: "LXC definitions" → "ntfy, /dev/net/tun en de restore-drill. De Debian-containers staan in tofu/proxmox/containers.tf."

- [ ] **Step 3: `proxmox_oci`**

In `roles/proxmox_oci/tasks/container.yml`: `pve_lxc_defaults.bridge` → `pve_guest_network.bridge`, `pve_lxc_defaults.gateway` → `pve_guest_network.gateway`, `pve_lxc_defaults.searchdomain` → `pve_guest_network.searchdomain`.

In `roles/proxmox_oci/tasks/main.yml:3-5`: "like proxmox_lxc" weg; "(roles/proxmox_access/defaults/main.yml)" → "(tofu/proxmox/access.tf)".

Run: `grep -rn "pve_lxc_defaults\|proxmox_lxc\b\|proxmox_access\b" roles playbooks inventory | grep -v "^roles/proxmox_\(lxc\|access\)/"`
Expected: alleen nog de plekken die de volgende stappen aanpassen (`new-guest.yml`, `restore-drill.yml`, `docs.yml`, `machines.md.j2`, `site.yml`, `proxmox/main.yml`, `proxmox-access.yml`, `pbs/tasks/config.yml` en `proxmox_network` (alleen commentaar)).

- [ ] **Step 4: `new-guest.yml`**

Header (regels 1-19) wordt:

```yaml
---
# Een nieuwe LXC-container klaarzetten, nadat OpenTofu hem gemaakt heeft.
#
#   1. Een regel in tofu/proxmox/containers.tf, dan: bin/tofu proxmox apply
#   2. ansible-playbook playbooks/new-guest.yml -e guest=<hostname>
#
# Wat dit doet: wachten tot hij luistert, zijn SSH-hostkey vertrouwen, het
# `ansible`-serviceaccount aanmaken en de baseline toepassen. Daarna is het
# een gewone host en mag site.yml erop.
#
# Wat dit NIET doet: de container maken (OpenTofu), of de dienst installeren
# (een eigen rol, of playbooks/new-service.yml).
```

De eerste play: de naam wordt "Make the new container reachable"; de taken "Require a guest…", "Remember…" en "Create it…" worden vervangen door:

```yaml
    - name: Require a container that Proxmox knows
      ansible.builtin.assert:
        that:
          - guest is defined
          - guest in (groups['proxmox_all_lxc'] | default([]))
          - guest not in (groups['appliances'] | default([]))
        fail_msg: >-
          Pass -e guest=<hostname> of a container that exists. Proxmox knows:
          {{ groups['proxmox_all_lxc'] | default([]) | difference(groups['appliances'] | default([])) | sort | join(', ') }}.
          A new one: add it to tofu/proxmox/containers.tf and run
          `bin/tofu proxmox apply` first.
        success_msg: "Preparing {{ guest | default('?') }}"

    - name: Remember what Proxmox says about it
      ansible.builtin.set_fact:
        new_guest_ip: "{{ hostvars[guest].ansible_host }}"
        new_guest_vmid: "{{ hostvars[guest].proxmox_vmid }}"
```

In de rest van de play: `new_guest_entry.ip | split('/') | first` → `new_guest_ip` (vier plekken), `new_guest_entry.vmid` → `new_guest_vmid`.

Commentaar boven "Create the ansible service account": "because pve_lxc_defaults.pubkey was injected at creation" → "because OpenTofu puts the ansible@neodata key in root at creation (tofu/proxmox/containers.tf, user_account)".

Laatste melding, regel 3: `"3. Commit pve_lxcs en de rest, …"` → `"3. Commit tofu/proxmox/containers.tf en de rest, anders bestaat deze machine alleen bij jou."`

Run: `ansible-playbook playbooks/new-guest.yml -e guest=bestaatniet; echo "exit=$?"`
Expected: faalt op de assert met de lijst `adguard, caddy, semaphore, tailscale`.

- [ ] **Step 5: `restore-drill.yml`**

Vervang de taken "Eis een guest die de inventory kent", "Onthoud wat de inventory over hem zegt" en "Weiger een vmid die de inventory claimt" door:

```yaml
    - name: Eis een container die Proxmox kent
      ansible.builtin.assert:
        that: restore_guest in drill_guests
        fail_msg: >-
          '{{ restore_guest }}' is geen Debian-container op pve01. Kies er een:
          {{ drill_guests | sort | join(', ') }}.
        success_msg: "Drill op de back-ups van {{ restore_guest }}"

    - name: Onthoud wat Proxmox over hem zegt
      ansible.builtin.set_fact:
        restore_vmid: "{{ hostvars[restore_guest].proxmox_vmid | int }}"
        restore_probe: "{{ drill_probes[restore_guest] | default('/etc/hostname') }}"

    # Twee wachten: dit playbook mag precies één vmid aanraken, en die mag
    # van niemand zijn. Ook niet van een guest die nu even weg is maar in
    # tofu/proxmox/ staat: die nummers (100-108) liggen onder drill_vmid.
    - name: Weiger een vmid van een bekende guest
      ansible.builtin.assert:
        that: drill_vmid not in drill_known_vmids
        fail_msg: >-
          vmid {{ drill_vmid }} hoort bij een echte guest. Dit playbook zou hem
          overschrijven. Verander drill_vmid.
        success_msg: "vmid {{ drill_vmid }} is van niemand"
```

En in de play-`vars:` (naast `restore_guest`):

```yaml
    drill_guests: >-
      {{ groups['proxmox_all_lxc'] | default([])
         | difference(groups['appliances'] | default([])) }}
    drill_known_vmids: >-
      {{ (groups['proxmox_all_lxc'] | default([])) + (groups['proxmox_all_qemu'] | default([]))
         | map('extract', hostvars, 'proxmox_vmid') | map('int') | list }}
```

Let op de haakjes: `((a) + (b)) | map(...)`. Schrijf het zo:

```yaml
    drill_known_vmids: >-
      {{ ((groups['proxmox_all_lxc'] | default([])) + (groups['proxmox_all_qemu'] | default([])))
         | map('extract', hostvars, 'proxmox_vmid') | map('int') | list }}
```

Verder: `restore_source.vmid` → `restore_vmid` (regels 115, 124, 135).

Run: `ansible-playbook playbooks/restore-drill.yml -e drill_confirm=true --check`
Expected: `failed=0` en een melding welke back-up van adguard hij zou pakken.

Run: `ansible-playbook playbooks/restore-drill.yml -e drill_confirm=true`
Expected: de drill slaagt op adguard (terugzetten, probe lezen, opruimen), `failed=0`.

- [ ] **Step 6: `docs.yml` en `machines.md.j2`**

In `playbooks/docs.yml`: de twee regels `pve_lxcs: …` en `pve_lxc_defaults: …` weg.

In `playbooks/templates/docs/machines.md.j2`:
- regel 15 (`{% set lxc_names = … %}`) weg.
- regel 26: "`homelab.proxmox.yml` live ophaalt, `pve_lxcs` en elke" → "`homelab.proxmox.yml` live ophaalt en elke".
- regel 63, het stuk `{% if h in lxc_names %}…{% endif +%}` wordt:

```jinja
{% if h in (groups['proxmox_all_lxc'] | default([])) and hv.proxmox_cores is defined %} · VMID {{ hv.proxmox_vmid }} · {{ hv.proxmox_cores }} core{{ 's' if hv.proxmox_cores | int != 1 }} · {{ (hv.proxmox_memory | int / 1024) | round(1) ~ ' GB' if hv.proxmox_memory | int >= 1024 else hv.proxmox_memory ~ ' MB' }} · {{ hv.proxmox_rootfs.size | regex_replace('G$', ' GB') }}{% endif +%}
```

- regels 95-101 (`{% if pve_lxc_defaults is defined %}` … `{% endif %}`) worden:

```jinja
---

De machines op pve01 maakt en beschrijft OpenTofu, in `tofu/proxmox/`. Hoe:
[Machine toevoegen](/runbooks/toevoegen/machine/).
```

Run: `ansible-playbook playbooks/docs.yml --check` en daarna zonder `--check` maar alleen de build: kijk in `docs-site/content/homelab/machines.mdx` dat de regel voor adguard nog `VMID 107 · 1 core · 512 MB · 2 GB` is.
Expected: dezelfde regels als vóór, voor alle vier de containers (ntfy krijgt ze nu ook, uit Proxmox).

- [ ] **Step 7: `proxmox-access.yml`, `site.yml`, `proxmox/main.yml`**

`playbooks/proxmox-access.yml`: de play "Proxmox API access" (regels 11-15, met de rol `proxmox_access`) weg. Header wordt:

```yaml
---
# Bewijst dat het token van Ansible (ansible@pve!automation) de guests ziet,
# zoals de dynamische inventory ze nodig heeft. De rechten zelf staan in
# tofu/proxmox/access.tf.
#
#   ansible-playbook playbooks/proxmox-access.yml
#
# De controle vraagt de guest-agent op via het TOKEN, niet met pvesh. pvesh
# draait als root en slaagt altijd, dus dat bewijst niets over wat de
# inventory-plugin echt ziet.
```

`playbooks/site.yml:9`: de regel `#   proxmox-lxcs.yml       creates missing LXC containers` weg.

`inventory/group_vars/proxmox/main.yml:7`: "(report.yml, proxmox_lxc)" → "(report.yml, proxmox_oci)".

- [ ] **Step 8: Weggooien**

```bash
git rm -r roles/proxmox_lxc roles/proxmox_access playbooks/proxmox-lxcs.yml \
  inventory/group_vars/proxmox/vms.yml inventory/group_vars/proxmox/access.yml
```

Run: `grep -rn "pve_lxcs\|pve_lxc_defaults\|pve_vms\|pve_users\|pve_acls\|proxmox-lxcs\|roles/proxmox_access\|roles/proxmox_lxc" playbooks roles inventory`
Expected: geen uitvoer. (Een commentaar in `pbs/tasks/config.yml` of `proxmox_network` dat "as in proxmox_access" zegt: herschrijf zonder die verwijzing.)

- [ ] **Step 9: Alles nog groen?**

Run: `ansible-playbook playbooks/site.yml --check --limit 'all:!mbp:!semaphore' > /tmp/claude-501/after.txt 2>&1; tail -20 /tmp/claude-501/after.txt`
Expected: `failed=0`; `changed`-tellers gelijk aan stap 1 (behalve de weggevallen `proxmox_access`-taken).

Run: `ansible-playbook playbooks/proxmox-access.yml && ansible-lint && bin/check-vaulted`
Expected: alle drie groen.

Run: `bin/tofu proxmox plan -detailed-exitcode; echo "exit=$?"`
Expected: `exit=0`.

- [ ] **Step 10: Commit**

```bash
git add -A playbooks roles inventory
git commit -m "refactor: Proxmox guests and access live in OpenTofu, not Ansible"
```

---

### Task 9: Docs en TODO

**Files:**
- Modify: `docs-site/content/runbooks/toevoegen/machine.mdx` (nieuwe LXC via OpenTofu; nieuw geval "Een machine aanpassen")
- Modify: `docs-site/content/runbooks/toevoegen/index.mdx` (rij voor het nieuwe geval)
- Modify: `docs-site/content/runbooks/stuk/pve01.mdx` (rampregel; `proxmox-access.yml` is nu een check; `new-guest.yml`-regels)
- Modify: `docs-site/content/runbooks/stuk/dienst.mdx` (herbouw van caddy/adguard: eerst `bin/tofu proxmox apply`)
- Modify: `docs-site/content/runbooks/toegang/werkplek.mdx:214`
- Modify: `TODO.md` (B)

- [ ] **Step 1: Lees elke plek eerst**

Run: `grep -n "new-guest\|pve_lxcs\|lxcs.yml\|vms.yml\|access.yml\|proxmox-access\|proxmox-lxcs" docs-site/content -r`
Pas elke treffer aan naar de nieuwe weg. De regel overal: een container **maken** of **aanpassen** is `tofu/proxmox/`, dan `bin/tofu proxmox apply`; **klaarzetten** is daarna `new-guest.yml`.

- [ ] **Step 2: `toevoegen/machine.mdx`**

Het stuk "nieuwe LXC" krijgt als eerste stap:

````mdx
#### Zet hem in OpenTofu

Een regel in `local.containers` in `tofu/proxmox/containers.tf`: de volgende
vrije `vm_id`, een vast adres, cores, geheugen en schijf. Kijk naar de andere
regels als voorbeeld.

```bash
bin/tofu proxmox plan    # alleen "1 to add"
bin/tofu proxmox apply
```
````

Nieuw geval, met een rij in de geval-tabel van de pagina en van `toevoegen/index.mdx`:

| Jouw situatie | Voorbeeld | Ga naar |
| --- | --- | --- |
| Een machine heeft **meer geheugen, cores of schijf** nodig | docker heeft meer RAM nodig, caddy een grotere schijf | [Machine aanpassen](#een-machine-aanpassen) |

````mdx
## Een machine aanpassen

Meer geheugen, cores of een grotere schijf. Niet in de Proxmox-GUI: dan
wijkt pve01 af van git, en het volgende `plan` wil het terugzetten.

<Steps>

#### Pas het getal aan

VM's in `tofu/proxmox/vms.tf`, containers in `tofu/proxmox/containers.tf`.

#### Kijk wat er zou veranderen

```bash
bin/tofu proxmox plan
```

Alleen dat ene veld, bij die ene machine, als `update in-place`. Staat er
`must be replaced`: **stop**, dat is een lege schijf.

#### Doen, en committen

```bash
bin/tofu proxmox apply
```

Een schijf kan alleen groter, nooit kleiner. Geheugen van een VM geldt na een
herstart.

</Steps>
````

In "Goed om te weten" van die pagina:

```markdown
### Waarom OpenTofu voor de machines

OpenTofu weet wat hij gemaakt heeft en toont vooraf wat hij gaat doen. Het
Ansible van voordien maakte alleen wat ontbrak en raakte een bestaande machine
nooit aan, dus meer geheugen was klikken in de GUI en daarna overtikken. PBS
blijft de inhoud bewaren; OpenTofu de vorm.
```

- [ ] **Step 3: `stuk/pve01.mdx`**

In het herbouwpad, vóór de stap die guests terugzet, een Callout:

```mdx
<Callout type="warning">
**Eerst PBS, dan OpenTofu.** Zet alle guests terug uit PBS vóór je
`bin/tofu proxmox plan` draait. Wil OpenTofu dan een guest *aanmaken* die uit
PBS moet komen: stop. Anders neemt hij het nummer in met een lege machine.
Een plan na het terugzetten moet `No changes` zeggen.
</Callout>
```

De regel `ansible-playbook playbooks/proxmox-access.yml` (regel 138): de uitleg eromheen wordt "het token van Ansible testen; de rechten zelf zet `bin/tofu proxmox apply`". En `tofu@pve` opnieuw aanmaken na een herbouw: verwijs naar de commando's uit dit plan (Task 1), in het runbook letterlijk overgenomen.

De sectie "Waarom `proxmox-access.yml` via het token test" (regel 734) blijft; alleen de verwijzing naar de rol weg.

- [ ] **Step 4: `stuk/dienst.mdx`**

Waar caddy of adguard **opnieuw gebouwd** wordt (regels ~153, ~263, ~271): vóór `new-guest.yml` de stap `bin/tofu proxmox apply` (maakt de verdwenen container opnieuw). De sectie "`new-guest.yml` maakt alleen wat je noemt" (regel 380) wordt "OpenTofu maakt de container, `new-guest.yml` zet hem klaar".

- [ ] **Step 5: `toegang/werkplek.mdx:214`**

"Draai eerst `new-guest.yml`" → "Maak hem eerst met `bin/tofu proxmox apply` en draai dan `new-guest.yml`".

- [ ] **Step 6: TODO.md**

In B: het Proxmox-punt en zijn twee subpunten (`prevent_destroy`, oude plek weghalen) afvinken, met "Deel 2 klaar op <datum>; ntfy (ct 109) blijft bij roles/proxmox_oci." Het `/dev/net/tun`-punt bovenaan B afvinken: "Ansible zet ze nu als root (roles/proxmox_tun)."

- [ ] **Step 7: Docs genereren en bouwen**

Run: `ansible-playbook playbooks/docs.yml`
Expected: `failed=0`.

Run: `cd docs-site && npm run build`
Expected: build zonder fouten.

- [ ] **Step 8: Commit**

```bash
git add docs-site/content TODO.md
git commit -m "docs: Proxmox guests via OpenTofu"
```
