# ADR-0005: Optional Hetzner volume per broker

- **Status:** Accepted
- **Date:** 2026-10-02
- **Owner:** Platform engineering
- **Tickets:** #4, #9

## Context
Local NVMe is fast but tied to server lifecycle. Volumes survive server replacement but are network-attached.

## Decision
`volume_size_gb = 0` (default) uses local disk. `> 0` creates one `hcloud_volume` per broker (`format = "xfs"`, `automount = false`, `delete_protection = true`). `format = "xfs"` formats the volume at creation. cloud-init waits up to 120 s for `/dev/disk/by-id/scsi-0HC_Volume_<id>` to appear (the attachment is created after the server), then mounts it at `/var/lib/kafka` via `/etc/fstab` with `defaults,nofail`. A `blkid` guard runs `mkfs` only when no filesystem exists, protecting re-attached volumes. Servers set `lifecycle { ignore_changes = [user_data, image, ssh_keys] }`.

## Alternatives considered
| Option | Pros | Cons |
|--------|------|------|
| Optional volume | User chooses speed vs durability | Two code paths to test |
| Always volume | Data decoupled | Slower, extra cost |
| Local only | Simplest, fastest | Data lost on rebuild |

## Consequences
Volume deletion requires disabling protection first, matching the no-destroy policy.
