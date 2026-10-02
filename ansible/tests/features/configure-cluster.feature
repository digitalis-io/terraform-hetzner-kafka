# Mirrors the acceptance criteria in GitHub issue #11. These scenarios
# describe site.yml / smoke-test.yml behaviour; they are realised by:
#   - molecule/default (converge, idempotence, verify) for the scenarios
#     that need a running Kafka service — requires Docker.
#   - a localhost-connection assertion play (tests/assert-inventory-contract.yml)
#     for "Missing kafka_node_id", which needs no container at all.
# All scenarios are read-only with respect to any real cluster: none of
# them provision or mutate infrastructure, so there is nothing to tear
# down here (bdd-guidelines Rule 4) beyond what each harness already does
# (Molecule destroys its containers after every run; the smoke test itself
# deletes its own test topic in an `always` block — see smoke-test.yml).
# Scenarios are independent and may run in any order (Rule 6).
Feature: Configure a Kafka KRaft cluster with site.yml

  Scenario: Configure combined cluster
    Given an inventory with 3 combined nodes
    When ansible-playbook site.yml runs
    Then kafka.service is active on all 3 hosts
    And the KRaft quorum has 3 voters

  Scenario: Idempotent re-run
    Given a configured cluster
    When ansible-playbook site.yml runs again
    Then the play reports changed=0

  Scenario: Single broker
    Given an inventory with 1 combined node
    Then the offsets and transaction-state-log replication factor is 1

  Scenario: Smoke test
    When ansible-playbook smoke-test.yml runs
    Then a message produced to a test topic is consumed back unchanged
    And the test topic no longer exists afterwards, even if the assertion failed

  # Edge case (bdd-guidelines Rule 3): a host missing a required inventory
  # key must fail fast, before any package is installed, not partway
  # through the kafka role. Realised by
  # tests/assert-inventory-contract.yml (no Docker needed).
  Scenario: Missing kafka_node_id
    Given a host without kafka_node_id
    Then the play fails in pre_tasks before installing Kafka

  # Edge case added per #9 (volumes): cloud-init's `nofail` mount means a
  # slow/failed Hetzner volume attachment is otherwise silent.
  Scenario: Kafka data volume not mounted
    Given a host with an /etc/fstab entry for /var/lib/kafka
    And that mountpoint is not currently mounted
    Then the play fails in pre_tasks before installing Kafka

  Scenario: Private network NIC down fails before installing Kafka
    Given a host whose kafka_node_ip is not configured on any interface
    When ansible-playbook site.yml runs
    Then the netplan file for the Hetzner private NIC is installed and applied
    And the play fails before installing Kafka if kafka_node_ip is still missing

  Scenario: Configure waits for the KRaft quorum
    Given Kafka has been installed and started on every host
    When ansible-playbook site.yml finishes
    Then every host reports an elected KRaft leader
    And the play fails if no leader is elected within 5 minutes
