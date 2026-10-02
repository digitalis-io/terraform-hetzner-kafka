# Executable realisation of tests/compliance/features/input_validation.feature.
# Each run feeds one invalid input and expects the plan to be rejected by the
# named variable validation or by the cross-variable preconditions on
# output.nodes. Plan-only, mocked provider, nothing persisted.

mock_provider "hcloud" {}

variables {
  name               = "kafka-test"
  location           = "fsn1"
  network_zone       = "eu-central"
  broker_server_type = "cpx32"
  broker_count       = 3
  ssh_key_names      = ["operator"]
  ssh_allowed_cidrs  = ["203.0.113.10/32"]
}

run "broker_count_zero_rejected" {
  command = plan
  variables { broker_count = 0 }
  expect_failures = [var.broker_count]
}

run "broker_count_eleven_rejected" {
  command = plan
  variables { broker_count = 11 }
  expect_failures = [var.broker_count]
}

run "broker_count_fractional_rejected" {
  command = plan
  variables { broker_count = 2.5 }
  expect_failures = [var.broker_count]
}

run "controller_count_two_rejected" {
  command = plan
  variables { controller_count = 2 }
  expect_failures = [var.controller_count]
}

run "ssh_allowed_cidrs_any_ipv4_rejected" {
  command = plan
  variables { ssh_allowed_cidrs = ["0.0.0.0/0"] }
  expect_failures = [var.ssh_allowed_cidrs]
}

run "ssh_allowed_cidrs_any_ipv6_rejected" {
  command = plan
  variables { ssh_allowed_cidrs = ["203.0.113.10/32", "::/0"] }
  expect_failures = [var.ssh_allowed_cidrs]
}

run "ssh_allowed_cidrs_empty_accepted" {
  command = plan
  variables { ssh_allowed_cidrs = [] }
  assert {
    condition     = length(output.nodes) == 3
    error_message = "An empty ssh_allowed_cidrs (no public SSH rule) must be accepted."
  }
}

run "ssh_allowed_cidrs_invalid_rejected" {
  command = plan
  variables { ssh_allowed_cidrs = ["not-a-cidr"] }
  expect_failures = [var.ssh_allowed_cidrs]
}

run "subnet_cidr_not_a_cidr_rejected" {
  command = plan
  variables { subnet_cidr = "not-a-cidr" }
  expect_failures = [var.subnet_cidr]
}

run "subnet_cidr_too_small_rejected" {
  command = plan
  variables { subnet_cidr = "10.0.1.0/28" }
  expect_failures = [var.subnet_cidr]
}

run "network_cidr_not_a_cidr_rejected" {
  command = plan
  variables { network_cidr = "10.0.0.0/33" }
  expect_failures = [var.network_cidr]
}

run "name_uppercase_rejected" {
  command = plan
  variables { name = "Kafka" }
  expect_failures = [var.name]
}

run "name_too_long_rejected" {
  command = plan
  variables { name = "a234567890123456789012345678901234567890x" }
  expect_failures = [var.name]
}

run "volume_size_below_minimum_rejected" {
  command = plan
  variables { volume_size_gb = 5 }
  expect_failures = [var.volume_size_gb]
}

run "volume_size_above_maximum_rejected" {
  command = plan
  variables { volume_size_gb = 10241 }
  expect_failures = [var.volume_size_gb]
}

run "volume_size_boundaries_accepted" {
  command = plan
  variables { volume_size_gb = 10240 }
  assert {
    condition     = output.nodes["broker-1"].has_volume
    error_message = "volume_size_gb = 10240 must be accepted."
  }
}

run "location_unknown_rejected" {
  command = plan
  variables { location = "mars1" }
  expect_failures = [var.location]
}

run "ssh_public_key_malformed_rejected" {
  command = plan
  variables { ssh_public_keys = { bad = "not-a-key" } }
  expect_failures = [var.ssh_public_keys]
}

run "combined_more_controllers_than_brokers_rejected" {
  command = plan
  variables {
    broker_count          = 1
    controller_count      = 3
    dedicated_controllers = false
  }
  expect_failures = [output.nodes]
}

run "dedicated_more_controllers_than_brokers_accepted" {
  command = plan
  variables {
    broker_count          = 1
    controller_count      = 3
    dedicated_controllers = true
  }
  assert {
    condition     = length(output.nodes) == 4
    error_message = "Dedicated mode allows controller_count > broker_count."
  }
}

run "subnet_outside_network_rejected" {
  command = plan
  variables {
    network_cidr = "10.0.0.0/16"
    subnet_cidr  = "10.1.1.0/24"
  }
  expect_failures = [output.nodes]
}

run "subnet_wider_than_network_rejected" {
  command = plan
  variables {
    network_cidr = "10.0.1.0/24"
    subnet_cidr  = "10.0.0.0/16"
  }
  expect_failures = [output.nodes]
}

run "network_zone_mismatch_rejected" {
  command = plan
  variables { network_zone = "us-east" }
  expect_failures = [output.nodes]
}

run "no_ssh_key_rejected" {
  command = plan
  variables {
    ssh_key_names   = []
    ssh_public_keys = {}
  }
  expect_failures = [output.nodes]
}
