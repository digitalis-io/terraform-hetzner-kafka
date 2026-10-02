# Specification of the kafka-cluster node map (ADR-0003).
#
# Executable realisation: modules/kafka-cluster/tests/node_map.tftest.hcl
# (`tofu test`, plan-only, mocked hcloud provider). terraform-compliance can
# only inspect resources in a plan; the node map is a local/output with no
# resources yet, so these scenarios are tagged @tofu-test and must be excluded
# from terraform-compliance runs until resource-level steps exist (#7-#9).
#
# Read-only: plans never apply, nothing is persisted, no cleanup is needed.
# Scenarios are independent and parallel-safe.

@tofu-test
Feature: Kafka node map

  Nodes are derived from broker and controller counts so that every server,
  volume and inventory entry gets a stable name, a unique KRaft node ID and
  the right KRaft roles.

  Background:
    Given a cluster named "kafka-test" in fsn1 with one SSH key

  Scenario: Combined three-node cluster
    Given 3 brokers without dedicated controllers
    When the plan is generated
    Then the nodes are broker-1, broker-2 and broker-3
    And every node runs the broker and controller roles
    And the node IDs are 1, 2 and 3

  Scenario: Combined five brokers, three controllers
    Given 5 brokers and 3 controllers without dedicated controllers
    When the plan is generated
    Then broker-1 to broker-3 run the broker and controller roles
    And broker-4 and broker-5 run only the broker role

  Scenario: Dedicated controllers
    Given 3 brokers and 3 dedicated controllers
    When the plan is generated
    Then controller-1 to controller-3 run only the controller role with IDs 1 to 3
    And broker-1 to broker-3 run only the broker role with IDs 101 to 103

  Scenario Outline: Controller count defaults by cluster size
    Given <brokers> brokers <mode> and no controller count
    When the plan is generated
    Then the cluster has <controllers> controllers

    Examples:
      | brokers | mode                            | controllers |
      | 1       | without dedicated controllers   | 1           |
      | 2       | without dedicated controllers   | 1           |
      | 4       | without dedicated controllers   | 3           |
      | 1       | with dedicated controllers      | 3           |

  Scenario: Private IPs avoid the subnet gateway
    Given 3 brokers and 3 dedicated controllers
    When the plan is generated
    Then controllers get private addresses from host 10 of the subnet
    And brokers get private addresses from host 20 of the subnet

  Scenario: Largest supported cluster fits a /27 subnet
    Given 10 brokers, 5 dedicated controllers and a /27 subnet
    When the plan is generated
    Then the plan has 15 nodes and broker-10 has node ID 110
