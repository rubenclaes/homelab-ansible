# De groepen: wie waar mag. Welke groep in welke app mag, staat per client
# in clients.tf (`allowed_user_groups`).
#
# Alleen de groepen zelf staan hier, niet wie erin zit: mensen aanmaken en in
# een groep zetten doe je in de UI van Pocket ID (later NeoGate). Zo raakt
# een apply nooit iemand die daar net is toegevoegd.
#
# Iemand kan in meer dan één groep. Jij zit in `admin` én `gezin`.
#
# `name` komt in de tokens (de groups-claim) en is dus wat een app leest:
# niet hernoemen zonder de apps na te kijken die erop steunen.

resource "pocketid_group" "admin" {
  name          = "admin"
  friendly_name = "Beheer"

  # Apps die een rol uit een claim lezen, maken een nieuw account van deze
  # groep meteen admin. Alleen bij het aanmaken: een bestaand account houdt
  # zijn rol.
  custom_claims = {
    immich_role = "admin"
  }
}

# Wie hier woont.
resource "pocketid_group" "gezin" {
  name          = "gezin"
  friendly_name = "Gezin"
}

# Ouders, broers en zussen: minder dan het gezin.
resource "pocketid_group" "familie" {
  name          = "familie"
  friendly_name = "Familie"
}
