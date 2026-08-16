#!/usr/bin/env bats
# Every menu-reachable storage cell renders print_summary (lib/config/
# lifecycle.sh) clean under `set -u`. This is the always-on, unprivileged
# guard for the unbound-variable class that historically only a real install
# summary manifested — e.g. print_summary tripping on a btrfs-multi root
# (ADR 0048), and the single-mode leftover-pool predicate (zfs/pool-owners).
#
# It complements its neighbours rather than repeating them: matrix-assembly
# validates the assembled *config*; layout-record unit-tests the layout_*
# accessors under `set -u`; this runs the real *generator* end-to-end per
# cell. The base fs×topology set is derived live from the generator, so a new
# filesystem or topology is swept automatically (ADR 0046 sync contract).
# See docs/agents/test-regression-catalog.md.

setup() {
  OS_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export OS_DIR SCRIPT_DIR="$OS_DIR"
  # shellcheck source=../../lib/matrix/generator.sh
  source "$OS_DIR/lib/matrix/generator.sh"
  # shellcheck source=../../lib/matrix/assemble.sh
  source "$OS_DIR/lib/matrix/assemble.sh"
}

# _base_cells — plaintext, non-impermanent, no-data-pool cells: the fs ×
# topology core, derived from the generator (not hand-listed).
_base_cells() {
  matrix_tier1_cells | jq -r '
    select(.axes.data_pool == null
      and .axes.encryption == false
      and .axes.impermanence == false) | .id'
}

# _summary_unbound <cell-id> — assemble the cell and render print_summary
# under `set -u`; echoes "unbound" iff the run tripped an unbound variable.
# stdin is /dev/null so the trailing confirmation read returns instead of
# hanging; the summary body renders in full before it.
_summary_unbound() {
  local cell cfg
  cell="$(matrix_tier1_cells | jq -c --arg id "$1" 'select(.id == $id)')"
  cfg="$(mktemp "$BATS_TEST_TMPDIR/cfg.XXXXXX")"
  matrix_cell_assemble "$cell" > "$cfg"
  (
    export CONFIG_FILE="$cfg"
    source "$OS_DIR/lib/common.sh"
    source "$OS_DIR/lib/config/categorized-list.sh"
    source "$OS_DIR/lib/config/accessors.sh"
    source "$OS_DIR/lib/config/lifecycle.sh"
    lsblk() { echo 20G; }   # no real block device in the harness
    load_config >/dev/null 2>&1
    detect_mode  >/dev/null 2>&1
    set -u
    local out
    out="$(print_summary </dev/null 2>&1)"
    grep -q 'unbound variable' <<<"$out" && echo unbound || true
  )
}

@test "print_summary is set-u-clean for every base fs×topology cell" {
  local id fails=""
  while IFS= read -r id; do
    [[ "$(_summary_unbound "$id")" == unbound ]] && fails+="$id "
  done < <(_base_cells)
  [ -z "$fails" ] || { echo "unbound-variable cells: $fails"; false; }
}

@test "print_summary is set-u-clean with a standalone data pool" {
  [ "$(_summary_unbound zfs-mirror-plain-pool-zfs)" != unbound ]
}

# The model-dependent multi branches (os topology `none`, folded leftover
# disks, standalone pools) read the layout record. Populate it as the real
# adapter would (mirroring layout-record's fixture) and render the real
# print_summary end-to-end, so those branches are guarded under `set -u`
# too — not just the accessors in isolation.
@test "print_summary is set-u-clean for the none+leftover model branch" {
  local cell cfg
  cell="$(matrix_tier1_cells | jq -c 'select(.id == "zfs-mirror-plain")')"
  cfg="$(mktemp "$BATS_TEST_TMPDIR/cfg.XXXXXX")"
  matrix_cell_assemble "$cell" > "$cfg"
  run bash -uc "
    export OS_DIR='$OS_DIR' SCRIPT_DIR='$OS_DIR' CONFIG_FILE='$cfg'
    source '$OS_DIR/lib/common.sh'
    source '$OS_DIR/lib/config/categorized-list.sh'
    source '$OS_DIR/lib/config/accessors.sh'
    source '$OS_DIR/lib/config/lifecycle.sh'
    lsblk() { echo 20G; }
    load_config >/dev/null 2>&1
    INSTALL_MODE=multi
    declare -gA _LAYOUT_IMPL_STORAGE_PARTS=([_leftover]='/dev/sdb1 /dev/sdc1')
    declare -gA _LAYOUT_IMPL_TOPOLOGIES=([_leftover]='independent')
    declare -gA _LAYOUT_IMPL_DATA_POOL_MOUNT=([vault]='/mnt/vault')
    declare -gA _LAYOUT_IMPL_DATA_POOL_TOPO=([vault]='raidz1')
    declare -ga _LAYOUT_IMPL_DATA_POOL_NAMES=(vault)
    declare -ga _LAYOUT_IMPL_LEFTOVER_DISKS=(/dev/sdb /dev/sdc)
    _LAYOUT_IMPL_OS_TOPOLOGY=none
    _LAYOUT_IMPL_OS_DISK=/dev/sda
    print_summary </dev/null 2>&1
  "
  [[ "$output" != *"unbound variable"* ]]
}
