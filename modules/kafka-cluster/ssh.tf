# SSH keys injected into every server at creation (#8). Two sources, merged:
#   - var.ssh_public_keys: created here as hcloud_ssh_key "<name>-<key>"
#   - var.ssh_key_names:   keys that already exist in the project, looked up
#                          by name. for_each over a set, so an empty list makes
#                          no API call during plan.
# At least one key is enforced by the output.nodes precondition; without one
# Hetzner would e-mail a root password instead.
resource "hcloud_ssh_key" "this" {
  for_each = var.ssh_public_keys

  name       = "${var.name}-${each.key}"
  public_key = each.value
  labels     = local.base_labels
}

data "hcloud_ssh_key" "existing" {
  for_each = toset(var.ssh_key_names)

  name = each.value
}

locals {
  # hcloud_server.ssh_keys accepts key names or IDs. Names are used: they are
  # known at plan time, readable in the plan, and the data source has already
  # failed the plan if an existing key is missing. Order: existing keys (as
  # given), then created keys (sorted by map key).
  ssh_keys = concat(
    [for k in var.ssh_key_names : data.hcloud_ssh_key.existing[k].name],
    [for k in sort(keys(var.ssh_public_keys)) : hcloud_ssh_key.this[k].name],
  )
}
