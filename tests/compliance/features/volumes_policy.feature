# Data volume policy checked by terraform-compliance against the plan JSON of a
# root that calls modules/kafka-cluster with volume_size_gb > 0 (#9,
# ADR-0005). Holds for any valid input; with volume_size_gb = 0 there are no
# volumes and every scenario is skipped. Input-specific scenarios live in
# volumes.feature (@tofu-test).
#
# Each scenario was mutation-checked by flipping or deleting the attribute in
# volumes.tf and confirming the scenario fails.
#
# Read-only against the plan: nothing is applied or persisted, no cleanup is
# needed. Scenarios are independent and parallel-safe.

Feature: Kafka data volumes cannot be lost by accident

  A broker's data volume must survive an accidental destroy, carry a
  filesystem from creation and be mounted only by cloud-init.

  Scenario: Volumes are delete-protected
    Given I have hcloud_volume defined
    Then it must contain delete_protection
    And its value must be true

  Scenario: Volumes are formatted xfs at creation
    Given I have hcloud_volume defined
    Then it must contain format
    And its value must be xfs

  Scenario: Hetzner automount is disabled on attachments
    Given I have hcloud_volume_attachment defined
    Then it must contain automount
    And its value must be false

  Scenario: Volumes are labelled as managed by OpenTofu
    Given I have hcloud_volume defined
    Then it must contain labels
    And it must contain managed-by
    And its value must be opentofu
