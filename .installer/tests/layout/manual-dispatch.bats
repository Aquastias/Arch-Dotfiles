#!/usr/bin/env bats
# Tests for the disk-config kind dispatch (ADR 0073): root_adapter_for_kind
# routes a `manual` disk kind to the manual Root Layout Adapter regardless of
# filesystem/mode, and otherwise delegates to the filesystem × mode table.
# Pure: string transforms on the arguments, no disk access.

setup() {
  error() { echo "ERROR: $*" >&2; exit 1; }
  export -f error
  # shellcheck source=../../lib/layout/dispatch.sh
  source "$BATS_TEST_DIRNAME/../../lib/layout/dispatch.sh"
}

@test "dispatch: manual kind selects the manual adapter, ignoring filesystem" {
  run root_adapter_for_kind /os manual zfs single
  [ "$status" -eq 0 ]
  [ "$output" = "/os/lib/layout/manual/root.sh" ]
}

@test "dispatch: manual kind ignores mode too" {
  run root_adapter_for_kind /os manual ext4 multi
  [ "$status" -eq 0 ]
  [ "$output" = "/os/lib/layout/manual/root.sh" ]
}

@test "dispatch: auto kind delegates to the zfs × mode adapter" {
  run root_adapter_for_kind /os auto zfs single
  [ "$status" -eq 0 ]
  [ "$output" = "/os/lib/layout/zfs/single.sh" ]
}

@test "dispatch: auto kind delegates to the ext4 adapter" {
  run root_adapter_for_kind /os auto ext4 single
  [ "$status" -eq 0 ]
  [ "$output" = "/os/lib/layout/ext4/single.sh" ]
}
