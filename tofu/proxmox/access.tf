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
