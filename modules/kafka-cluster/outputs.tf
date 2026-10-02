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

output "network_id" {
  description = "ID of the Hetzner private network (hcloud_network)."
  value       = hcloud_network.this.id
}

output "subnet_id" {
  description = "ID of the node subnet (hcloud_network_subnet), formatted as NETWORK_ID-IP_RANGE."
  value       = hcloud_network_subnet.this.id
}

output "firewall_id" {
  description = "ID of the public-interface firewall. Pass to hcloud_server.firewall_ids to apply it."
  value       = hcloud_firewall.this.id
}

output "servers" {
  description = "Map of node key (broker-<n>, controller-<n>) to server attributes: id, name, public_ipv4, public_ipv6, private_ip, volume_id (null when the node has no data volume)."
  value = {
    for k, s in hcloud_server.this : k => {
      id          = s.id
      name        = s.name
      public_ipv4 = s.ipv4_address
      public_ipv6 = s.ipv6_address
      private_ip  = local.nodes[k].private_ip
      volume_id   = try(hcloud_volume.this[k].id, null)
    }
  }
}

output "placement_group_ids" {
  description = "Map of pool (broker, controller) to spread placement group ID. controller is present only when dedicated_controllers = true."
  value       = { for k, pg in hcloud_placement_group.this : k => pg.id }
}

output "ssh_keys" {
  description = "Names of every SSH key injected into the servers: ssh_key_names as given, then the keys created from ssh_public_keys (<name>-<key>)."
  value       = local.ssh_keys
}

output "inventory" {
  description = "Ansible YAML inventory (ADR-0002): group kafka with one host per server (ansible_host = public IPv4, ansible_user = root, kafka_node_id, kafka_node_roles, kafka_node_ip = private IP), group var kafka_axonops_cluster_name, and child groups kafka_brokers / kafka_controllers. Contains no secrets."
  value = templatefile("${path.module}/templates/inventory.yaml.tftpl", {
    cluster_name = var.name
    inventory    = local.inventory
  })
}

output "bootstrap_servers" {
  description = "Comma-separated Kafka bootstrap servers (<private_ip>:9092) of every node with the broker role, ordered by node ID. Reachable from the private network only."
  value       = local.bootstrap_servers
}
