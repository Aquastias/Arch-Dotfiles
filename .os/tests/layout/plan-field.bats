#!/usr/bin/env bats
# Tests for nonzfs_plan_field (lib/layout/core.sh) — the single `key=value`
# plan-text reader shared by the non-ZFS root spine (root.sh), the device
# resolver (devices.sh), the data formatter (data.sh), and the btrfs multi
# adapter. Formerly four byte-identical copies (_nzroot_field / _nonzfs_plan_
# field / _data_plan_field). Pure: grep + cut on stdin, no deps.

setup() {
  # shellcheck source=../../lib/layout/core.sh
  source "$BATS_TEST_DIRNAME/../../lib/layout/core.sh"
}

plan() {
  printf '%s\n' \
    "esp_part_num=1" "swap_part_num=2" "root_part_num=3" \
    "keylocation=file:///etc/cryptsetup-keys.d/tank0.key" "root_mib=51200"
}

@test "nonzfs_plan_field: reads a field's value" {
  [ "$(plan | nonzfs_plan_field root_part_num)" = "3" ]
  [ "$(plan | nonzfs_plan_field root_mib)" = "51200" ]
}

@test "nonzfs_plan_field: keeps a value containing '=' intact" {
  [ "$(plan | nonzfs_plan_field keylocation)" \
      = "file:///etc/cryptsetup-keys.d/tank0.key" ]
}

@test "nonzfs_plan_field: absent field emits nothing" {
  [ -z "$(plan | nonzfs_plan_field missing)" ]
}

@test "nonzfs_plan_field: anchors to line start (no substring match)" {
  # 'swap_part_num=2' must not match a query for the substring 'part_num'.
  [ -z "$(plan | nonzfs_plan_field part_num)" ]
}
