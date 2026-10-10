terraform {
  # 1.11: tofu/proxmox gebruikt ephemeral variabelen en write-only attributen.
  required_version = ">= 1.11"

  required_providers {
    proxmox = {
      source = "bpg/proxmox"
      # Op de minor vast: voor 1.0 breekt een provider ook in een minor release.
      version = "~> 0.114.0"
    }
  }
}
