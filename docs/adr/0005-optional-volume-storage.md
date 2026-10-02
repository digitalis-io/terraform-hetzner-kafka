# ADR-0005: Optional Hetzner volume per broker

- **Status:** Proposed
- **Date:** 2026-10-02
- **Owner:** Platform engineering
- **Tickets:** pending

## Context
Local NVMe is fast but tied to server lifecycle. Volumes survive server replacement but are network-attached.

## Decision
`volume_size_gb = 0` (default) uses local disk. `> 0` creates one `hcloud_volume` per broker (`format = "xfs"`, `automount = false`, `delete_protection = true`). cloud-init mounts `/dev/disk/by-id/scsi-0HC_Volume_<id>` at `/var/lib/kafka` via `/etc/fstab`, formatting only when `blkid` finds no filesystem. Servers set `lifecycle { ignore_changes = [user_data, image, ssh_keys] }`.

## Alternatives considered
| Option | Pros | Cons |
|--------|------|------|
| Optional volume | User chooses speed vs durability | Two code paths to test |
| Always volume | Data decoupled | Slower, extra cost |
| Local only | Simplest, fastest | Data lost on rebuild |

## Consequences
Volume deletion requires disabling protection first, matching the no-destroy policy.
