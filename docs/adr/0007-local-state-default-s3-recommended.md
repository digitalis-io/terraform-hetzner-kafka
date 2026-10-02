# ADR-0007: Local state by default, S3 remote state recommended

- **Status:** Accepted
- **Date:** 2026-10-02
- **Owner:** Platform engineering
- **Tickets:** #13, #26
- **Supersedes:** ADR-0006

## Context
ADR-0006 required an S3 backend on Hetzner Object Storage for `examples/complete`. In practice this blocks a first run: users need an Object Storage bucket and credentials before they can see a cluster, and the first end-to-end test (#13) was run with local state. This repository is also an entry point for teams evaluating Kafka on Hetzner, where time to a working cluster matters.

## Decision
`examples/complete/backend.tf` ships with the S3 block commented out, so state is local by default. Remote state is recommended and documented: uncomment `backend "s3" {}`, copy `params/<location>/<env>/backend.hcl.example` to `backend.hcl` and export Object Storage credentials. `make prep` detects an active S3 block and passes `backend.hcl` only then, failing clearly if it is missing. The ADR-0006 S3 settings (`use_lockfile`, `use_path_style`, `skip_*`) and the `LOCK=false` fallback remain the recommended remote configuration.

## Alternatives considered
| Option | Pros | Cons |
|--------|------|------|
| S3 required (ADR-0006) | Shared state and locking from day one | Extra setup before first cluster; blocks evaluation |
| Local by default, S3 optional | Fast first run; same remote setup available | Users can lose or diverge local state |
| Backend chosen by a Make variable via generated override file | No file edit | Generated files confuse users and tooling |

## Consequences
Local state is a risk for shared or long-lived clusters; the README states this and shows the migration (`tofu init -migrate-state`). The project standard "never local state in shared modules" still holds: the module declares no backend.
