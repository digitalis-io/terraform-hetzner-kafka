# ADR-0004: Kafka on private network only; public firewall allows SSH only

- **Status:** Proposed
- **Date:** 2026-10-02
- **Owner:** Platform engineering
- **Tickets:** pending

## Context
The kafka role binds listeners on all interfaces (`PLAINTEXT://:9092`, `CONTROLLER://:9093`). MVP Kafka is PLAINTEXT. Hetzner firewalls filter public interfaces only.

## Decision
Create `hcloud_network` + subnet; every node gets a deterministic private IP. Kafka advertises private IPs (`kafka_node_ip`). One `hcloud_firewall` on all nodes allows inbound 22/tcp from `ssh_allowed_cidrs` only (no default `0.0.0.0/0`). Servers keep a public IPv4 for SSH and egress.

## Alternatives considered
| Option | Pros | Cons |
|--------|------|------|
| Private net + firewall | Simple, Ansible direct over SSH | Public IPs exist (SSH only) |
| Private only + bastion | Smallest attack surface | Needs NAT for egress, ProxyJump, more resources |
| Public Kafka | External clients | Requires TLS/SASL first |

## Consequences
Clients must be inside the Hetzner network. Compliance test asserts no public rule for 9092/9093.
