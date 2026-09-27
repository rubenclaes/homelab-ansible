# Instellingen van Pocket ID zelf. Alleen wat hier staat, beheert OpenTofu;
# elke andere instelling blijft wat de UI ervan maakte.

resource "pocketid_application_config" "this" {
  # Niemand maakt zelf een account: mensen komen erbij via de UI of NeoGate.
  allow_user_signups = "disabled"

  # Pocket ID heeft geen mailserver, dus zonder dit is geen enkel adres
  # "geverifieerd". Vaultwarden weigert dan elke login, en Immich en
  # Shelfmark koppelen geen bestaand account. Een beheerder vult het adres
  # in, dus het klopt.
  emails_verified = "true"

  # Hoort bij de regel hierboven, anders is het een gat: kan iemand zijn eigen
  # mailadres wijzigen, dan vult hij dat van een ander in en neemt hij diens
  # account over in elke app die op mailadres koppelt. Passkeys beheren kan
  # iedereen nog zelf; naam en adres wijzig jij (of NeoGate).
  allow_own_account_edit = "false"
}
