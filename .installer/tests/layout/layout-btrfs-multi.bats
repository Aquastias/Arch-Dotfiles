#!/usr/bin/env bats
# Tests for .installer/lib/layout/btrfs/multi.sh — the multi-disk btrfs root.
#
# Strategy (as layout-single.bats): stub every disk command to append its
# argv to $CALLS, drive the seam verbs in phase order, assert on $CALLS.

_stub_layout_commands() {
  info() { :; }; warn() { :; }; section() { :; }; confirm() { :; }
  blockdev()  { echo $((100 * 1024 * 1024 * 1024)); }
  layout_disk_exists() { return 0; }
  zfs_ram_gib() { echo 4; }
  local command_name
  for command_name in wipefs sgdisk partprobe mkfs.fat mkfs.btrfs mkfs.ext4 \
      mount umount mkdir btrfs mkswap modprobe; do
    eval "${command_name}() { printf '${command_name} %s\n' \"\$*\" >>\"\$CALLS\"; }"
  done
  sleep() { :; }; udevadm() { :; }
  blkid() { echo UUID-X; }
  part_name() { printf '%s%s' "$1" "$2"; }
}

setup() {
  TEST_DIR="$(mktemp -d)"
  CALLS="$TEST_DIR/calls"; : >"$CALLS"
  CONFIG_FILE="$TEST_DIR/install.json"
  MOUNT_ROOT=/mnt
  INSTALLER_DIR="$BATS_TEST_DIRNAME/../.."
  export CONFIG_FILE INSTALLER_DIR
  source "$BATS_TEST_DIRNAME/../../lib/common.sh"
  source "$BATS_TEST_DIRNAME/../../lib/config/install-config.sh"
  source "$BATS_TEST_DIRNAME/../../lib/layout/btrfs/multi.sh"
  _stub_layout_commands
  cat >"$CONFIG_FILE" <<'JSON'
{ "filesystem": "btrfs", "options": {"swap": false},
  "os_pool": {"topology": "raid1", "disks": ["/dev/vda", "/dev/vdb"]},
  "data_pools": [{"name": "tank", "filesystem": "ext4", "topology": "single",
                  "disks": ["/dev/vdc"], "mount": "/data/tank"}] }
JSON
  layout_validate
  layout_plan
  layout_partition
  layout_create_pools
  layout_mount_esp
}

teardown() { rm -rf "$TEST_DIR"; }

@test "btrfs multi: declared data pools are partitioned and formatted" {
  grep -q '^sgdisk -n1:0:0 .* /dev/vdc$' "$CALLS"
  grep -q '^mkfs.ext4 -F /dev/vdc1$' "$CALLS"
  grep -q '^mount /dev/vdc1 /mnt/data/tank$' "$CALLS"
  [ "${LAYOUT_DATA_POOL_NAMES[*]}" = "tank" ]
}

@test "btrfs multi: every ESP is mounted (secondaries at /boot/efiN)" {
  grep -q '^mount /dev/vda1 /mnt/boot/efi$' "$CALLS"
  grep -q '^mount /dev/vdb1 /mnt/boot/efi1$' "$CALLS"
}
