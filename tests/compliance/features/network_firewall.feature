# Specification of the kafka-cluster private network and public firewall
# (#7, ADR-0004).
#
# Executable realisation: modules/kafka-cluster/tests/network_firewall.tftest.hcl
# (`tofu test`, plan-only, mocked hcloud provider). These scenarios vary module
# inputs and one expects the plan to fail, which terraform-compliance cannot
# do against a single plan JSON, hence @tofu-test. The input-independent
# policy checks live in network_firewall_policy.feature (terraform-compliance).
#
# Read-only: plans never apply, nothing is persisted, no cleanup is needed.
# Scenarios are independent and parallel-safe.

@tofu-test
Feature: Private network and SSH-only firewall

  Kafka is PLAINTEXT and listens on every interface, so the only public
  inbound traffic allowed is SSH (and optionally ping) from known addresses.

  Background:
    Given a valid 3-broker cluster configuration

  Scenario: Network and subnet created
    Given default network variables
    When the plan is generated
    Then one private network with range 10.0.0.0/16 is created
    And one cloud subnet 10.0.1.0/24 in the configured network zone is created

  Scenario: Firewall allows SSH from allowlist only
    Given SSH is allowed from 203.0.113.10/32
    When the plan is generated
    Then the firewall allows inbound SSH only from 203.0.113.10/32
    And no inbound rule exists for ports 9092 or 9093

  Scenario: ICMP can be disabled
    Given SSH is allowed from 203.0.113.10/32 and ICMP is disabled
    When the plan is generated
    Then the firewall has only the SSH rule

  Scenario: Empty SSH allowlist
    Given SSH is allowed from nowhere
    When the plan is generated
    Then the firewall has no inbound rules

  Scenario: Subnet outside network
    Given the network is 10.0.0.0/16 and the subnet is 192.168.1.0/24
    When the plan is generated
    Then it fails with a validation error mentioning subnet_cidr
