# ADR-0006: Remote state on Hetzner Object Storage

- **Status:** Proposed
- **Date:** 2026-10-02
- **Owner:** Platform engineering
- **Tickets:** pending

## Context
Project standard forbids local state for shared infrastructure. The bootstrap assumes AWS S3 + DynamoDB.

## Decision
`examples/complete` uses the `s3` backend against Hetzner Object Storage (`https://<location>.your-objectstorage.com`) with a partial backend config (`-backend-config=params/<location>/<env>/backend.hcl`) and `use_lockfile = true` (OpenTofu >= 1.10 / Terraform >= 1.10 native S3 locking). Credentials from `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`. The module declares no backend.

## Alternatives considered
| Option | Pros | Cons |
|--------|------|------|
| Hetzner Object Storage | Same provider, EU, cheap | Requires S3 compat flags (`skip_*`) |
| AWS S3 + DynamoDB | Mature | Second cloud account |
| Local state | None | Forbidden by standard |

## Consequences
Raises minimum runtime to OpenTofu >= 1.10 for the example. Makefile `REGION` becomes Hetzner `LOCATION`.
