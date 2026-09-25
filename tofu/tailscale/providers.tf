# De sleutels komen uit TAILSCALE_OAUTH_CLIENT_ID en
# TAILSCALE_OAUTH_CLIENT_SECRET (bin/tofu). Het is de client "opentofu", niet
# die van roles/tailscale: twee clients, elk zo weinig mogelijk rechten.
provider "tailscale" {}
