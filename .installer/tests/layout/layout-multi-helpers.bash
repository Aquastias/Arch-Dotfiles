# layout-multi-helpers.bash — shared setup for the layout-multi-*.bats parts
# Tests for .installer/lib/layout/zfs/multi.sh — pure topology suggestion
# functions.
# layout_suggest_os_topologies and layout_suggest_storage_topologies have no system calls.

setup() {
  TEST_DIR="$(mktemp -d)"
  CONFIG_FILE="$TEST_DIR/install.json"
  export CONFIG_FILE
  printf '{}' > "$CONFIG_FILE"
  # shellcheck source=../../lib/common.sh
  source "$BATS_TEST_DIRNAME/../../lib/common.sh"
  # shellcheck source=../../lib/zfs/pools.sh
  source "$BATS_TEST_DIRNAME/../../lib/zfs/pools.sh"
  # shellcheck source=../../lib/config/install-config.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/install-config.sh"
  # shellcheck source=../../lib/zfs/pool-owners.sh
  source "$BATS_TEST_DIRNAME/../../lib/zfs/pool-owners.sh"
  # shellcheck source=../../lib/layout/zfs/multi.sh
  source "$BATS_TEST_DIRNAME/../../lib/layout/zfs/multi.sh"
  _LAYOUT_PHASE=1  # simulate validate phase having run
}

teardown() {
  rm -rf "$TEST_DIR"
}
# Drives the full seam chain through both wrappers and asserts
# _LAYOUT_PHASE reaches the final ordinal. Stubs external commands and the
# zfs-pools.sh / install-config.sh seams the same way layout-single.bats does.

setup_phase_smoke_fixture() {
  CALLS="$TEST_DIR/calls.log"
  export CALLS MOUNT_ROOT="$TEST_DIR/mnt"
  mkdir -p "$MOUNT_ROOT"

  cat >"$CONFIG_FILE" <<'JSONC'
{
  "os_pool":  { "pool_name": "rpool",
                "topology":  "mirror",
                "disks":     ["/dev/sdx", "/dev/sdy"] },
  "storage_groups": []
}
JSONC

  # shellcheck source=../../lib/config/install-config.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/install-config.sh"

  info()    { :; }
  warn()    { :; }
  section() { :; }
  confirm() { :; }
  pick_option() { PICK_RESULT="${2:-mirror}"; }

  wipefs()    { printf 'wipefs %s\n'    "$*" >>"$CALLS"; }
  sgdisk()    { printf 'sgdisk %s\n'    "$*" >>"$CALLS"; }
  partprobe() { printf 'partprobe %s\n' "$*" >>"$CALLS"; }
  mkfs.fat()  { printf 'mkfs.fat %s\n'  "$*" >>"$CALLS"; }
  mount()     { printf 'mount %s\n'     "$*" >>"$CALLS"; }
  lsblk()     { echo "?"; }
  sleep()     { :; }
  part_name() { printf '%s%s' "$1" "$2"; }

  zfs_encryption_options()      { :; }
  zfs_create_pool()       { printf 'zfs_create_pool %s\n'       "$*" >>"$CALLS"; }
  zfs_create_os_datasets() { printf 'zfs_create_os_datasets %s\n' "$*" >>"$CALLS"; }
  zfs()                 { printf 'zfs %s\n'                 "$*" >>"$CALLS"; }
  zpool()               { printf 'zpool %s\n'               "$*" >>"$CALLS"; }
}
# Drives the plan step with a stubbed lsblk (so no real disks needed) and a
# warn() that echoes to stdout, then asserts on the captured $output.

setup_data_pool_size_fixture() {
  # shellcheck source=../../lib/config/install-config.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/install-config.sh"
  section() { :; }
  info()    { :; }
  warn()    { echo "WARN: $*"; }
  # lsblk -bdno SIZE <disk> → bytes; lsblk -dno SIZE <disk> → human.
  lsblk() {
    local disk="${!#}" human bytes
    case "$disk" in
    *da) human="100G"; bytes="$((100 * 1024 * 1024 * 1024))" ;;
    *db) human="200G"; bytes="$((200 * 1024 * 1024 * 1024))" ;;
    *dc) human="100G"; bytes="$((100 * 1024 * 1024 * 1024))" ;;
    *)   human="?";    bytes="0" ;;
    esac
    if [[ "$*" == *-b* ]]; then printf '%s\n' "$bytes"
    else printf '%s\n' "$human"; fi
  }
}

write_multi_config() { printf '%s' "$1" >"$CONFIG_FILE"; }

_find_block_device() {
  local device
  for device in /dev/loop0 /dev/loop1 /dev/sda /dev/nvme0n1 /dev/vda /dev/ram0; do
    [[ -b "$device" ]] && { printf %s "$device"; return; }
  done
  return 1
}
# Drives the real plan→partition→pools seam chain with stubbed prompts and
# zpool/zfs, then asserts on the create-path call log — interactively
# synthesized pools must go through the SAME path as declarative data_pools[].

setup_leftover_fixture() {
  CALLS="$TEST_DIR/calls.log"
  export CALLS MOUNT_ROOT="$TEST_DIR/mnt"
  mkdir -p "$MOUNT_ROOT"

  # layout_create_data_pools now dispatches every group (zfs included) through the Data
  # Group Formatter seam (data_formatter_source "$INSTALLER_DIR" <fs>), so the leaf must
  # be resolvable; the mocked zfs_create_pool/zfs/etc below survive its guarded
  # sources (they only load pools.sh when the primitive is not already a function).
  export INSTALLER_DIR; INSTALLER_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"

  # shellcheck source=../../lib/config/install-config.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/install-config.sh"

  info()    { :; }
  warn()    { :; }
  section() { :; }
  confirm() { :; }
  lsblk()   { echo "?"; }
  sleep()   { :; }
  part_name() { printf '%s%s' "$1" "$2"; }

  wipefs()    { :; }
  sgdisk()    { :; }
  partprobe() { :; }
  mkfs.fat()  { :; }
  mount()     { :; }

  zfs_encryption_options()      { :; }
  zfs_create_pool()       { printf 'zfs_create_pool %s\n'       "$*" >>"$CALLS"; }
  zfs_create_os_datasets() { printf 'zfs_create_os_datasets %s\n' "$*" >>"$CALLS"; }
  zfs()                 { printf 'zfs %s\n'                 "$*" >>"$CALLS"; }
  zpool()               { printf 'zpool %s\n'               "$*" >>"$CALLS"; }

  # Empty line input → accept the default pool name.
  _zfs_multi_topology_read_tty() { printf ''; }

  # pick_option mimic (first word of a chosen option): choose own-pool (2nd
  # option) for any per-disk leftover prompt; option 1 (the OS disk) elsewhere.
  pick_option() {
    local question="$1"; shift
    local index=0
    [[ "$question" == *"Leftover disk"* ]] && index=1
    PICK_RESULT="$(echo "${@:$((index + 1)):1}" | awk '{print $1}')"
  }
}

