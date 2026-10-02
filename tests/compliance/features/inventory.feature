# Specification of the Ansible inventory handoff (#10, ADR-0002).
#
# Executable realisation: modules/kafka-cluster/tests/inventory.tftest.hcl
# (`tofu test`, mocked hcloud provider). The inventory and bootstrap servers are
# module outputs, not resources, so terraform-compliance cannot inspect them;
# hence @tofu-test. The inventory embeds public IPv4s, unknown at plan, so the
# inventory scenarios run `apply` against the mock provider, which fabricates
# values locally and never calls Hetzner.
#
# Nothing real is created or persisted, so no cleanup is needed.
# Scenarios are independent and parallel-safe.

@tofu-test
Feature: Ansible inventory for the Kafka role

  The module hands the cluster to Ansible as an inventory that tells every
  host its KRaft identity and the private address Kafka must advertise, and
  publishes the broker bootstrap list for clients on the private network.

  Background:
    Given a cluster named "kafka-test" in fsn1 with one SSH key

  Scenario: Inventory for combined cluster
    Given 3 brokers without dedicated controllers
    When the inventory is rendered
    Then it is valid YAML with 3 hosts under group kafka
    And each host has kafka_node_ip equal to its private IP
    And each host has kafka_node_roles [broker, controller]
    And the cluster name is set for the whole group

  Scenario: Inventory for dedicated controllers
    Given 3 brokers and 3 dedicated controllers
    When the inventory is rendered
    Then controller hosts have kafka_node_roles [controller]
    And broker hosts have kafka_node_roles [broker]
    And bootstrap_servers lists only broker private IPs on port 9092

  Scenario: No secrets in inventory
    Given 3 brokers and 3 dedicated controllers
    When the inventory is rendered
    Then it contains no password, token or key values
    And each host carries only its connection and KRaft identity

  # Edge: with 10 brokers, name order (broker-10 before broker-2) differs from
  # node ID order; clients must see the node ID order.
  Scenario: Bootstrap servers follow node ID order
    Given 10 brokers without dedicated controllers
    When the plan is generated
    Then bootstrap_servers lists broker-1 to broker-10 in node ID order
