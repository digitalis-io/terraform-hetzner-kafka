# ADR-0001: Hetzner Cloud with OpenTofu and the hcloud provider

- **Status:** Accepted
- **Date:** 2026-10-02
- **Owner:** Platform engineering
- **Tickets:** #4, #5, #6

## Context
Kafka clusters must run on low-cost European infrastructure. The bootstrap standard is OpenTofu (Terraform >= 1.5 compatible).

## Decision
Use Hetzner Cloud via the `hetznercloud/hcloud` provider, pinned `~> 1.<minor>`. OpenTofu >= 1.7 is the reference runtime. The API token is read from `HCLOUD_TOKEN` only.

## Alternatives considered
| Option | Pros | Cons |
|--------|------|------|
| Hetzner Cloud | API-driven, cheap, private networks, volumes, firewalls | Fewer managed services, 10-server spread group limit |
| Hetzner Robot (dedicated) | Raw performance, local NVMe | No Terraform lifecycle, slow provisioning |

## Consequences
Module is Hetzner-specific. No tflint ruleset exists for hcloud; correctness relies on validation blocks and compliance tests.
