# ADR-0003: Single module with internal node map; combined or dedicated controllers

- **Status:** Accepted
- **Date:** 2026-10-02
- **Owner:** Platform engineering
- **Tickets:** #4, #6, #8

## Context
Users choose broker count, controller layout and server types. Node IDs must be unique and stable. The kafka role uses static `controller.quorum.voters`.

## Decision
One module `modules/kafka-cluster` builds `local.nodes`, a map keyed `broker-<n>` / `controller-<n>`. All servers, volumes and inventory entries derive from it via `for_each`.

- `dedicated_controllers = false` (default): the first `controller_count` brokers are `[broker, controller]`, the rest `[broker]`. IDs 1..N.
- `dedicated_controllers = true`: `controller_count` controller-only nodes (IDs 1..N), broker IDs 101..(100+broker_count).
- `controller_count` ∈ {1, 3, 5}, must be <= `broker_count` in combined mode.
- In combined mode `broker_count` <= 10 (one spread group). In dedicated mode `broker_count` <= 10 and `controller_count` <= 5.

## Alternatives considered
| Option | Pros | Cons |
|--------|------|------|
| Single module, node map | One place for IDs, stable keys | Larger module |
| Node-pool submodule ×2 | Reusable pools | Cross-module ID allocation, more wiring |
| Flat root | Fastest | Not reusable, breaks module standard |

## Consequences
Scaling brokers adds/removes tail nodes only. Changing controller membership after bootstrap is unsupported until a quorum-reconfiguration runbook exists.
