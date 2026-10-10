terraform {
  # 1.11: tofu/proxmox gebruikt ephemeral variabelen en write-only attributen.
  required_version = ">= 1.11"

  required_providers {
    pocketid = {
      source  = "trozz/pocketid"
      version = "~> 2.4"
    }
  }
}
