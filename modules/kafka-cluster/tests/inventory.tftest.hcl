# Executable realisation of tests/compliance/features/inventory.feature (#10).
# The inventory embeds each server's public IPv4, which is unknown at plan, so
# the inventory runs use command = apply against a mocked hcloud provider: the
# mock fabricates resource values locally and never calls the Hetzner API, so
# no credentials are needed and nothing real is created or left behind.
# Runs are independent and order-free.

mock_provider "hcloud" {
  # Numeric ids for arguments that parse them (see servers.tftest.hcl).
  mock_resource "hcloud_network" {
    defaults = { id = "1001" }
  }
  mock_resource "hcloud_firewall" {
    defaults = { id = "2001" }
  }
  mock_resource "hcloud_placement_group" {
    defaults = { id = "3001" }
  }
  # Fixed public IPv4 instead of random mock text, so the inventory is fully
  # deterministic. OpenTofu override_resource cannot target single instances,
  # so all servers share it; tests tie ansible_host to each server's own
  # ipv4_address attribute instead.
  mock_resource "hcloud_server" {
    defaults = { ipv4_address = "198.51.100.1" }
  }
}

variables {
  name               = "kafka-test"
  location           = "fsn1"
  network_zone       = "eu-central"
  broker_server_type = "cpx32"
  broker_count       = 3
  ssh_key_names      = ["operator"]
  ssh_allowed_cidrs  = ["203.0.113.10/32"]
}

run "combined_cluster_inventory" {
  command = apply

  assert {
    condition     = can(yamldecode(output.inventory))
    error_message = "inventory must be valid YAML."
  }

  assert {
    condition     = toset(keys(yamldecode(output.inventory).kafka.hosts)) == toset(["kafka-test-broker-1", "kafka-test-broker-2", "kafka-test-broker-3"])
    error_message = "Group kafka must hold exactly 3 hosts keyed by server name."
  }

  assert {
    condition = alltrue([
      for n in [1, 2, 3] :
      yamldecode(output.inventory).kafka.hosts["kafka-test-broker-${n}"].kafka_node_ip == output.servers["broker-${n}"].private_ip &&
      yamldecode(output.inventory).kafka.hosts["kafka-test-broker-${n}"].kafka_node_ip == "10.0.1.${9 + n}"
    ])
    error_message = "kafka_node_ip must equal each server's private IP."
  }

  assert {
    condition = alltrue([
      for n in [1, 2, 3] :
      yamldecode(output.inventory).kafka.hosts["kafka-test-broker-${n}"].ansible_host == hcloud_server.this["broker-${n}"].ipv4_address &&
      yamldecode(output.inventory).kafka.hosts["kafka-test-broker-${n}"].ansible_host == "198.51.100.1"
    ])
    error_message = "ansible_host must be each server's own public IPv4."
  }

  assert {
    condition = alltrue([
      for n in [1, 2, 3] : yamldecode(output.inventory).kafka.hosts["kafka-test-broker-${n}"].kafka_node_id == n
    ])
    error_message = "kafka_node_id must be the node map's node_id (1..3)."
  }

  assert {
    condition = alltrue([
      for h in yamldecode(output.inventory).kafka.hosts :
      h.kafka_node_roles == ["broker", "controller"] && h.ansible_user == "root"
    ])
    error_message = "Every combined host must have kafka_node_roles [broker, controller] and ansible_user root."
  }

  assert {
    condition     = yamldecode(output.inventory).kafka.vars == { kafka_axonops_cluster_name = "kafka-test" }
    error_message = "Group vars must be exactly kafka_axonops_cluster_name = var.name."
  }

  assert {
    condition = (
      toset(keys(yamldecode(output.inventory).kafka.children.kafka_brokers.hosts)) == toset(["kafka-test-broker-1", "kafka-test-broker-2", "kafka-test-broker-3"]) &&
      toset(keys(yamldecode(output.inventory).kafka.children.kafka_controllers.hosts)) == toset(["kafka-test-broker-1", "kafka-test-broker-2", "kafka-test-broker-3"])
    )
    error_message = "In combined mode every host belongs to both kafka_brokers and kafka_controllers."
  }

  assert {
    condition     = output.bootstrap_servers == "10.0.1.10:9092,10.0.1.11:9092,10.0.1.12:9092"
    error_message = "bootstrap_servers must list every broker's private IP on 9092, ordered by node ID."
  }
}

run "dedicated_controllers_inventory" {
  command = apply

  variables {
    dedicated_controllers = true
  }

  assert {
    condition     = length(yamldecode(output.inventory).kafka.hosts) == 6
    error_message = "Expected 6 hosts: 3 controllers and 3 brokers."
  }

  assert {
    condition = alltrue([
      for n in [1, 2, 3] :
      yamldecode(output.inventory).kafka.hosts["kafka-test-controller-${n}"].kafka_node_roles == ["controller"] &&
      yamldecode(output.inventory).kafka.hosts["kafka-test-controller-${n}"].kafka_node_id == n &&
      yamldecode(output.inventory).kafka.hosts["kafka-test-controller-${n}"].kafka_node_ip == "10.0.1.${9 + n}"
    ])
    error_message = "Controller hosts must have kafka_node_roles [controller], node IDs 1..3 and private IPs .10-.12."
  }

  assert {
    condition = alltrue([
      for n in [1, 2, 3] :
      yamldecode(output.inventory).kafka.hosts["kafka-test-broker-${n}"].kafka_node_roles == ["broker"] &&
      yamldecode(output.inventory).kafka.hosts["kafka-test-broker-${n}"].kafka_node_id == 100 + n
    ])
    error_message = "Broker hosts must have kafka_node_roles [broker] and node IDs 101..103."
  }

  assert {
    condition = (
      toset(keys(yamldecode(output.inventory).kafka.children.kafka_controllers.hosts)) == toset(["kafka-test-controller-1", "kafka-test-controller-2", "kafka-test-controller-3"]) &&
      toset(keys(yamldecode(output.inventory).kafka.children.kafka_brokers.hosts)) == toset(["kafka-test-broker-1", "kafka-test-broker-2", "kafka-test-broker-3"])
    )
    error_message = "kafka_controllers / kafka_brokers must split hosts by KRaft role."
  }

  assert {
    condition     = output.bootstrap_servers == "10.0.1.20:9092,10.0.1.21:9092,10.0.1.22:9092"
    error_message = "bootstrap_servers must list only broker private IPs on 9092 (no controllers)."
  }
}

run "inventory_has_no_secrets" {
  command = apply

  variables {
    dedicated_controllers = true
  }

  # No secret-bearing key or value: credentials stay in Ansible Vault (ADR-0002).
  assert {
    condition     = !can(regex("(?i)(password|passwd|secret|token|key|credential|vault)", output.inventory))
    error_message = "inventory must not contain password, token, key or other secret material."
  }

  # Only the documented contract reaches the hosts: nothing else can leak in.
  assert {
    condition = alltrue([
      for h in yamldecode(output.inventory).kafka.hosts :
      toset(keys(h)) == toset(["ansible_host", "ansible_user", "kafka_node_id", "kafka_node_roles", "kafka_node_ip"])
    ])
    error_message = "Hosts must carry only ansible_host, ansible_user, kafka_node_id, kafka_node_roles and kafka_node_ip."
  }
}

# Edge: 10 brokers. Lexical key order would put broker-10 before broker-2;
# bootstrap_servers must follow numeric node ID order. Private IPs are known
# at plan, so plan is enough.
run "bootstrap_servers_ordered_by_node_id" {
  command = plan

  variables {
    broker_count = 10
  }

  assert {
    condition     = output.bootstrap_servers == join(",", [for i in range(10, 20) : "10.0.1.${i}:9092"])
    error_message = "bootstrap_servers must be ordered by node ID (broker-1..broker-10)."
  }
}
