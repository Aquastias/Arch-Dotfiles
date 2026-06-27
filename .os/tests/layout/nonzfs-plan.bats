#!/usr/bin/env bats
# Tests for the shared non-ZFS partition planner (ADR 0043) — the pure
# arithmetic core under the ext4/xfs/btrfs Root Adapters. Given the disk size
# and the ESP + swap sizes (all MiB), it computes the root partition (the
# remainder) and validates there is room, emitting a `key=value` plan the
# adapter turns into sgdisk calls. Pure: no disk access.

setup() {
  # error() aborts in production (common.sh exits); mirror that so a failed
  # validation stops the function rather than falling through.
  error() { echo "ERROR: $*" >&2; exit 1; }
  export -f error
  # shellcheck source=../../lib/layout/nonzfs/plan.sh
  source "$BATS_TEST_DIRNAME/../../lib/layout/nonzfs/plan.sh"
}

# Helper: extract a key=value field from the plan output.
plan_field() { grep -E "^$1=" | cut -d= -f2; }

# ── tracer: ESP + swap + root(remainder) ────────────────────────────────────

@test "plan: root is the remainder after ESP + swap + alignment" {
  # 40 GiB = 40960 MiB; 512 ESP; 8192 swap; 2 MiB alignment guard.
  run nonzfs_partition_plan 40960 512 8192
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | plan_field esp_mib)"  = "512" ]
  [ "$(printf '%s\n' "$output" | plan_field swap_mib)" = "8192" ]
  [ "$(printf '%s\n' "$output" | plan_field root_mib)" = "32254" ]
}

@test "plan: swap 0 means no swap partition; root absorbs the space" {
  run nonzfs_partition_plan 40960 512 0
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | plan_field swap_mib)" = "0" ]
  [ "$(printf '%s\n' "$output" | plan_field root_mib)" = "40446" ]
}

@test "plan: a root below the floor is rejected, naming the shortfall" {
  # 9 GiB disk, 512 ESP, 4096 swap → root ~4546 MiB < 8192 floor.
  run nonzfs_partition_plan 9216 512 4096
  [ "$status" -ne 0 ]
  [[ "$output" =~ "floor" ]]
}
