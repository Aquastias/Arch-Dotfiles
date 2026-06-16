#!/usr/bin/env bats
# Tests for lib/layout/dispatch.sh — the filesystem-keyed layout adapter seam
# (ADR 0040). layout_adapter_source maps (filesystem, mode) → the adapter file
# to source. ZFS is the only implemented adapter and keeps the flat
# lib/layout/<mode>.sh path (the zfs/ relocation is deferred to filesystem #2);
# any other filesystem errors. Pure: a string transform, no disk access.

setup() {
  error() { echo "ERROR: $*" >&2; return 1; }
  export -f error

  # shellcheck source=../../lib/layout/dispatch.sh
  source "$BATS_TEST_DIRNAME/../../lib/layout/dispatch.sh"
}

# ── tracer: zfs resolves to the flat single-mode adapter ────────────────────

@test "layout_adapter_source: zfs single resolves to lib/layout/single.sh" {
  run layout_adapter_source /os zfs single
  [ "$status" -eq 0 ]
  [ "$output" = "/os/lib/layout/single.sh" ]
}

@test "layout_adapter_source: the mode keys the adapter file (multi)" {
  run layout_adapter_source /os zfs multi
  [ "$status" -eq 0 ]
  [ "$output" = "/os/lib/layout/multi.sh" ]
}

@test "layout_adapter_source: an unbuilt filesystem errors, naming it" {
  run layout_adapter_source /os btrfs single
  [ "$status" -ne 0 ]
  [[ "$output" =~ "btrfs" ]]
}
