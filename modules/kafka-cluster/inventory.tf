# #10 Ansible inventory handoff (ADR-0002). Rendered from local.nodes and the
# servers' public IPv4; exported as output.inventory. No secrets.

locals {
  # Kafka nodes running each KRaft process role, keyed by server name.
  # kafka_brokers / kafka_controllers child groups let operators target one
  # role (`--limit kafka_controllers`, controllers-first rolling restarts).
  # The axonops.axonops kafka role does not need them: it builds its own
  # kafka__group_* groups from kafka_node_roles.
  inventory_role_groups = {
    for role in ["broker", "controller"] : "kafka_${role}s" => {
      hosts = { for k, n in local.nodes : hcloud_server.this[k].name => {} if contains(n.kafka_roles, role) }
    }
  }

  # Structured inventory, serialised with yamlencode() inside the template so
  # the output is always valid YAML with deterministic (sorted) key order.
  inventory = {
    kafka = {
      hosts = {
        for k, n in local.nodes : hcloud_server.this[k].name => {
          ansible_host     = hcloud_server.this[k].ipv4_address
          ansible_user     = "root"
          kafka_node_id    = n.node_id
          kafka_node_roles = n.kafka_roles
          # Private IP: Kafka advertises it; never ansible_default_ipv4 (public).
          kafka_node_ip = n.private_ip
        }
      }
      vars = {
        kafka_axonops_cluster_name = var.name
      }
      children = local.inventory_role_groups
    }
  }

  # Broker private IPs on the PLAINTEXT listener, ordered by KRaft node.id.
  # Zero-padded ids make the lexical sort numeric (broker-10 after broker-9).
  bootstrap_servers = join(",", [
    for entry in sort([
      for n in local.nodes : format("%06d|%s:9092", n.node_id, n.private_ip) if contains(n.kafka_roles, "broker")
    ]) : split("|", entry)[1]
  ])
}
