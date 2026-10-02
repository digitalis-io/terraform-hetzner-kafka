# Private network for broker/controller traffic (ADR-0004). Kafka listeners
# (9092/9093) are reachable only here; Hetzner firewalls do not filter
# private-network traffic.
resource "hcloud_network" "this" {
  name     = "${var.name}-net"
  ip_range = var.network_cidr
  labels   = local.base_labels
}

resource "hcloud_network_subnet" "this" {
  network_id   = hcloud_network.this.id
  type         = "cloud"
  network_zone = var.network_zone
  ip_range     = var.subnet_cidr

  lifecycle {
    # Same rule as output.nodes; repeated here so the subnet itself refuses
    # to plan when it would sit outside the network.
    precondition {
      condition     = local.subnet_within_network
      error_message = "subnet_cidr (${var.subnet_cidr}) must be inside network_cidr (${var.network_cidr})."
    }
  }
}
