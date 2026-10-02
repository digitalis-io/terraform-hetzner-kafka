<p align="center">
  <a href="https://digitalis.io">
    <img src="https://digitalis-marketplace-assets.s3.us-east-1.amazonaws.com/DigitalisDigital_DigitalisFullLogoGradient+-+medium.png" alt="Digitalis.IO" width="300">
  </a>
</p>

<p align="center">
  <em>Built and maintained by <a href="https://digitalis.io">Digitalis.IO</a>: Apache Kafka experts, 24x7 managed services and consultancy</em>
</p>

# ansible/

Configures the Kafka KRaft cluster provisioned by `modules/kafka-cluster`
(OpenTofu) using the [`axonops.axonops`](https://github.com/axonops/axonops-ansible-collection)
collection. See [`docs/architecture.md`](../docs/architecture.md) and
[ADR-0002](../docs/adr/0002-inventory-handoff-to-ansible.md) for the
Terraform → Ansible handoff.

## Quick start

```bash
cd ansible
ansible-galaxy collection install -r requirements.yml
cp group_vars/kafka/vars.yml.example group_vars/kafka/vars.yml     # edit as needed
cp group_vars/kafka/vault.yml.example group_vars/kafka/vault.yml   # set real passwords
ansible-vault encrypt group_vars/kafka/vault.yml
ansible-playbook -i ../inventory.yml certs.yml                       # TLS CA + per-host certs in tls/
ansible-playbook -i ../inventory.yml site.yml --ask-vault-pass       # inventory.yml comes from `tofu apply` / `make inventory`
ansible-playbook -i ../inventory.yml smoke-test.yml --ask-vault-pass # produce/consume over SASL_SSL
```

From the repository root the same steps are `make certs configure smoke-test`.

(`ansible.cfg`'s default `inventory` path is already `../inventory.yml`, so
`-i` can be omitted once that file exists.)

## Contents

| File | Purpose |
|------|---------|
| `requirements.yml` | Pinned `axonops.axonops` collection (and its direct dependencies) |
| `ansible.cfg` | Inventory path, SSH `accept-new` host-key policy, pipelining |
| `site.yml` | `chrony`, `preflight`, `kafka` roles; validates the inventory contract and the Kafka data-volume mount before installing anything |
| `smoke-test.yml` | Produce/consume one message against the private network; cleans up its test topic even on failure. With security on it authenticates over SASL_SSL and checks that a client without credentials is refused |
| `certs.yml` | Creates the project CA and one certificate per inventory host in `tls/` (gitignored). Idempotent: after a scale-out it signs only the new hosts ([ADR-0008](../docs/adr/0008-kafka-tls-certificate-source.md)) |
| `group_vars/kafka/vars.yml.example` | Cluster settings, including TLS, SASL and ACLs. Copy to `vars.yml` |
| `group_vars/kafka/vault.yml.example` | Secrets template. Copy to `vault.yml` (gitignored) and encrypt with `ansible-vault` |
| `tests/inventory.yml` | Fake 3-node inventory for `--syntax-check` / `ansible-lint` |
| `tests/assert-inventory-contract.yml` | Localhost-only checks for the pre_tasks failure paths (missing inventory keys; unmounted data volume; private NIC down) |
| `tests/assert-security-prereqs.yml` | Localhost-only checks for missing or placeholder SASL passwords and missing TLS files |
| `tests/features/*.feature` | Gherkin specs mirroring the acceptance criteria of #11 and #14 |
| `molecule/default/` | Docker-based 3-node PLAINTEXT cluster (converge + idempotence + smoke test), run in CI |
| `molecule/secure/` | Same cluster with TLS (`generate` mode), SASL/SCRAM-SHA-512 and ACLs, run in CI |

## Security (#14)

The example `vars.yml` turns on TLS, SASL/SCRAM-SHA-512 and ACLs. Every
listener (9092 clients and inter-broker, 9093 controllers) becomes
`SASL_SSL`. Design and trade-offs: [ADR-0008](../docs/adr/0008-kafka-tls-certificate-source.md).

| Setting | Example value | Why |
|---------|---------------|-----|
| `kafka_tls_mode` | `custom` | Certificates from `certs.yml` (project CA in `tls/`). `generate` keeps its CA in `/tmp` and is for disposable test clusters only |
| `kafka_tls_client_auth` | `none` | Clients prove identity with SASL; TLS encrypts. Use `required` for mTLS |
| `kafka_sasl_inter_broker_password` | `"{{ vault_kafka_sasl_inter_broker_password }}"` | Broker and controller identity; also the cluster super user |
| `kafka_sasl_users` | `"{{ vault_kafka_sasl_users }}"` | Application users, for example `app1` |
| `kafka_acl_allow_everyone_if_no_acl` | `false` | Deny by default; grant access with `kafka_acls` |

Before installing anything, `site.yml` stops if a SASL password is missing,
shorter than 16 characters or still `CHANGE_ME`. It also stops if the TLS
files from `certs.yml` are missing. Without the Vault password, Ansible
cannot load `vault.yml` and stops before the first task.

Things to know:

- **Fresh clusters only.** SCRAM credentials are written when storage is
  formatted. Moving a running PLAINTEXT cluster to SASL_SSL is a manual
  migration.
- **SCRAM users and ACLs need a running broker.** The role applies them only
  with `kafka_start_on_install: true`.
- **Protect `tls/ca.key`.** It can sign certificates that every broker
  trusts. Keep it offline or encrypt it with `ansible-vault` after use.
- **Rotate a host certificate:** delete `tls/<host>.crt`, then run
  `make certs configure`.

Client example (inside the Hetzner private network):

```properties
bootstrap.servers=10.0.1.10:9092,10.0.1.11:9092,10.0.1.12:9092
security.protocol=SASL_SSL
sasl.mechanism=SCRAM-SHA-512
sasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username="app1" password="<from vault.yml>";
ssl.truststore.type=PEM
ssl.truststore.location=/path/to/ca.crt
```

The AxonOps agent is still off (`kafka_axonops_agent_enabled: false`); see #15.

Replication factors (`kafka_replication_factor`,
`kafka_offsets_topic_replication_factor`,
`kafka_transaction_state_log_replication_factor`,
`kafka_transaction_state_log_min_isr`) are derived in `site.yml` from
`groups['kafka_brokers'] | length`, not from the play's full host count —
dedicated controllers (ADR-0003) hold no partition data, so sizing against
`groups['kafka']` would overstate how many replicas can actually exist.

## Contact

This project is maintained by [Digitalis.io](https://digitalis.io), providing
managed services and consultancy for Apache Kafka. For support, visit
[digitalis.io/contact](https://digitalis.io/contact).
