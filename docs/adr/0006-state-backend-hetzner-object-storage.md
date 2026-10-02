# ADR-0006: Remote state on Hetzner Object Storage

- **Status:** Accepted
- **Date:** 2026-10-02
- **Owner:** Platform engineering
- **Tickets:** #4, #5

## Context
Project standard forbids local state for shared infrastructure. The bootstrap assumes AWS S3 + DynamoDB.

## Decision
`examples/complete` uses the `s3` backend against Hetzner Object Storage (`https://<location>.your-objectstorage.com`) with a partial backend config (`-backend-config=params/<location>/<env>/backend.hcl`) and `use_lockfile = true` (OpenTofu >= 1.10; Terraform >= 1.11 GA). Hetzner support for `If-None-Match` conditional writes is unverified: ticket #5 must prove it with two concurrent `tofu plan -lock=true` runs. If it fails, use `-lock=false` plus a CI concurrency group. Credentials from `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`. The module declares no backend.

## Alternatives considered
| Option | Pros | Cons |
|--------|------|------|
| Hetzner Object Storage | Same provider, EU, cheap | Requires `skip_credentials_validation`, `skip_region_validation`, `skip_requesting_account_id`, `skip_s3_checksum`, `use_path_style`, `endpoints.s3` |
| AWS S3 + DynamoDB | Mature | Second cloud account |
| Local state | None | Forbidden by standard |

## Consequences
Raises minimum runtime to OpenTofu >= 1.10 for the example. Makefile `REGION` becomes Hetzner `LOCATION`.
