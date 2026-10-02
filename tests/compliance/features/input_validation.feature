# Specification of kafka-cluster input validation.
#
# Executable realisation: modules/kafka-cluster/tests/input_validation.tftest.hcl
# (`tofu test` with expect_failures). Each scenario asserts the plan is
# rejected by the named variable's validation, or by the cross-variable
# preconditions on output.nodes. terraform-compliance cannot assert a plan
# that fails to build, hence @tofu-test (exclude from terraform-compliance).
#
# Read-only: plans never apply, nothing is persisted, no cleanup is needed.
# Scenarios are independent and parallel-safe.

@tofu-test
Feature: Invalid cluster inputs are rejected

  Bad sizes, open SSH ranges and malformed networks must fail at plan time,
  before any Hetzner resource is created.

  Background:
    Given a valid 3-broker cluster configuration

  Scenario Outline: Invalid single inputs rejected
    Given <variable> is set to <value>
    When the plan is generated
    Then it fails with a validation error mentioning <variable>

    Examples:
      | variable          | value                |
      | broker_count      | 0                    |
      | broker_count      | 11                   |
      | controller_count  | 2                    |
      | ssh_allowed_cidrs | ["0.0.0.0/0"]        |
      | ssh_allowed_cidrs | ["::/0"]             |
      | ssh_allowed_cidrs | ["not-a-cidr"]       |
      | subnet_cidr       | "not-a-cidr"         |
      | subnet_cidr       | "10.0.1.0/28"        |
      | name              | "Kafka"              |
      | volume_size_gb    | 5                    |
      | volume_size_gb    | 10241                |
      | location          | "mars1"              |
      | ssh_public_keys   | { bad = "not-a-key" } |

  Scenario: Combined mode with more controllers than brokers
    Given 1 broker and 3 controllers without dedicated controllers
    When the plan is generated
    Then it fails with a validation error mentioning controller_count

  Scenario: Dedicated mode allows more controllers than brokers
    Given 1 broker and 3 dedicated controllers
    When the plan is generated
    Then the plan succeeds with 4 nodes

  Scenario: Empty SSH allowlist is accepted
    Given ssh_allowed_cidrs is empty
    When the plan is generated
    Then the plan succeeds

  Scenario: Subnet outside the network
    Given the network is 10.0.0.0/16 and the subnet is 10.1.1.0/24
    When the plan is generated
    Then it fails with a validation error mentioning subnet_cidr

  Scenario: Network zone does not contain the location
    Given location fsn1 with network zone us-east
    When the plan is generated
    Then it fails with a validation error mentioning network_zone

  Scenario: No SSH key supplied
    Given neither ssh_key_names nor ssh_public_keys is set
    When the plan is generated
    Then it fails with an error requiring at least one SSH key
