# Mirrors the acceptance criteria in GitHub issue #14 (ADR-0008). Realised by:
#   - molecule/secure (converge, idempotence, verify): TLS in generate mode,
#     SASL/SCRAM-SHA-512 and ACLs on 3 combined Docker nodes.
#   - tests/assert-security-prereqs.yml (localhost, no Docker) for the
#     missing-secret and missing-certificate paths.
#   - Ansible itself for "Missing vault password": an encrypted vault.yml
#     cannot be loaded without the password, so the play stops before its
#     first task.
# Molecule destroys its containers after every run; the smoke test deletes
# its own topic and temporary client config in `always` blocks.
Feature: Secure a Kafka KRaft cluster with TLS, SASL/SCRAM and ACLs

  Scenario: Secure cluster
    Given kafka_security_enabled, TLS, SASL and ACLs are enabled
    And the secrets come from Ansible Vault
    When make configure smoke-test runs
    Then every listener uses SASL_SSL
    And the smoke test produces and consumes a message over SASL_SSL

  Scenario: Unauthenticated client rejected
    Given a secure cluster
    And a client config that lists topics successfully with SASL credentials
    When the same client config connects without SASL credentials
    Then the connection is refused

  Scenario: ACLs deny by default
    Given a secure cluster with ACLs enabled
    And an application user with no ACL on the smoke-test topic
    When that user produces to the smoke-test topic
    Then the broker refuses it with an authorization error

  Scenario: Plaintext vault file
    Given group_vars/kafka/vault.yml exists but is not encrypted
    When make configure runs
    Then the play fails in pre_tasks and tells the operator to encrypt it

  Scenario: Missing vault password
    Given group_vars/kafka/vault.yml is encrypted
    And no vault password is supplied
    When make configure runs
    Then the play fails before changing any host

  Scenario: Missing SASL password
    Given SASL is enabled
    And kafka_sasl_inter_broker_password is undefined or CHANGE_ME
    When make configure runs
    Then the play fails in pre_tasks before installing Kafka

  Scenario: Missing TLS certificates
    Given TLS custom mode is enabled
    And make certs has not been run
    When make configure runs
    Then the play fails in pre_tasks and tells the operator to run make certs

  Scenario: Certificates survive a scale-out
    Given make certs has already created the project CA
    When a broker is added and make certs runs again
    Then only the new host gets a new certificate
    And it is signed by the existing CA
