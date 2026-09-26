terraform {
  required_version = ">= 1.10"

  required_providers {
    pocketid = {
      source  = "trozz/pocketid"
      version = "~> 2.4"
    }
  }
}
