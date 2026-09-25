# OpenTofu, deel 2: Proxmox

25-09-2026. Samen met Ruben afgesproken.

## Doel

Wat er op pve01 **bestaat** staat in git, en OpenTofu houdt het zo: de vier
VM's, de vier Debian-containers, en de gebruiker, rol en rechten van Ansible.
Wat er **in** een machine draait blijft bij Ansible.

Dit vervangt de afschriften die niets leest (`vms.yml`) of alleen aanmaakt en
nooit aanpast (`pve_lxcs`, `access.yml`), en de rollen daarachter.

Bovenop PBS, niet in de plaats: PBS bewaart de inhoud van de schijven,
OpenTofu de vorm (cores, geheugen, schijfgrootte, netwerk, rechten).

Klaar als:

- `bin/tofu proxmox plan` zegt **No changes** tegen pve01.
- Een guest aanpassen (bv. meer geheugen) gaat via een getal in
  `tofu/proxmox/`, `plan`, `apply`, en niet meer via de GUI plus overtikken.
- `vms.yml`, `access.yml`, `pve_lxcs`, `roles/proxmox_lxc`,
  `roles/proxmox_access` en `playbooks/proxmox-lxcs.yml` zijn weg,
  `playbooks/proxmox-access.yml` is alleen nog de controle van het token, en
  niets breekt.
- De `/dev/net/tun`-regels van ct 107 en 108 zijn geen handstap meer.

## Beslist

| Vraag | Keuze | Waarom |
| --- | --- | --- |
| Project | `tofu/proxmox/`, eigen state `proxmox/terraform.tfstate` in dezelfde R2-bucket, zelfde backend en versleuteling als deel 1 | een fout in Proxmox raakt Tailscale niet |
| Provider | `bpg/proxmox`, vast op `~> 0.114` | de gangbare provider; importeert VM's, containers, gebruikers, rollen en ACL's |
| Verbinding | `https://192.168.0.10:8006`, `insecure = true` | rechtstreeks, zonder Caddy of AdGuard: die draaien op de containers die je hiermee misschien net moet herstellen. Het certificaat is dat van pve01 zelf (self-signed), op het LAN |
| Wie is OpenTofu op Proxmox | eigen gebruiker `tofu@pve` met eigen rol `OpenTofu` en een token (`privsep=0`), met de hand aangemaakt | een tool beheert zijn eigen sleutel niet: één fout en hij sluit zichzelf buiten. Los van `ansible@pve`, zodat je het ene kan intrekken zonder het andere |
| Geheim | `PROXMOX_VE_API_TOKEN` erbij in `tofu/secrets.env` | zelfde plek als de rest |
| VM's | één `resource`-blok per VM in `vms.tf` | vier machines die elk anders zijn (PBS met datastore-schijf, haos met EFI); een lus zou meer verbergen dan hij bespaart |
| Containers | één `for_each` over een map in `containers.tf`, met gedeelde standaardwaarden | vier bijna gelijke Debian-containers; zelfde vorm als `pve_lxcs` nu |
| Rechten | `ansible@pve`, rol `AnsibleAutomation` en zijn ACL in `access.tf` | de token van Ansible zelf niet: een tokengeheim kan je niet importeren |
| Niet in OpenTofu | `tofu@pve` zelf, `root@pam`, `rubenclaes@pam`, ntfy (ct 109, `roles/proxmox_oci`), storage, back-upjobs, meldingen, netwerk (`proxmox_datacenter`) | zie "Wat bij Ansible blijft" |
| `/dev/net/tun` | Ansible, als root op pve01 | Proxmox laat een apparaat alleen door `root@pam` doorgeven, en een token telt niet als root. Ansible heeft al root op pve01 |

## Hoe het eruitziet

```
tofu/proxmox/
  versions.tf        # tofu >= 1.10, bpg/proxmox ~> 0.114
  backend.tf         # R2 + slot + versleuteling (zoals deel 1)
  providers.tf       # endpoint, insecure; token uit env
  vms.tf             # 100 pbs, 101 haos, 102 docker-grafana-stack, 103 docker
  containers.tf      # 104 semaphore, 106 caddy, 107 adguard, 108 tailscale
  access.tf          # ansible@pve, rol AnsibleAutomation, ACL op /
  .terraform.lock.hcl
```

### Vangnetten

- **`prevent_destroy`** op elke guest. Zegt een plan ooit *replace* voor een
  VM, dan is dat een lege schijf; OpenTofu weigert dan in plaats van het te
  doen.
- **`ignore_changes` alleen met een reden erbij**, in een commentaar per
  regel. Alleen voor wat Proxmox zelf zet of wat met de hand beheerd blijft
  (bv. de HTML in `description` van de helper-scripts). Niet om een lastig
  plan stil te krijgen.
- **Eerst importeren, dan leeg plan, dan pas opruimen.** Zelfde volgorde als
  deel 1. De oude bronnen gaan pas weg als `plan` leeg is.
- **Rampregel.** Na een herbouw van pve01: eerst alles terugzetten uit PBS,
  dan pas `bin/tofu proxmox plan`. Wil hij dan een guest *aanmaken* die uit
  PBS moet komen: stoppen. Anders neemt OpenTofu het nummer in met een lege
  machine. Dit komt in het runbook "pve01 herbouwen".

### Wat bij Ansible blijft

| Wat | Waar | Waarom |
| --- | --- | --- |
| `tofu@pve` en zijn token | handstap, beschreven in het runbook | zie "Beslist" |
| `root@pam`, `rubenclaes@pam` | niemand, zoals nu | PAM-accounts van voor deze repo; beheren kan je buitensluiten |
| ntfy (ct 109) | `roles/proxmox_oci` | zijn geheimen staan in de Ansible-vault; verhuizen zet hetzelfde geheim op twee plekken |
| storage, back-upjobs, meldingen, netwerk | `proxmox_datacenter`, `proxmox_network` | werkt; buiten dit deel |
| `/dev/net/tun` op ct 107 en 108 | nieuwe kleine taak in de Proxmox-play, als root | de twee `lxc.*`-regels in `/etc/pve/lxc/<id>.conf`, en de container herstarten als ze nieuw zijn |

### Wat meeverandert

`pve_lxcs` wordt ook gelezen buiten `roles/proxmox_lxc`:

| Wie | Nu | Straks |
| --- | --- | --- |
| `playbooks/new-guest.yml` | maakt de container uit `pve_lxcs`, dan bootstrap | alleen nog bootstrap. Aanmaken: een regel in `containers.tf`, `bin/tofu proxmox apply`, dan `new-guest.yml -e guest=<naam>` |
| `playbooks/restore-drill.yml` | kiest de container en zijn opslag uit `pve_lxcs` | uit de dynamische inventory (de guests die Proxmox als LXC kent) |
| `playbooks/docs.yml` (pagina Machines) | cores, geheugen, schijf uit `pve_lxcs` | live uit Proxmox, zoals de adressen nu al |
| `roles/proxmox_oci` | bridge, gateway, zoekdomein uit `pve_lxc_defaults` | een klein `pve_guest_network` in `lxcs.yml`. Dezelfde drie waarden staan ook in `containers.tf`; zo blijft het tot ntfy ook verhuist |

## Stappen

Niets verandert op pve01 voor stap 5. Tot dan is terug gaan: `tofu/proxmox/`
weggooien.

1. **Handstap op pve01** (Ruben, met de commando's uit het plan): gebruiker
   `tofu@pve`, rol `OpenTofu`, ACL op `/`, token. Het token in
   `tofu/secrets.env`.
2. **Project**: `versions.tf`, `backend.tf`, `providers.tf`; `init`, lock
   voor mac en linux.
3. **Rechten importeren**: `access.tf`, import, leeg plan.
4. **Containers importeren**: `containers.tf`, import, leeg plan.
5. **VM's importeren**: `vms.tf`, import, leeg plan. De lastigste stap: een
   VM heeft veel velden. Pas de code aan tot het plan leeg is; nooit een plan
   toepassen dat iets vervangt.
6. **`/dev/net/tun` naar Ansible**: de taak, een droogloop die voor 107 en
   108 niets wil veranderen (de regels staan er al).
7. **Opruimen**: `vms.yml`, `access.yml`, `pve_lxcs`, de twee rollen, de twee
   playbooks en hun import in `site.yml`; `new-guest.yml`,
   `restore-drill.yml`, `docs.yml` en `proxmox_oci` aangepast. De controle
   uit `proxmox-access.yml` (ziet de token van Ansible de guest-agents?)
   blijft als kleine check, want de dynamische inventory hangt ervan af.
8. **Docs en TODO**: runbooks "Machine toevoegen" en "pve01 herbouwen"
   (met de rampregel), de pagina Machines, TODO B.

## Testen

- Na stap 3, 4 en 5: `bin/tofu proxmox plan` leeg.
- Een echte wijziging als proef, na stap 5: een onschuldig veld dat niets
  herstart (bv. een notitie of tag op ct 106, caddy) erbij en weer weg.
  `plan` toont alleen dat veld, `apply` werkt, daarna weer leeg.
- `prevent_destroy`: een `tofu plan -destroy` moet weigeren.
- Stap 6: `ansible-playbook playbooks/site.yml --limit pve01 --check` meldt
  niets voor de tun-regels.
- Na stap 7: `ansible-playbook playbooks/site.yml --check`, `docs.yml`,
  `restore-drill.yml` (echte drill op adguard) en `ansible-lint` groen.
- `bin/tofu tailscale plan` nog steeds leeg (deel 1 niet geraakt).

## Goed om te weten

- **De token van `tofu@pve` mag veel**, ook rechten uitdelen
  (`Permissions.Modify`): zonder kan hij de ACL van Ansible niet beheren.
  Daarom staat hij alleen in de vault en draait OpenTofu alleen op de mbp.
- **Een VM importeren is precies werk.** De provider kent veel velden. Liever
  een paar velden letterlijk overnemen dan `ignore_changes` breed zetten.
- **Niet in dit deel:** ntfy (ct 109), de datacenter-instellingen, PBS
  (deel 3), een geplande `plan` in Semaphore.
