# Inloggen op Proxmox via Pocket ID: realm `pocketid`, naast PAM. De client
# zelf staat in tofu/pocketid/clients.tf.
#
# root@pam blijft de noodtoegang, en PAM blijft de standaard op de
# loginpagina: ligt Pocket ID (een container op deze machine) plat, dan kom
# je er nog in.
#
# Wie in de groep `admin` van Pocket ID zit, komt bij elke login in de
# Proxmox-groep admin-pocketid (Proxmox plakt de realm achter de naam), en
# die groep is Administrator. groups_overwrite: wie uit `admin` gaat, verliest
# het bij de volgende login.

variable "pocketid_proxmox_client_secret" {
  description = "Client-secret van de client proxmox in Pocket ID. Uit tofu/secrets.env; komt nooit in de state."
  type        = string
  sensitive   = true
  ephemeral   = true
}

resource "proxmox_realm_openid" "pocketid" {
  realm      = "pocketid"
  issuer_url = "https://id.neodata.be"
  client_id  = "proxmox"

  # Write-only: het secret gaat naar Proxmox maar niet in de state. Verander
  # je het secret, verhoog dan de versie, anders stuurt OpenTofu het niet.
  client_key_wo         = var.pocketid_proxmox_client_secret
  client_key_wo_version = 1

  username_claim = "username"
  scopes         = "openid email profile groups"
  query_userinfo = true
  autocreate     = true

  groups_claim      = "groups"
  groups_autocreate = false
  groups_overwrite  = true

  default = false
  comment = "Pocket ID (id.neodata.be)"
}

resource "proxmox_virtual_environment_group" "admin_pocketid" {
  group_id = "admin-pocketid"
  comment  = "Groep admin in Pocket ID"
}

resource "proxmox_acl" "admin_pocketid" {
  path      = "/"
  group_id  = proxmox_virtual_environment_group.admin_pocketid.group_id
  role_id   = "Administrator"
  propagate = true
}
