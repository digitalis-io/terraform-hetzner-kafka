# Specification of the optional per-broker data volumes (#9, ADR-0005).
#
# Executable realisation:
#   - modules/kafka-cluster/tests/volumes.tftest.hcl (`tofu test`, plan-only,
#     mocked hcloud provider) for every scenario except the one tagged
#     @cloud-init-test. These vary module inputs or expect the plan to fail,
#     which terraform-compliance cannot do against a single plan JSON, hence
#     @tofu-test on the feature.
#   - tests/cloud-init/test_mount_data_volume.sh (`make cloud-init-test`) for
#     "Existing filesystem preserved": it runs the exact script cloud-init
#     ships against stubbed blkid/mkfs/mount, since a real boot needs a server.
# The input-independent volume policy lives in volumes_policy.feature.
#
# Read-only: plans never apply; the script test works in temp dirs removed on
# exit. Nothing persists, no cleanup is needed. Scenarios are independent and
# parallel-safe.

@tofu-test
Feature: Optional protected data volumes for brokers

  Operators can keep Kafka data on a Hetzner volume that survives server
  replacement. Each broker gets its own protected volume, mounted for Kafka at
  first boot without ever wiping existing data.

  Background:
    Given a cluster named "kafka-test" in fsn1 with one SSH key

  Scenario: No volumes by default
    Given 3 brokers and no data volume size
    When the plan is generated
    Then no data volume is created
    And no server has boot-time configuration

  Scenario: Volumes for brokers
    Given 3 brokers with 100 GB data volumes
    When the plan is generated
    Then 3 delete-protected 100 GB volumes are created, one per broker
    And each volume is attached to its broker without automatic mounting
    And each broker mounts its volume for Kafka data at first boot

  Scenario: Dedicated controllers get no volume
    Given 3 brokers and 3 dedicated controllers with 100 GB data volumes
    When the plan is generated
    Then only brokers receive a volume
    And controllers have no boot-time configuration

  @cloud-init-test
  Scenario: Existing filesystem preserved
    Given a volume that already contains an xfs filesystem
    When the server boots with the cloud-init template
    Then the volume is mounted without being reformatted

  @cloud-init-test
  Scenario: Unreadable volume is left untouched
    Given a volume whose filesystem cannot be identified
    When the server boots with the cloud-init template
    Then the volume is neither formatted nor mounted

  Scenario: Volume size out of range
    Given a data volume size of 5 GB
    When the plan is generated
    Then it fails with a validation error on the volume size
