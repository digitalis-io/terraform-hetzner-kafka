# Specification of the kafka-cluster servers, SSH keys and placement groups
# (#8, ADR-0003, ADR-0005).
#
# Executable realisation: modules/kafka-cluster/tests/servers.tftest.hcl
# (`tofu test`, plan-only, mocked hcloud provider). These scenarios vary module
# inputs, compare two plans or expect the plan to fail, which
# terraform-compliance cannot do against a single plan JSON, hence @tofu-test.
# The input-independent server policy lives in servers_policy.feature.
#
# Read-only: plans never apply, nothing is persisted, no cleanup is needed.
# Scenarios are independent and parallel-safe.

@tofu-test
Feature: Kafka servers with stable identity and host anti-affinity

  Every node in the node map becomes one server on its own physical host,
  reachable over SSH and attached to the private network at a fixed address.

  Background:
    Given a cluster named "kafka-test" in fsn1 with one SSH key

  Scenario: Combined cluster servers
    Given 3 brokers without dedicated controllers
    When the plan is generated
    Then 3 servers are created with the broker server type
    And one spread placement group is created
    And each server has the firewall attached and a private IP in the subnet

  Scenario: Dedicated controller servers
    Given 3 brokers and 3 dedicated controllers
    When the plan is generated
    Then 6 servers are created
    And the controllers use the controller server type
    And two spread placement groups are created

  Scenario: Existing and new SSH keys are combined
    Given one existing SSH key and one new public key
    When the plan is generated
    Then the new key is created in the project
    And every server receives both keys

  Scenario: Scale out keeps existing servers
    Given an applied cluster with 3 brokers
    When the broker count changes to 4
    Then the plan adds only broker-4 and changes no existing server

  Scenario: No SSH keys
    Given no existing SSH key and no public key
    When the plan is generated
    Then it fails with a validation error requiring at least one SSH key
