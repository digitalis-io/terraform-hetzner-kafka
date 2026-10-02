# Executable realisation of tests/compliance/features/network_firewall.feature
# (#7, ADR-0004). Plan-only against a mocked hcloud provider: no credentials,
# no real resources, nothing to clean up. Runs are independent and order-free.

mock_provider "hcloud" {
  # hcloud_network.id is a numeric string; the generated mock id is random
  # text, which hcloud_network_subnet.network_id (a number) rejects.
  mock_resource "hcloud_network" {
    defaults = { id = "1001" }
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

run "network_and_subnet_defaults" {
  command = plan

  assert {
    condition     = hcloud_network.this.ip_range == "10.0.0.0/16" && hcloud_network.this.name == "kafka-test-net"
    error_message = "Network must be kafka-test-net with ip_range 10.0.0.0/16."
  }

  assert {
    condition     = hcloud_network_subnet.this.type == "cloud" && hcloud_network_subnet.this.ip_range == "10.0.1.0/24" && hcloud_network_subnet.this.network_zone == "eu-central"
    error_message = "Subnet must be a cloud subnet 10.0.1.0/24 in eu-central."
  }
}

run "network_and_subnet_custom_ranges" {
  command = plan

  variables {
    location     = "ash"
    network_zone = "us-east"
    network_cidr = "172.16.0.0/12"
    subnet_cidr  = "172.16.8.0/24"
  }

  assert {
    condition     = hcloud_network.this.ip_range == "172.16.0.0/12" && hcloud_network_subnet.this.ip_range == "172.16.8.0/24" && hcloud_network_subnet.this.network_zone == "us-east"
    error_message = "Network and subnet must follow network_cidr, subnet_cidr and network_zone."
  }
}

run "ssh_allowed_from_allowlist_only" {
  command = plan

  assert {
    condition     = hcloud_firewall.this.name == "kafka-test-fw"
    error_message = "Firewall must be named kafka-test-fw."
  }

  assert {
    condition = length([
      for r in hcloud_firewall.this.rule : r
      if r.direction == "in" && r.protocol == "tcp" && r.port == "22" && toset(r.source_ips) == toset(["203.0.113.10/32"])
    ]) == 1
    error_message = "Expected one inbound tcp/22 rule with source 203.0.113.10/32."
  }

  assert {
    condition     = length([for r in hcloud_firewall.this.rule : r if r.direction == "in" && r.protocol == "tcp"]) == 1
    error_message = "tcp/22 must be the only inbound tcp rule."
  }

  assert {
    condition = length([
      for r in hcloud_firewall.this.rule : r
      if r.direction == "in" && contains(["9092", "9093"], coalesce(r.port, "none"))
    ]) == 0
    error_message = "No inbound rule may exist for Kafka ports 9092 or 9093."
  }

  assert {
    condition = length([
      for r in hcloud_firewall.this.rule : r
      if r.direction == "in" && r.protocol == "icmp" && toset(r.source_ips) == toset(["203.0.113.10/32"])
    ]) == 1
    error_message = "allow_icmp defaults to true: expected one inbound ICMP rule from the allowlist."
  }

  assert {
    condition     = alltrue([for r in hcloud_firewall.this.rule : !contains(r.source_ips, "0.0.0.0/0") && !contains(r.source_ips, "::/0")])
    error_message = "No rule may be open to the whole internet."
  }
}

run "icmp_disabled" {
  command = plan

  variables { allow_icmp = false }

  assert {
    condition     = length(hcloud_firewall.this.rule) == 1 && one(hcloud_firewall.this.rule).protocol == "tcp"
    error_message = "With allow_icmp = false only the tcp/22 rule must remain."
  }
}

run "empty_ssh_allowlist_has_no_inbound_rules" {
  command = plan

  variables { ssh_allowed_cidrs = [] }

  assert {
    condition     = length([for r in hcloud_firewall.this.rule : r if r.direction == "in" && r.protocol == "tcp"]) == 0
    error_message = "An empty ssh_allowed_cidrs must produce no inbound tcp rules."
  }

  assert {
    condition     = length(hcloud_firewall.this.rule) == 0
    error_message = "An empty ssh_allowed_cidrs must produce no rules at all (ICMP has no source)."
  }
}

run "labels_on_network_resources" {
  command = plan

  variables { labels = { team = "platform" } }

  assert {
    condition = alltrue([
      for l in [hcloud_network.this.labels, hcloud_firewall.this.labels] :
      l == tomap({ cluster = "kafka-test", managed-by = "opentofu", team = "platform" })
    ])
    error_message = "Network and firewall must carry cluster, managed-by and user labels."
  }
}

run "subnet_outside_network_rejected" {
  command = plan

  variables {
    network_cidr = "10.0.0.0/16"
    subnet_cidr  = "192.168.1.0/24"
  }

  expect_failures = [hcloud_network_subnet.this, output.nodes]
}
