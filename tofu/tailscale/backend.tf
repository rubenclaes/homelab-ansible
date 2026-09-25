# De state staat in Cloudflare R2, niet in git (geen slot, en hij bevat
# geheimen) en niet op de homelab (ligt pve01 plat, dan is de kaart ook weg).
#
# Het endpoint en de sleutel komen uit env (AWS_ENDPOINT_URL_S3,
# AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY), gezet door bin/tofu.
#
# R2 is geen AWS: de skip_*-regels zetten de AWS-controles uit die R2 niet
# kent, en skip_s3_checksum is nodig omdat R2 de nieuwe checksums van de
# AWS-SDK weigert.

variable "state_passphrase" {
  description = "Passphrase voor de versleuteling van state en plan. Uit tofu/secrets.env."
  type        = string
  sensitive   = true
}

terraform {
  backend "s3" {
    bucket = "homelab-tofu-state"
    key    = "tailscale/terraform.tfstate"
    region = "auto"

    use_lockfile = true

    use_path_style              = true
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_s3_checksum            = true
  }

  # Cloudflare ziet alleen versleutelde bytes. `enforced` weigert een
  # leesbare state of plan te schrijven, ook per ongeluk.
  encryption {
    key_provider "pbkdf2" "main" {
      passphrase = var.state_passphrase
    }

    method "aes_gcm" "main" {
      keys = key_provider.pbkdf2.main
    }

    state {
      method   = method.aes_gcm.main
      enforced = true
    }

    plan {
      method   = method.aes_gcm.main
      enforced = true
    }
  }
}
