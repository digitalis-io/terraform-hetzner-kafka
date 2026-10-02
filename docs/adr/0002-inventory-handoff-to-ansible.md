# ADR-0002: Terraform renders inventory; Ansible runs separately

- **Status:** Accepted
- **Date:** 2026-10-02
- **Owner:** Platform engineering
- **Tickets:** #4, #10, #11

## Context
Infrastructure is provisioned by OpenTofu; Kafka is configured by the `axonops.axonops` collection. The handoff must be repeatable and keep secrets out of Terraform state.

## Decision
The module outputs a YAML Ansible inventory (`templatefile`). The example root writes it to `inventory.yml` with `local_file`. The operator runs `ansible-playbook` as a separate step. The inventory carries no secrets.

## Alternatives considered
| Option | Pros | Cons |
|--------|------|------|
| Inventory + separate run | Clean separation, re-runnable, secrets stay in Ansible Vault | Two commands |
| `terraform_data` + `local-exec` | One command | Couples state to config runs, needs Ansible on TF runner, failures taint resources |
| cloud-init `ansible-pull` | No control node | Hard to coordinate KRaft quorum, secrets on hosts |

## Consequences
Inventory schema is a module contract (`kafka_node_id`, `kafka_node_roles`, `kafka_node_ip`, `ansible_host`). Changes to it are breaking.
