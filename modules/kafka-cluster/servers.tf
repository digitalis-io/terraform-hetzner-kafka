# One spread placement group per pool (ADR-0003): brokers always, controllers
# only in dedicated mode. A spread group puts each member on a different
# physical host and holds at most 10 servers, which bounds broker_count.
resource "hcloud_placement_group" "this" {
  for_each = toset(var.dedicated_controllers ? ["broker", "controller"] : ["broker"])

  name   = "${var.name}-${each.key}s"
  type   = "spread"
  labels = merge(local.base_labels, { role = each.key })
}

locals {
  # Per-node cloud-init. null for every node until #9 renders the volume-mount
  # user_data for nodes with has_volume = true. Changes are ignored after
  # creation (lifecycle below), so filling this in never replaces a server.
  user_data = { for k in keys(local.nodes) : k => null }
}

# One server per local.nodes entry, keyed broker-<n> / controller-<n>, so
# resizing a pool only adds or removes tail servers (ADR-0003).
resource "hcloud_server" "this" {
  for_each = local.nodes

  name               = "${var.name}-${each.key}"
  server_type        = each.value.server_type
  image              = var.image
  location           = var.location
  ssh_keys           = local.ssh_keys
  firewall_ids       = [hcloud_firewall.this.id]
  placement_group_id = hcloud_placement_group.this[each.value.role].id
  user_data          = local.user_data[each.key]
  labels             = each.value.labels

  # Public IPv4 is required for Ansible SSH and package/agent egress; IPv6 is
  # free and kept on. Both sit behind hcloud_firewall.this (SSH/ICMP only).
  # Private-only nodes (bastion) are out of MVP scope.
  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }

  # Deterministic private IP from local.nodes (ADR-0004). Kafka advertises it.
  network {
    network_id = hcloud_network.this.id
    ip         = each.value.private_ip
  }

  # The server can only join the network once the subnet exists; the network
  # block references the network, not the subnet, so declare it explicitly.
  depends_on = [hcloud_network_subnet.this]

  lifecycle {
    # ADR-0005: these are create-time-only inputs on Hetzner. A new image
    # release, an edited cloud-init or a rotated SSH key would otherwise force
    # replacement of a stateful Kafka node. Rotate keys with Ansible; rebuild
    # deliberately with `tofu apply -replace`.
    # location and the private network ip are deliberately NOT ignored:
    # changing var.location or toggling dedicated_controllers (which shifts
    # private IP offsets) replaces every node at once. Treat both as
    # cluster-rebuild operations, not routine edits.
    ignore_changes = [user_data, image, ssh_keys]
  }
}
