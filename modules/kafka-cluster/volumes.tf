# Optional data volume per broker (ADR-0005). Created only when
# volume_size_gb > 0, and only for nodes with has_volume = true (brokers;
# dedicated controllers never get one).
#
# Ordering, no cycle: hcloud_volume (no server_id) -> hcloud_server (user_data
# references the volume's device path) -> hcloud_volume_attachment. The volume
# exists before its server, so the exact device path is known at server
# creation and cloud-init never has to guess which disk is Kafka's. The
# attachment is created after the server; cloud-init waits up to 120 s for it.
resource "hcloud_volume" "this" {
  for_each = { for k, n in local.nodes : k => n if n.has_volume }

  name     = "${var.name}-${each.key}-data"
  size     = var.volume_size_gb
  location = var.location
  # Formatted once by Hetzner at creation. cloud-init re-checks with blkid and
  # never formats a volume that already holds a filesystem.
  format = "xfs"
  # Destroying a protected volume fails: set delete_protection = false (or
  # disable it in the console) before `tofu destroy` or shrinking broker_count.
  delete_protection = true
  labels            = each.value.labels
}

resource "hcloud_volume_attachment" "this" {
  for_each = hcloud_volume.this

  volume_id = each.value.id
  server_id = hcloud_server.this[each.key].id
  # cloud-init mounts it (fstab, nofail); Hetzner automount would race it.
  automount = false
}

locals {
  # Mount point for Kafka data; the Ansible side expects log.dirs below it.
  kafka_data_dir = "/var/lib/kafka"
}
