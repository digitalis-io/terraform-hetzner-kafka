# Executable realisation of tests/compliance/features/volumes.feature (#9,
# ADR-0005), except "Existing filesystem preserved", which exercises the
# mount script itself (tests/cloud-init/test_mount_data_volume.sh).
# Plan-only against a mocked hcloud provider: no credentials, no real
# resources, nothing to clean up. Runs are independent and order-free.

mock_provider "hcloud" {
  # Numeric ids: the generated mock id is random text, which numeric
  # arguments (network_id, firewall_ids, placement_group_id, volume_id,
  # server_id) reject. Every mocked volume gets the same id/device; the tests
  # only check that the device path reaches cloud-init.
  mock_resource "hcloud_network" {
    defaults = { id = "1001" }
  }
  mock_resource "hcloud_firewall" {
    defaults = { id = "2001" }
  }
  mock_resource "hcloud_placement_group" {
    defaults = { id = "3001" }
  }
  mock_resource "hcloud_volume" {
    defaults = {
      id           = "4001"
      linux_device = "/dev/disk/by-id/scsi-0HC_Volume_4001"
    }
  }
  mock_resource "hcloud_server" {
    defaults = { id = "5001" }
  }
}

variables {
  name               = "kafka-test"
  location           = "fsn1"
  network_zone       = "eu-central"
  broker_server_type = "cpx32"
  broker_count       = 3
  ssh_key_names      = ["operator"]
  ssh_allowed_cidrs  = ["203.0.113.10/32"]
}

run "no_volumes_by_default" {
  command = plan

  assert {
    condition     = length(hcloud_volume.this) == 0 && length(hcloud_volume_attachment.this) == 0
    error_message = "volume_size_gb = 0 must plan no volumes and no attachments."
  }

  assert {
    condition     = alltrue([for s in hcloud_server.this : s.user_data == null])
    error_message = "Servers must have no user_data when no volume is attached."
  }

  assert {
    condition     = alltrue([for s in output.servers : s.volume_id == null])
    error_message = "servers output volume_id must be null without volumes."
  }
}

run "volumes_for_brokers" {
  command = plan

  variables {
    volume_size_gb = 100
  }

  assert {
    condition     = toset(keys(hcloud_volume.this)) == toset(["broker-1", "broker-2", "broker-3"])
    error_message = "Expected one volume per broker: broker-1..3."
  }

  assert {
    condition = alltrue([
      for k, v in hcloud_volume.this :
      v.name == "kafka-test-${k}-data" && v.size == 100 && v.location == "fsn1" &&
      v.delete_protection == true && v.format == "xfs"
    ])
    error_message = "Volumes must be <name>-<key>-data, 100 GB, in var.location, xfs, delete-protected."
  }

  assert {
    condition     = alltrue([for v in hcloud_volume.this : v.labels == tomap({ cluster = "kafka-test", managed-by = "opentofu", role = "broker" })])
    error_message = "Volume labels must come from the node map."
  }

  assert {
    condition = (
      toset(keys(hcloud_volume_attachment.this)) == toset(keys(hcloud_volume.this)) &&
      alltrue([for a in hcloud_volume_attachment.this : a.automount == false && a.volume_id == 4001 && a.server_id == 5001])
    )
    error_message = "Each volume must be attached to its server with automount = false."
  }

  assert {
    condition = alltrue([
      for s in hcloud_server.this :
      startswith(s.user_data, "#cloud-config\n") &&
      strcontains(s.user_data, "\"/dev/disk/by-id/scsi-0HC_Volume_4001\", \"/var/lib/kafka\"") &&
      strcontains(s.user_data, "defaults,nofail") &&
      strcontains(s.user_data, "blkid -o value -s TYPE") &&
      strcontains(s.user_data, "mkfs.xfs") &&
      strcontains(s.user_data, "wait_seconds=$${WAIT_SECONDS:-120}")
    ])
    error_message = "Broker cloud-init must wait 120 s for the volume device, guard mkfs with blkid and mount /var/lib/kafka with defaults,nofail."
  }

  assert {
    condition     = can(yamldecode(hcloud_server.this["broker-1"].user_data))
    error_message = "Rendered cloud-init must be valid YAML."
  }

  assert {
    condition     = yamldecode(hcloud_server.this["broker-1"].user_data).write_files[0].content == file("${path.module}/templates/mount-data-volume.sh")
    error_message = "cloud-init must ship the mount script byte-for-byte (the script tested by tests/cloud-init)."
  }

  assert {
    condition     = alltrue([for s in output.servers : s.volume_id == "4001"])
    error_message = "servers output must expose each broker's volume_id."
  }
}

run "dedicated_controllers_get_no_volume" {
  command = plan

  variables {
    dedicated_controllers = true
    volume_size_gb        = 100
  }

  assert {
    condition     = toset(keys(hcloud_volume.this)) == toset(["broker-1", "broker-2", "broker-3"])
    error_message = "Only brokers may get volumes in dedicated mode."
  }

  assert {
    condition     = alltrue([for k in keys(hcloud_volume_attachment.this) : !startswith(k, "controller-")])
    error_message = "No volume may be attached to a controller node."
  }

  assert {
    condition     = alltrue([for k, s in hcloud_server.this : startswith(k, "controller-") ? s.user_data == null : s.user_data != null])
    error_message = "Controllers must have no user_data; brokers must have the volume cloud-init."
  }

  assert {
    condition     = alltrue([for k, s in output.servers : startswith(k, "controller-") ? s.volume_id == null : true])
    error_message = "Controllers must report volume_id = null."
  }
}

run "volume_size_out_of_range_rejected" {
  command = plan

  variables {
    volume_size_gb = 5
  }

  expect_failures = [var.volume_size_gb]
}
