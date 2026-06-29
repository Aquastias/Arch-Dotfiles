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

@test "root_adapter_source: ext4 resolves to the single ext4 adapter" {
  run root_adapter_source /os ext4 single
  [ "$status" -eq 0 ]
  [ "$output" = "/os/lib/layout/ext4/single.sh" ]
}

@test "root_adapter_source: ext4 ignores mode (single-disk only)" {
  run root_adapter_source /os ext4 multi
  [ "$status" -eq 0 ]
  [ "$output" = "/os/lib/layout/ext4/single.sh" ]
}

@test "root_adapter_source: xfs resolves to the single xfs adapter" {
  run root_adapter_source /os xfs single
  [ "$status" -eq 0 ]
  [ "$output" = "/os/lib/layout/xfs/single.sh" ]
}

@test "root_adapter_source: xfs ignores mode (single-disk only)" {
  run root_adapter_source /os xfs multi
  [ "$status" -eq 0 ]
  [ "$output" = "/os/lib/layout/xfs/single.sh" ]
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

@test "data_formatter_source: ext4 resolves to the ext4 data formatter" {
  run data_formatter_source /os ext4
  [ "$status" -eq 0 ]
  [ "$output" = "/os/lib/layout/ext4/data.sh" ]
}

@test "data_formatter_source: xfs resolves to the xfs data formatter" {
  run data_formatter_source /os xfs
  [ "$status" -eq 0 ]
  [ "$output" = "/os/lib/layout/xfs/data.sh" ]
}

@test "data_formatter_source: btrfs resolves to the btrfs data formatter" {
  run data_formatter_source /os btrfs
  [ "$status" -eq 0 ]
  [ "$output" = "/os/lib/layout/btrfs/data.sh" ]
}

@test "data_formatter_source: an unbuilt filesystem errors, naming it" {
  run data_formatter_source /os reiserfs
  [ "$status" -ne 0 ]
  [[ "$output" =~ "reiserfs" ]]
}
