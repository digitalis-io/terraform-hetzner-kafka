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
cp group_vars/kafka.yml.example group_vars/kafka.yml   # edit as needed
ansible-playbook -i ../inventory.yml site.yml           # inventory.yml comes from `tofu apply` / `make inventory`
ansible-playbook -i ../inventory.yml smoke-test.yml      # produce/consume a test message
```

(`ansible.cfg`'s default `inventory` path is already `../inventory.yml`, so
`-i` can be omitted once that file exists.)

## Contents

| File | Purpose |
|------|---------|
| `requirements.yml` | Pinned `axonops.axonops` collection (and its direct dependencies) |
| `ansible.cfg` | Inventory path, SSH `accept-new` host-key policy, pipelining |
| `site.yml` | `chrony`, `preflight`, `kafka` roles; validates the inventory contract and the Kafka data-volume mount before installing anything |
| `smoke-test.yml` | Produce/consume one message against the private network; cleans up its test topic even on failure |
| `group_vars/kafka.yml.example` | Starting point for cluster-specific overrides — copy to `kafka.yml` |
| `tests/inventory.yml` | Fake 3-node inventory for `--syntax-check` / `ansible-lint` |
| `tests/assert-inventory-contract.yml` | Localhost-only checks for the two pre_tasks failure paths (missing inventory keys; unmounted data volume) |
| `tests/features/*.feature` | Gherkin specs mirroring issue #11's acceptance criteria |
| `molecule/default/` | Docker-based 3-node combined-cluster scenario (converge + idempotence + smoke-test). **Not run in this change** — authored and lint/syntax-checked only; wiring into CI is a follow-up |

## Scope (Iteration 1, #11)

TLS, SASL, ACLs and the AxonOps agent are out of scope here — see Iteration 2
(#15). `kafka_axonops_agent_enabled` defaults to `false` in `site.yml`.

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
