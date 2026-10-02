#!/bin/sh
# Mount a Hetzner data volume for Kafka (ADR-0005).
#
# Usage: mount-data-volume.sh DEVICE MOUNT_POINT
#   DEVICE       stable device path, /dev/disk/by-id/scsi-0HC_Volume_<id>
#   MOUNT_POINT  directory to mount the volume on, e.g. /var/lib/kafka
#
# Environment (overridable for tests only):
#   FSTAB         fstab file to update (default /etc/fstab)
#   WAIT_SECONDS  seconds to wait for DEVICE to appear (default 120)
#
# Shipped to every node with a volume by cloud-init (cloud-init.yaml.tftpl).
# The attachment is created after the server, so the device may appear late.
# Idempotent: safe to re-run; it never formats a volume that already holds a
# filesystem, never duplicates the fstab entry and never re-mounts.
set -eu

log() {
  printf 'mount-data-volume: %s\n' "$*" >&2
}

if [ "$#" -ne 2 ]; then
  log "usage: $0 DEVICE MOUNT_POINT"
  exit 64
fi

device=$1
mount_point=$2
fstab=${FSTAB:-/etc/fstab}
wait_seconds=${WAIT_SECONDS:-120}

waited=0
while [ ! -e "$device" ]; do
  if [ "$waited" -ge "$wait_seconds" ]; then
    log "error: $device did not appear within ${wait_seconds}s"
    exit 1
  fi
  sleep 1
  waited=$((waited + 1))
done

# blkid exit codes: 0 = filesystem found, 2 = no filesystem signature.
# Anything else (I/O error, ambivalent probe) aborts rather than risk running
# mkfs over existing data.
if fstype=$(blkid -o value -s TYPE "$device"); then
  rc=0
else
  rc=$?
fi

case "$rc" in
  0)
    log "$device already has a filesystem ($fstype); not formatting"
    ;;
  2)
    log "$device has no filesystem; creating xfs"
    mkfs.xfs "$device"
    fstype=xfs
    ;;
  *)
    log "error: blkid failed on $device (exit $rc); refusing to format"
    exit 1
    ;;
esac

mkdir -p "$mount_point"

if awk -v dev="$device" '$1 == dev { found = 1 } END { exit !found }' "$fstab"; then
  log "$device already in $fstab"
else
  # by-id path is tied to the Hetzner volume, stable across reboots and
  # re-attachment; UUID is not needed. nofail keeps boot going if the volume
  # is detached; the short device timeout caps systemd's default 90 s wait.
  printf '%s %s %s defaults,nofail,x-systemd.device-timeout=30s 0 2\n' "$device" "$mount_point" "$fstype" >>"$fstab"
  log "added $device to $fstab"
fi

if mountpoint -q "$mount_point"; then
  log "$mount_point already mounted"
else
  mount "$mount_point"
  log "mounted $device on $mount_point"
fi
