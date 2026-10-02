# Executable realisation of tests/compliance/features/node_map.feature.
# Plan-only against a mocked hcloud provider: no credentials, no real
# resources, nothing to clean up. Runs are independent and order-free.

mock_provider "hcloud" {}

variables {
  name               = "kafka-test"
  location           = "fsn1"
  network_zone       = "eu-central"
  broker_server_type = "cpx32"
  ssh_key_names      = ["operator"]
  ssh_allowed_cidrs  = ["203.0.113.10/32"]
}

run "combined_three_node_cluster" {
  command = plan

  variables {
    broker_count          = 3
    dedicated_controllers = false
  }

  assert {
    condition     = toset(keys(output.nodes)) == toset(["broker-1", "broker-2", "broker-3"])
    error_message = "Expected exactly broker-1, broker-2, broker-3."
  }

  assert {
    condition     = alltrue([for n in values(output.nodes) : n.kafka_roles == tolist(["broker", "controller"])])
    error_message = "Every combined node must run [broker, controller]."
  }

  assert {
    condition     = [for k in ["broker-1", "broker-2", "broker-3"] : output.nodes[k].node_id] == [1, 2, 3]
    error_message = "Combined node IDs must be 1, 2, 3."
  }

  assert {
    condition     = [for k in ["broker-1", "broker-2", "broker-3"] : output.nodes[k].private_ip] == ["10.0.1.10", "10.0.1.11", "10.0.1.12"]
    error_message = "Combined private IPs must be cidrhost(subnet_cidr, 10 + index)."
  }

  assert {
    condition     = alltrue([for n in values(output.nodes) : n.has_volume == false && n.server_type == "cpx32" && n.role == "broker"])
    error_message = "Default nodes are brokers on cpx32 without volumes."
  }
}

run "combined_five_brokers_three_controllers" {
  command = plan

  variables {
    broker_count          = 5
    controller_count      = 3
    dedicated_controllers = false
  }

  assert {
    condition     = alltrue([for k in ["broker-1", "broker-2", "broker-3"] : output.nodes[k].kafka_roles == tolist(["broker", "controller"])])
    error_message = "broker-1..3 must run [broker, controller]."
  }

  assert {
    condition     = alltrue([for k in ["broker-4", "broker-5"] : output.nodes[k].kafka_roles == tolist(["broker"])])
    error_message = "broker-4..5 must run [broker] only."
  }

  assert {
    condition     = length(output.nodes) == 5
    error_message = "Combined mode must not create controller-only nodes."
  }
}

run "dedicated_controllers" {
  command = plan

  variables {
    broker_count           = 3
    controller_count       = 3
    dedicated_controllers  = true
    controller_server_type = "cpx22"
    volume_size_gb         = 100
  }

  assert {
    condition     = [for k in ["controller-1", "controller-2", "controller-3"] : output.nodes[k].node_id] == [1, 2, 3]
    error_message = "Controller IDs must be 1..3."
  }

  assert {
    condition     = alltrue([for k in ["controller-1", "controller-2", "controller-3"] : output.nodes[k].kafka_roles == tolist(["controller"]) && output.nodes[k].server_type == "cpx22" && !output.nodes[k].has_volume])
    error_message = "Controllers must run [controller] on controller_server_type without volumes."
  }

  assert {
    condition     = [for k in ["broker-1", "broker-2", "broker-3"] : output.nodes[k].node_id] == [101, 102, 103]
    error_message = "Dedicated broker IDs must be 101..103."
  }

  assert {
    condition     = alltrue([for k in ["broker-1", "broker-2", "broker-3"] : output.nodes[k].kafka_roles == tolist(["broker"]) && output.nodes[k].has_volume])
    error_message = "Dedicated brokers must run [broker] and have a volume when volume_size_gb > 0."
  }

  assert {
    condition     = output.nodes["controller-1"].private_ip == "10.0.1.10" && output.nodes["broker-1"].private_ip == "10.0.1.20"
    error_message = "Controllers start at host 10, dedicated brokers at host 20."
  }

  assert {
    condition     = output.nodes["broker-1"].labels == { cluster = "kafka-test", managed-by = "opentofu", role = "broker" }
    error_message = "Node labels must carry cluster, managed-by and role."
  }
}

run "dedicated_controller_type_defaults_to_broker_type" {
  command = plan

  variables {
    broker_count          = 1
    controller_count      = 1
    dedicated_controllers = true
  }

  assert {
    condition     = output.nodes["controller-1"].server_type == "cpx32"
    error_message = "Null controller_server_type must fall back to broker_server_type."
  }
}

run "single_node_combined_cluster" {
  command = plan

  variables {
    broker_count     = 1
    controller_count = 1
    ssh_key_names    = []
    ssh_public_keys  = { operator = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExampleOnlyNotARealKey operator" }
  }

  assert {
    condition     = toset(keys(output.nodes)) == toset(["broker-1"]) && output.nodes["broker-1"].kafka_roles == tolist(["broker", "controller"])
    error_message = "A single combined node must run [broker, controller]."
  }
}

run "maximum_cluster_size" {
  command = plan

  variables {
    broker_count          = 10
    controller_count      = 5
    dedicated_controllers = true
    subnet_cidr           = "10.0.1.0/27"
  }

  assert {
    condition     = length(output.nodes) == 15 && output.nodes["broker-10"].private_ip == "10.0.1.29" && output.nodes["broker-10"].node_id == 110
    error_message = "10 brokers + 5 controllers must fit a /27 with broker-10 at .29 and ID 110."
  }
}

run "combined_one_broker_defaults_to_one_controller" {
  command = plan

  variables {
    broker_count = 1
  }

  assert {
    condition     = length(output.nodes) == 1 && output.nodes["broker-1"].kafka_roles == tolist(["broker", "controller"])
    error_message = "With controller_count = null, a 1-broker combined cluster must have 1 controller."
  }
}

run "combined_two_brokers_defaults_to_one_controller" {
  command = plan

  variables {
    broker_count = 2
  }

  assert {
    condition     = output.nodes["broker-1"].kafka_roles == tolist(["broker", "controller"]) && output.nodes["broker-2"].kafka_roles == tolist(["broker"])
    error_message = "With controller_count = null, a 2-broker combined cluster must have 1 controller (broker-1)."
  }
}

run "combined_four_brokers_defaults_to_three_controllers" {
  command = plan

  variables {
    broker_count = 4
  }

  assert {
    condition     = length([for n in values(output.nodes) : n if contains(n.kafka_roles, "controller")]) == 3
    error_message = "With controller_count = null, a 4-broker combined cluster must have 3 controllers."
  }
}

run "dedicated_defaults_to_three_controllers" {
  command = plan

  variables {
    broker_count          = 1
    dedicated_controllers = true
  }

  assert {
    condition     = toset([for k, n in output.nodes : k if n.role == "controller"]) == toset(["controller-1", "controller-2", "controller-3"])
    error_message = "With controller_count = null, dedicated mode must create 3 controllers."
  }
}
