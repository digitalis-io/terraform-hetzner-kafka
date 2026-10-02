#!/bin/sh
# Stubs and check() conditions are single-quoted on purpose: they expand when
# the stub runs or when check() evals them, not here.
# shellcheck disable=SC2016
# Behaviour tests for modules/kafka-cluster/templates/mount-data-volume.sh,
# the script cloud-init runs on nodes with a data volume (#9, ADR-0005).
# Realises the "Existing filesystem preserved" scenario of
# tests/compliance/features/volumes.feature plus its edge cases.
#
# blkid, mkfs.xfs, mountpoint, mount and sleep are replaced by PATH stubs that
# record their calls; the "device" is a plain file and fstab a temp file. No
# root, no loop device, nothing outside a per-test temp dir is touched; every
# temp dir is removed on exit (trap), even when a case fails. Cases are
# independent and order-free.
#
# Usage: tests/cloud-init/test_mount_data_volume.sh   (or: make cloud-init-test)
set -eu

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
script="$repo_root/modules/kafka-cluster/templates/mount-data-volume.sh"
work_root=$(mktemp -d)
trap 'rm -rf "$work_root"' EXIT INT TERM

passed=0
failed=0

# new_case NAME: fresh temp dir with stubs, empty fstab and a "device" file.
# Stub behaviour is driven by env vars read at call time:
#   BLKID_RC / BLKID_TYPE  blkid exit status and printed type
#   MOUNTED                1 = mountpoint -q reports already mounted
new_case() {
  dir="$work_root/$1"
  mkdir -p "$dir/bin"
  calls="$dir/calls"
  fstab="$dir/fstab"
  device="$dir/scsi-0HC_Volume_4001"
  # Under the case dir: the script creates it with mkdir -p.
  mount_point="$dir/var/lib/kafka"
  : >"$calls"
  printf '# fstab\n' >"$fstab"
  : >"$device"

  for cmd in mkfs.xfs mount sleep; do
    printf '#!/bin/sh\necho "%s $*" >>"%s"\n' "$cmd" "$calls" >"$dir/bin/$cmd"
  done
  printf '#!/bin/sh\necho "blkid $*" >>"%s"\n[ -n "${BLKID_TYPE:-}" ] && echo "$BLKID_TYPE"\nexit "${BLKID_RC:-0}"\n' \
    "$calls" >"$dir/bin/blkid"
  printf '#!/bin/sh\necho "mountpoint $*" >>"%s"\n[ "${MOUNTED:-0}" = 1 ]\n' \
    "$calls" >"$dir/bin/mountpoint"
  chmod +x "$dir/bin/"*
}

# run_script: run the real script against the current case; sets $rc.
run_script() {
  if PATH="$dir/bin:$PATH" FSTAB="$fstab" WAIT_SECONDS="${WAIT:-120}" \
    sh "$script" "$device" "$mount_point" >"$dir/out" 2>&1; then
    rc=0
  else
    rc=$?
  fi
}

# check DESCRIPTION CONDITION: CONDITION is eval'd against the case's
# $rc, $calls, $fstab, $device and $mount_point.
check() {
  if eval "$2"; then
    passed=$((passed + 1))
    printf 'ok   %s\n' "$1"
  else
    failed=$((failed + 1))
    printf 'FAIL %s\n' "$1"
    sed 's/^/     | /' "$dir/out" "$calls"
  fi
}

fstab_lines() {
  grep -c "^$device " "$fstab" || true
}

# Scenario: Existing filesystem preserved
new_case existing_xfs
BLKID_RC=0 BLKID_TYPE=xfs run_script
check "existing xfs: script succeeds" '[ "$rc" -eq 0 ]'
check "existing xfs: mkfs never runs" '! grep -q "^mkfs.xfs" "$calls"'
check "existing xfs: fstab entry with defaults,nofail" \
  'grep -qx "$device $mount_point xfs defaults,nofail,x-systemd.device-timeout=30s 0 2" "$fstab"'
check "existing xfs: mount directory created" '[ -d "$mount_point" ]'
check "existing xfs: volume is mounted" 'grep -qx "mount $mount_point" "$calls"'

# Edge: a re-attached volume with another filesystem keeps it too.
new_case existing_ext4
BLKID_RC=0 BLKID_TYPE=ext4 run_script
check "existing ext4: no mkfs, fstab uses ext4" \
  '[ "$rc" -eq 0 ] && ! grep -q "^mkfs.xfs" "$calls" && grep -qx "$device $mount_point ext4 defaults,nofail,x-systemd.device-timeout=30s 0 2" "$fstab"'

# Empty volume (blkid exit 2) is formatted xfs exactly once.
new_case empty_volume
BLKID_RC=2 run_script
check "empty volume: mkfs.xfs runs once on the device" \
  '[ "$rc" -eq 0 ] && [ "$(grep -c "^mkfs.xfs $device\$" "$calls")" -eq 1 ]'
check "empty volume: fstab entry is xfs" \
  'grep -qx "$device $mount_point xfs defaults,nofail,x-systemd.device-timeout=30s 0 2" "$fstab"'

# Re-run (reboot, cloud-init re-run): no duplicate fstab line, no re-mount.
new_case rerun
BLKID_RC=0 BLKID_TYPE=xfs run_script
: >"$calls"
BLKID_RC=0 BLKID_TYPE=xfs MOUNTED=1 run_script
check "re-run: succeeds with one fstab entry" '[ "$rc" -eq 0 ] && [ "$(fstab_lines)" -eq 1 ]'
check "re-run: already mounted volume is not re-mounted" '! grep -q "^mount " "$calls"'

# blkid failure other than "no filesystem" must abort, never format.
new_case blkid_error
BLKID_RC=4 run_script
check "blkid error: script fails" '[ "$rc" -ne 0 ]'
check "blkid error: no mkfs, no fstab entry, no mount" \
  '! grep -q "^mkfs.xfs" "$calls" && [ "$(fstab_lines)" -eq 0 ] && ! grep -q "^mount " "$calls"'

# Device never attached: give up after WAIT_SECONDS without touching anything.
new_case device_missing
rm -f "$device"
WAIT=3 run_script
check "missing device: fails after waiting WAIT_SECONDS" \
  '[ "$rc" -eq 1 ] && [ "$(grep -c "^sleep 1\$" "$calls")" -eq 3 ] && grep -q "did not appear within 3s" "$dir/out"'
check "missing device: no blkid, mkfs or fstab change" \
  '! grep -q "^blkid\|^mkfs.xfs" "$calls" && [ "$(fstab_lines)" -eq 0 ]'

# Wrong usage is rejected.
new_case usage
# shellcheck disable=SC2034 # rc is read by check()'s eval
if sh "$script" "$device" >"$dir/out" 2>&1; then rc=0; else rc=$?; fi
check "missing argument: exit 64" '[ "$rc" -eq 64 ]'

printf '\n%d passed, %d failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
