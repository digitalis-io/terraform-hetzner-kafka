output "nodes" {
  description = "Map of node key (broker-<n>, controller-<n>) to node attributes: role, node_id, kafka_roles, server_type, private_ip, has_volume, labels."
  value       = local.nodes

  # Cross-variable rules. Enforced here (hard plan failure) instead of
  # cross-variable `validation` blocks so the module keeps supporting
  # OpenTofu/Terraform >= 1.5. Every later resource derives from local.nodes,
  # so a failure here blocks the whole plan.
  precondition {
    condition     = var.dedicated_controllers || local.controller_count <= var.broker_count
    error_message = "controller_count (${local.controller_count}) must be <= broker_count (${var.broker_count}) when dedicated_controllers = false."
  }

  precondition {
    condition     = local.subnet_within_network
    error_message = "subnet_cidr (${var.subnet_cidr}) must be inside network_cidr (${var.network_cidr})."
  }

  precondition {
    condition     = local.location_network_zone[var.location] == var.network_zone
    error_message = "network_zone (${var.network_zone}) does not contain location ${var.location}; expected ${local.location_network_zone[var.location]}."
  }

  precondition {
    condition     = length(var.ssh_key_names) + length(var.ssh_public_keys) > 0
    error_message = "At least one SSH key is required: set ssh_key_names or ssh_public_keys."
  }
}
