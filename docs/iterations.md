# Iteration plan — terraform-hetzner-kafka

Design: [architecture.md](architecture.md). Tracking issues: #1 (Iteration 0), #2 (Iteration 1), #3 (Iteration 2). Every ticket's definition of done includes `secrets-auditor`, `terraform-specialist` (or `ansible-specialist`), and `docs-quality-reviewer` via `/create-pr`.

## Iteration 0 — Bootstrap

**Objective:** retarget the AWS-flavoured scaffold to Hetzner and accept the architecture.
**Exit gate:** ADRs 0001–0006 accepted and merged; CI runs fmt, validate, tflint, trivy, terraform-compliance on an empty plan.

| # | Issue | Ticket | Agent | Blocked by |
|---|-------|--------|-------|-----------|
| 0.1 | #4 | Accept architecture and ADRs 0001–0006 | `tech-decision-maker`, `docs-quality-reviewer` | — |
| 0.2 | #5 | Retarget scaffold to Hetzner: Makefile `LOCATION`, `params/<location>/<env>/` layout, S3 backend on Hetzner Object Storage, CI terraform-compliance job | `devops`, `terraform-specialist` | 0.1 |

## Iteration 1 — MVP

**Objective:** one command sequence (`make apply galaxy configure smoke-test`) yields a healthy KRaft cluster on Hetzner.
**Exit gate:** quality gates applied via `/create-pr` on every ticket; E2E run evidence attached to 1.8 (#13).

| # | Issue | Ticket | Agent | Blocked by |
|---|-------|--------|-------|-----------|
| 1.1 | #6 | Module skeleton: versions, variables with validation, `local.nodes` map, outputs + compliance features for invalid inputs | `terraform-specialist` | 0.2 |
| 1.2 | #7 | Private network, subnet and firewall (SSH-only public ingress) | `terraform-specialist`, `security-reviewer` | 1.1 |
| 1.3 | #8 | Servers, SSH keys, spread placement groups, private IP attachment | `terraform-specialist` | 1.2 |
| 1.4 | #9 | Optional data volumes with cloud-init mount at `/var/lib/kafka` | `terraform-specialist` | 1.3 |
| 1.5 | #10 | Ansible inventory template and module outputs | `terraform-specialist` | 1.3 |
| 1.6 | #11 | Ansible playbook: `requirements.yml`, `site.yml`, `group_vars` example | `ansible-specialist`, `kafka-config-reviewer` | 1.5 |
| 1.7 | #12 | `examples/complete` root, end-to-end Makefile targets, branded README | `terraform-specialist`, `devops`, `docs-quality-reviewer` | 1.4, 1.5, 1.6 |
| 1.8 | #13 | E2E validation in a Hetzner test project (combined + dedicated, with/without volumes) | `qa-tester` | 1.7 |

## Iteration 2 — Security and operations

**Objective:** production-ready security and monitoring. Detailed after MVP feedback.

| # | Issue | Ticket | Agent | Blocked by |
|---|-------|--------|-------|-----------|
| 2.1 | #14 | Enable TLS + SASL/SCRAM + ACLs via Ansible Vault in example | `ansible-specialist`, `security-reviewer` | 1.8 |
| 2.2 | #15 | AxonOps agent wiring (SaaS key in Vault or self-hosted server) | `ansible-specialist` | 1.8 |

## Iteration 3 — Hardening (backlog, not filed)

Multi-location + rack awareness, KRaft quorum reconfiguration runbook, bastion/private-only mode, rolling upgrade playbook.
