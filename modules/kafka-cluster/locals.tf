locals {
  # Hetzner Cloud location -> network zone. Used to reject a subnet zone that
  # cannot host servers in var.location.
  location_network_zone = {
    fsn1 = "eu-central"
    nbg1 = "eu-central"
    hel1 = "eu-central"
    ash  = "us-east"
    hil  = "us-west"
    sin  = "ap-southeast"
  }

  # True when subnet_cidr's base address, masked to network_cidr's prefix
  # length, equals network_cidr's base address (and the subnet is not wider).
  subnet_prefix_length  = try(tonumber(split("/", var.subnet_cidr)[1]), -1)
  network_prefix_length = try(tonumber(split("/", var.network_cidr)[1]), 33)
  subnet_within_network = try(
    local.subnet_prefix_length >= local.network_prefix_length &&
    cidrhost("${cidrhost(var.subnet_cidr, 0)}/${local.network_prefix_length}", 0) == cidrhost(var.network_cidr, 0),
    false
  )

  # Private IP plan (ADR-0004: avoid the subnet gateway, assign
  # cidrhost(subnet_cidr, 10 + index)). Offsets are fixed per pool so that
  # changing one pool's size never renumbers the other:
  #   combined mode:  broker-n     -> host 10 + (n - 1)  (.10 - .19)
  #   dedicated mode: controller-n -> host 10 + (n - 1)  (.10 - .14)
  #                   broker-n     -> host 20 + (n - 1)  (.20 - .29)
  controller_ip_offset = 10
  broker_ip_offset     = var.dedicated_controllers ? 20 : 10

  # Broker node IDs: 1..N in combined mode, 101..(100+N) in dedicated mode.
  broker_node_id_offset = var.dedicated_controllers ? 100 : 0

  # Effective controller count when var.controller_count is null:
  # dedicated -> 3; combined -> 3 if broker_count >= 3, else 1.
  controller_count = var.controller_count != null ? var.controller_count : (
    var.dedicated_controllers || var.broker_count >= 3 ? 3 : 1
  )

  controller_server_type = coalesce(var.controller_server_type, var.broker_server_type)

  base_labels = merge(var.labels, {
    cluster    = var.name
    managed-by = "opentofu"
  })

  controller_nodes = var.dedicated_controllers ? {
    for i in range(1, local.controller_count + 1) : "controller-${i}" => {
      role        = "controller"
      node_id     = i
      kafka_roles = tolist(["controller"])
      server_type = local.controller_server_type
      private_ip  = cidrhost(var.subnet_cidr, local.controller_ip_offset + i - 1)
      has_volume  = false
      labels      = merge(local.base_labels, { role = "controller" })
    }
  } : {}

  broker_nodes = {
    for i in range(1, var.broker_count + 1) : "broker-${i}" => {
      role        = "broker"
      node_id     = local.broker_node_id_offset + i
      kafka_roles = !var.dedicated_controllers && i <= local.controller_count ? tolist(["broker", "controller"]) : tolist(["broker"])
      server_type = var.broker_server_type
      private_ip  = cidrhost(var.subnet_cidr, local.broker_ip_offset + i - 1)
      has_volume  = var.volume_size_gb > 0
      labels      = merge(local.base_labels, { role = "broker" })
    }
  }

  # Single source of truth for servers, volumes and inventory (ADR-0003).
  # Keys are stable (broker-<n>, controller-<n>): resizing a pool only adds or
  # removes tail nodes. Fields:
  #   role        - "broker" or "controller" (pool the node belongs to)
  #   node_id     - KRaft node.id
  #   kafka_roles - KRaft process.roles, e.g. ["broker", "controller"]
  #   server_type - Hetzner server type
  #   private_ip  - cidrhost(subnet_cidr, 10 + index), see offsets above
  #   has_volume  - true when a data volume is attached (brokers only)
  #   labels      - Hetzner labels for the node's resources
  nodes = merge(local.controller_nodes, local.broker_nodes)
}
