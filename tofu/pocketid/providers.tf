# Rechtstreeks naar de docker-host, niet via id.neodata.be: dat loopt over
# Caddy en AdGuard, en die wil je hier niet als voorwaarde.
#
# De sleutel komt uit POCKETID_API_TOKEN (bin/tofu). Het is de STATIC_API_KEY
# van Pocket ID zelf (POCKET_ID_STATIC_API_KEY in files/env/infra.env): daarmee
# is er geen API-sleutel die iemand eerst in de UI moet aanmaken.
provider "pocketid" {
  base_url = "http://192.168.0.15:1411"
}
