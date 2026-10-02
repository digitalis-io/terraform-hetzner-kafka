# Network and firewall policy checked by terraform-compliance against the
# plan JSON of the root that calls modules/kafka-cluster (ADR-0004).
# Holds for any valid input, so it runs on whatever plan CI produces.
# Input-specific scenarios live in network_firewall.feature (@tofu-test).
#
# Read-only against the plan: nothing is applied or persisted, no cleanup is
# needed. Scenarios are independent and parallel-safe.

Feature: Kafka never reaches the public internet

  Kafka listeners must only be reachable over the private network, and every
  Hetzner resource must be traceable to this tooling.

  Scenario: No firewall rule opens a Kafka port
    Given I have hcloud_firewall defined
    When it contains rule
    And it contains port
    Then its value must not match the "^(9092|9093)(-.*)?$" regex

  Scenario: No firewall rule is open to the whole internet
    Given I have hcloud_firewall defined
    When it contains rule
    And it contains source_ips
    Then its value must not match the "/([0-7])$" regex

  Scenario: Nodes use a cloud subnet
    Given I have hcloud_network_subnet defined
    Then it must contain type
    And its value must be cloud

  Scenario Outline: Resources are labelled as managed by OpenTofu
    Given I have <resource> defined
    Then it must contain labels
    And it must contain managed-by
    And its value must be opentofu

    Examples:
      | resource        |
      | hcloud_network  |
      | hcloud_firewall |
