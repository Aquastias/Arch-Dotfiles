#!/usr/bin/env bats
# Tests for lib/layout/dispatch.sh — the filesystem-keyed layout dispatch
# (ADR 0040, split by ADR 0043). Two seams: root_adapter_source maps
# (filesystem, mode) → the Root Layout Adapter to source; data_formatter_source
# maps (filesystem) → the Data Group Formatter. ZFS is the only built adapter and
# now lives under lib/layout/zfs/; any other filesystem errors. Pure: string
# transforms, no disk access.

setup() {
  error() { echo "ERROR: $*" >&2; return 1; }
  export -f error

  # shellcheck source=../../lib/layout/dispatch.sh
  source "$BATS_TEST_DIRNAME/../../lib/layout/dispatch.sh"
}

# ── root_adapter_source: filesystem × mode → the relocated zfs/ adapter ──────

@test "root_adapter_source: zfs single resolves to lib/layout/zfs/single.sh" {
  run root_adapter_source /os zfs single
  [ "$status" -eq 0 ]
  [ "$output" = "/os/lib/layout/zfs/single.sh" ]
}

@test "root_adapter_source: the mode keys the adapter file (multi)" {
  run root_adapter_source /os zfs multi
  [ "$status" -eq 0 ]
  [ "$output" = "/os/lib/layout/zfs/multi.sh" ]
}

@test "root_adapter_source: an unbuilt filesystem errors, naming it" {
  run root_adapter_source /os btrfs single
  [ "$status" -ne 0 ]
  [[ "$output" =~ "btrfs" ]]
}

# ── data_formatter_source: filesystem → the Data Group Formatter (no mode) ───

@test "data_formatter_source: zfs resolves to the zfs data-pool module" {
  run data_formatter_source /os zfs
  [ "$status" -eq 0 ]
  [ "$output" = "/os/lib/layout/zfs/multi.sh" ]
}

@test "data_formatter_source: an unbuilt filesystem errors, naming it" {
  run data_formatter_source /os ext4
  [ "$status" -ne 0 ]
  [[ "$output" =~ "ext4" ]]
}
