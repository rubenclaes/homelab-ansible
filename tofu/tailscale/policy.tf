# De toegangsregels van de tailnet. files/tailscale/policy.hujson is de bron;
# een wijziging gaat via `bin/tofu tailscale apply`. Tailscale draait bij elke
# apply de `tests` uit dat bestand, en weigert als er een faalt.
#
# Commentaar telt mee: de provider bewaart HuJSON zoals het is, dus een
# gewijzigd commentaar is ook een (onschuldige) wijziging in het plan.
resource "tailscale_acl" "this" {
  acl = file("${path.module}/../../files/tailscale/policy.hujson")
}
