# Server policy checked by terraform-compliance against the plan JSON of the
# root that calls modules/kafka-cluster (#8, ADR-0003, ADR-0004). Holds for any
# valid input, so it runs on whatever plan CI produces. Input-specific
# scenarios live in servers.feature (@tofu-test).
#
# placement_group_id is optional+computed, so the plan always carries the key
# (null when unset); the null check is what makes that scenario meaningful.
# Each scenario was mutation-checked by deleting the attribute from
# hcloud_server and confirming the scenario fails.
#
# Read-only against the plan: nothing is applied or persisted, no cleanup is
# needed. Scenarios are independent and parallel-safe.

Feature: Every Kafka server is isolated, spread and traceable

  Servers must sit behind the SSH-only firewall, on separate physical hosts,
  on the private network, and be identifiable as managed by this tooling.

  Scenario: Servers have the public firewall attached
    Given I have hcloud_server defined
    Then it must contain firewall_ids

  Scenario: Servers belong to a placement group
    Given I have hcloud_server defined
    Then it must contain placement_group_id
    And its value must not be null

  Scenario: Placement groups spread servers across hosts
    Given I have hcloud_placement_group defined
    Then it must contain type
    And its value must be spread

  Scenario: Servers join the private network
    Given I have hcloud_server defined
    Then it must contain network

  Scenario Outline: Server resources are labelled as managed by OpenTofu
    Given I have <resource> defined
    Then it must contain labels
    And it must contain managed-by
    And its value must be opentofu

    Examples:
      | resource               |
      | hcloud_server          |
      | hcloud_placement_group |
      | hcloud_ssh_key         |
