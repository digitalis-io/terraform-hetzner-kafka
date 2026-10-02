# Executable realisation of tests/compliance/features/servers.feature (#8).
# Plan-only against a mocked hcloud provider: no credentials, no real
# resources, nothing to clean up. Runs are independent and order-free.

mock_provider "hcloud" {
  # These ids are numeric strings; the generated mock id is random text, which
  # the numeric arguments that consume them (hcloud_network_subnet.network_id,
  # hcloud_server.network_id / firewall_ids / placement_group_id) reject.
  mock_resource "hcloud_network" {
    defaults = { id = "1001" }
  }
  mock_resource "hcloud_firewall" {
    defaults = { id = "2001" }
  }
  mock_resource "hcloud_placement_group" {
    defaults = { id = "3001" }
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

run "combined_cluster_servers" {
  command = plan

  assert {
    condition     = toset(keys(hcloud_server.this)) == toset(["broker-1", "broker-2", "broker-3"])
    error_message = "Expected exactly 3 servers: broker-1..3."
  }

  assert {
    condition     = alltrue([for k, s in hcloud_server.this : s.name == "kafka-test-${k}" && s.server_type == "cpx32"])
    error_message = "Servers must be named <name>-<key> and use broker_server_type."
  }

  assert {
    condition     = length(hcloud_placement_group.this) == 1 && hcloud_placement_group.this["broker"].type == "spread" && hcloud_placement_group.this["broker"].name == "kafka-test-brokers"
    error_message = "Expected one spread placement group kafka-test-brokers."
  }

  assert {
    condition     = alltrue([for s in hcloud_server.this : tolist(s.firewall_ids) == tolist([2001]) && s.placement_group_id == 3001])
    error_message = "Every server must have the firewall and the broker placement group attached."
  }

  assert {
    condition = alltrue([
      for k, s in hcloud_server.this :
      one(s.network).network_id == 1001 && one(s.network).ip == cidrhost("10.0.1.0/24", 9 + tonumber(trimprefix(k, "broker-")))
    ])
    error_message = "Every server must join the network with private IP 10.0.1.(10 + n - 1)."
  }

  assert {
    condition     = alltrue([for s in hcloud_server.this : one(s.public_net).ipv4_enabled && one(s.public_net).ipv6_enabled])
    error_message = "Public IPv4 and IPv6 must be enabled."
  }

  assert {
    condition     = alltrue([for s in hcloud_server.this : s.image == "ubuntu-24.04" && s.location == "fsn1" && s.user_data == null])
    error_message = "Servers must use var.image, var.location and no user_data without volumes."
  }

  assert {
    condition     = alltrue([for s in hcloud_server.this : s.labels == tomap({ cluster = "kafka-test", managed-by = "opentofu", role = "broker" })])
    error_message = "Server labels must come from the node map."
  }
}

run "dedicated_controller_servers" {
  command = plan

  variables {
    dedicated_controllers  = true
    controller_count       = 3
    controller_server_type = "cpx22"
  }

  assert {
    condition     = length(hcloud_server.this) == 6
    error_message = "Expected 6 servers (3 controllers + 3 brokers)."
  }

  assert {
    condition     = alltrue([for k, s in hcloud_server.this : s.server_type == (startswith(k, "controller-") ? "cpx22" : "cpx32")])
    error_message = "Controllers must use controller_server_type and brokers broker_server_type."
  }

  assert {
    condition = (
      toset(keys(hcloud_placement_group.this)) == toset(["broker", "controller"]) &&
      alltrue([for pg in hcloud_placement_group.this : pg.type == "spread"]) &&
      hcloud_placement_group.this["controller"].name == "kafka-test-controllers"
    )
    error_message = "Expected two spread placement groups: brokers and controllers."
  }

  assert {
    condition     = alltrue([for k, s in hcloud_server.this : s.labels["role"] == (startswith(k, "controller-") ? "controller" : "broker")])
    error_message = "Server role label must match its pool."
  }

  assert {
    condition     = output.servers["controller-1"].private_ip == "10.0.1.10" && output.servers["broker-1"].private_ip == "10.0.1.20"
    error_message = "servers output must expose the per-pool private IPs."
  }
}

run "ssh_keys_merged" {
  command = plan

  variables {
    ssh_key_names   = ["operator"]
    ssh_public_keys = { ci = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExampleOnlyNotARealKey ci" }
  }

  assert {
    condition     = hcloud_ssh_key.this["ci"].name == "kafka-test-ci" && hcloud_ssh_key.this["ci"].labels["managed-by"] == "opentofu"
    error_message = "Created SSH keys must be named <name>-<key> and labelled."
  }

  assert {
    condition     = output.ssh_keys == ["operator", "kafka-test-ci"] && alltrue([for s in hcloud_server.this : s.ssh_keys == tolist(["operator", "kafka-test-ci"])])
    error_message = "Servers must receive the existing key then the created key."
  }
}

run "public_keys_only_reads_no_existing_key" {
  command = plan

  variables {
    ssh_key_names   = []
    ssh_public_keys = { ci = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExampleOnlyNotARealKey ci" }
  }

  assert {
    condition     = length(data.hcloud_ssh_key.existing) == 0 && output.ssh_keys == ["kafka-test-ci"]
    error_message = "An empty ssh_key_names must not look up any existing key."
  }
}

run "no_ssh_keys_rejected" {
  command = plan

  variables {
    ssh_key_names   = []
    ssh_public_keys = {}
  }

  expect_failures = [output.nodes]
}

# Plan-level proof of scale-out: both plans are checked against the same
# expected attributes for broker-1..3 (test-only variable scale_out_existing).
# Name, type, location, private IP, labels, placement group and firewall are
# everything the server is built from, so if they match in the 3-broker and
# 4-broker plans, the 3 -> 4 change can only add broker-4. (run.<name> outputs
# of a plan run are unknown in OpenTofu, hence a shared fixture instead.)
run "scale_out_baseline" {
  command = plan

  variables {
    scale_out_existing = {
      broker-1 = "10.0.1.10"
      broker-2 = "10.0.1.11"
      broker-3 = "10.0.1.12"
    }
  }

  assert {
    condition     = toset(keys(hcloud_server.this)) == toset(keys(var.scale_out_existing))
    error_message = "Baseline must plan broker-1..3."
  }

  assert {
    condition = alltrue([
      for k, ip in var.scale_out_existing :
      hcloud_server.this[k].name == "kafka-test-${k}" &&
      hcloud_server.this[k].server_type == "cpx32" &&
      hcloud_server.this[k].location == "fsn1" &&
      one(hcloud_server.this[k].network).ip == ip &&
      hcloud_server.this[k].labels == tomap({ cluster = "kafka-test", managed-by = "opentofu", role = "broker" }) &&
      hcloud_server.this[k].placement_group_id == 3001 &&
      tolist(hcloud_server.this[k].firewall_ids) == tolist([2001])
    ])
    error_message = "Baseline broker-1..3 attributes differ from the fixture."
  }
}

run "scale_out_adds_only_broker_4" {
  command = plan

  variables {
    broker_count = 4
    scale_out_existing = {
      broker-1 = "10.0.1.10"
      broker-2 = "10.0.1.11"
      broker-3 = "10.0.1.12"
    }
  }

  assert {
    condition     = toset(keys(hcloud_server.this)) == setunion(toset(keys(var.scale_out_existing)), toset(["broker-4"]))
    error_message = "Scaling 3 -> 4 must add exactly broker-4."
  }

  assert {
    condition = alltrue([
      for k, ip in var.scale_out_existing :
      hcloud_server.this[k].name == "kafka-test-${k}" &&
      hcloud_server.this[k].server_type == "cpx32" &&
      hcloud_server.this[k].location == "fsn1" &&
      one(hcloud_server.this[k].network).ip == ip &&
      hcloud_server.this[k].labels == tomap({ cluster = "kafka-test", managed-by = "opentofu", role = "broker" }) &&
      hcloud_server.this[k].placement_group_id == 3001 &&
      tolist(hcloud_server.this[k].firewall_ids) == tolist([2001])
    ])
    error_message = "broker-1..3 must be planned with the same attributes as in the 3-broker plan."
  }

  assert {
    condition     = hcloud_server.this["broker-4"].name == "kafka-test-broker-4" && one(hcloud_server.this["broker-4"].network).ip == "10.0.1.13"
    error_message = "broker-4 must be kafka-test-broker-4 at 10.0.1.13."
  }
}
