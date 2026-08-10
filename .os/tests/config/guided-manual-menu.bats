#!/usr/bin/env bats
# Tests for the Guided Installer's Manual Partitioning surface (ADR 0073): the
# Disks-category toggle sets disk_config.kind; the one-time notice enumerates
# the disabled features; the pool-dependent Disks fields render shown-but-locked
# while manual is on; toggling off is non-destructive. Menu model + controller
# seams, no fzf, no real disks.

setup() {
  TEST_DIR="$(mktemp -d)"
  export GUIDED_STATE_FILE="$TEST_DIR/state.json"
  export GUIDED_NAV_FILE="$TEST_DIR/nav.json"
  export GUIDED_BASELINE_FILE="$TEST_DIR/base.json"

  source "$BATS_TEST_DIRNAME/../../lib/config/state.sh"
  source "$BATS_TEST_DIRNAME/../../lib/config/nav.sh"
  source "$BATS_TEST_DIRNAME/../../lib/config/edits.sh"
  source "$BATS_TEST_DIRNAME/../../lib/config/menu.sh"
  source "$BATS_TEST_DIRNAME/../../lib/config/skeleton.sh"
  source "$BATS_TEST_DIRNAME/../../lib/guided-controller.sh"

  printf '%s\n' '{}' > "$GUIDED_STATE_FILE"
  printf '%s\n' '{}' > "$GUIDED_BASELINE_FILE"
  printf '%s\n' '{"screen":"top"}' > "$GUIDED_NAV_FILE"
}
teardown() { rm -rf "$TEST_DIR"; }

row() { jq -e ".[] | select(.field == \"$1\")"; }
manual_state() { cfgstate_set "$(cfgstate_new)" disk_config.kind '"manual"'; }

# ── the toggle row ──────────────────────────────────────────────────────────

@test "menu_rows: a manual-partitioning row sits under Disks, default auto" {
  run menu_rows "$(cfgstate_new)"
  [ "$status" -eq 0 ]
  echo "$output" | row disk_config.kind | jq -e '.section == "Disks"'
  echo "$output" | row disk_config.kind | jq -e '.value == "auto"'
}

@test "enum options: the manual toggle offers auto and manual" {
  run menu_enum_options disk_config.kind
  [ "$status" -eq 0 ]
  [ "$output" = "auto
manual" ]
}

# ── shown-but-locked dependent fields ───────────────────────────────────────

@test "menu_rows: nothing is locked while auto (the default)" {
  run menu_rows "$(cfgstate_new)"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'all(.[]; .locked == false)'
}

@test "menu_rows: manual locks the pool-dependent Disks fields" {
  run menu_rows "$(manual_state)"
  [ "$status" -eq 0 ]
  echo "$output" | row filesystem                   | jq -e '.locked == true'
  echo "$output" | row options.encryption           | jq -e '.locked == true'
  echo "$output" | row options.impermanence.enabled | jq -e '.locked == true'
  echo "$output" | row options.esp_size             | jq -e '.locked == true'
}

@test "menu_rows: the manual toggle itself is never locked" {
  run menu_rows "$(manual_state)"
  [ "$status" -eq 0 ]
  echo "$output" | row disk_config.kind | jq -e '.locked == false'
}

@test "menu_rows: a non-Disks field is never locked by manual" {
  run menu_rows "$(manual_state)"
  [ "$status" -eq 0 ]
  echo "$output" | row system.hostname | jq -e '.locked == false'
}

# ── the notice ──────────────────────────────────────────────────────────────

@test "notice: enumerates every disabled feature" {
  run menu_manual_notice
  [ "$status" -eq 0 ]
  [[ "$output" =~ [Ee]ncryption ]]
  [[ "$output" =~ [Ii]mpermanence ]]
  [[ "$output" =~ swap ]]
  [[ "$output" =~ ESP ]]
  [[ "$output" =~ (ZFS|pool) ]]
}

# ── controller: apply, notice, lock enforcement, non-destructive off ────────

@test "apply: toggling to manual sets the kind (notice is a directive)" {
  # The notice now rides the manual-on fzf directive (header), not stderr, so
  # apply stays a clean pure state transform.
  local state
  state="$(_ctl_apply_enum "$(cfgstate_new)" disk_config.kind manual)"
  echo "$state" | jq -e '.disk_config.kind == "manual"'
}

@test "apply: a locked field (encryption) is a no-op while manual" {
  local s; s="$(manual_state)"
  run _ctl_apply_enum "$s" options.encryption true
  [ "$status" -ne 0 ]
  echo "$output" | jq -e '.options.encryption == null'
}

@test "apply: the locked esp-size text field is a no-op while manual" {
  local s; s="$(manual_state)"
  run _ctl_apply_text "$s" options.esp_size 4G
  [ "$status" -ne 0 ]
  echo "$output" | jq -e '(.options.esp_size // null) == null'
}

@test "apply: encryption is editable again once manual is off" {
  run _ctl_apply_enum "$(cfgstate_new)" options.encryption true
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.options.encryption == true'
}

@test "toggle: turning manual on emits the manual-on directive" {
  printf '%s\n' '{"screen":"category","category":"Disks"}' > "$GUIDED_NAV_FILE"
  printf '%s\n' '{}' > "$GUIDED_STATE_FILE"
  run _ctl_enter_category "Manual partitioning: off"
  [ "$status" -eq 0 ]
  [ "$output" = "manual-on" ]
  jq -e '.disk_config.kind == "manual"' "$GUIDED_STATE_FILE"
}

@test "toggle: turning manual off emits a plain refresh" {
  printf '%s\n' '{"screen":"category","category":"Disks"}' > "$GUIDED_NAV_FILE"
  printf '%s\n' '{"disk_config":{"kind":"manual"}}' > "$GUIDED_STATE_FILE"
  run _ctl_enter_category "Manual partitioning: on"
  [ "$status" -eq 0 ]
  [ "$output" = "refresh" ]
  jq -e '.disk_config.kind == "auto"' "$GUIDED_STATE_FILE"
}

nav_disks() { printf '%s\n' '{"screen":"category","category":"Disks"}' > "$GUIDED_NAV_FILE"; }

@test "editor: the Partitions row opens the assignment table" {
  nav_disks
  printf '%s\n' '{"disk_config":{"kind":"manual"}}' > "$GUIDED_STATE_FILE"
  run _ctl_enter_category "Partitions ▸ 0 assigned (run cfdisk)"
  [ "$status" -eq 0 ] && [ "$output" = "render" ]
  jq -e '.screen == "manualparts"' "$GUIDED_NAV_FILE"
}

@test "editor: a partition row opens its per-partition editor" {
  printf '%s\n' '{"screen":"manualparts","category":"Disks"}' > "$GUIDED_NAV_FILE"
  printf '%s\n' '{}' > "$GUIDED_STATE_FILE"
  run _ctl_enter_manualparts "/dev/sda3  →  (unassigned)  [format]"
  [ "$status" -eq 0 ] && [ "$output" = "render" ]
  jq -e '.screen == "partedit" and .device == "/dev/sda3"' "$GUIDED_NAV_FILE"
}

@test "editor: cfdisk action is gated in --debug, launches otherwise" {
  printf '%s\n' '{"screen":"manualparts","category":"Disks"}' > "$GUIDED_NAV_FILE"
  printf '%s\n' '{}' > "$GUIDED_STATE_FILE"
  local row="⟳ Run cfdisk (edit the partition table)"
  INSTALL_DEBUG=1 run _ctl_enter_manualparts "$row"
  [[ "$output" == notice* ]]
  INSTALL_DEBUG=0 run _ctl_enter_manualparts "$row"
  [ "$output" = "cfdisk" ]
}

part_nav() {
  printf '%s\n' \
    '{"screen":"partedit","category":"Disks","device":"/dev/sda3"}' \
    > "$GUIDED_NAV_FILE"
}

@test "partedit: Enter cycles the mountpoint" {
  part_nav
  printf '%s\n' \
    '{"disk_config":{"partitions":[{"device":"/dev/sda3","mountpoint":"","fs":"","format":true}]}}' \
    > "$GUIDED_STATE_FILE"
  run _ctl_enter_partedit "mountpoint: (unassigned)   (Enter cycles)"
  [ "$status" -eq 0 ]
  jq -e '.disk_config.partitions[0].mountpoint == "/"' "$GUIDED_STATE_FILE"
}

@test "partedit: Enter cycles the filesystem through supported values only" {
  part_nav
  printf '%s\n' \
    '{"disk_config":{"partitions":[{"device":"/dev/sda3","mountpoint":"/","fs":"ext4","format":true}]}}' \
    > "$GUIDED_STATE_FILE"
  run _ctl_enter_partedit "filesystem: ext4   (Enter cycles)"
  jq -e '.disk_config.partitions[0].fs == "xfs"' "$GUIDED_STATE_FILE"
}

@test "partedit: Enter toggles format" {
  part_nav
  printf '%s\n' \
    '{"disk_config":{"partitions":[{"device":"/dev/sda3","mountpoint":"/","fs":"ext4","format":true}]}}' \
    > "$GUIDED_STATE_FILE"
  run _ctl_enter_partedit "format: on   (Enter toggles)"
  jq -e '.disk_config.partitions[0].format == false' "$GUIDED_STATE_FILE"
}

@test "proceed: blocked with a notice when the manual layout is invalid" {
  printf '%s\n' '{"screen":"top"}' > "$GUIDED_NAV_FILE"
  printf '%s\n' '{"disk_config":{"kind":"manual"}}' > "$GUIDED_STATE_FILE"
  run _ctl_proceed_directive
  [[ "$output" == notice* ]]
  [[ "$output" == *"Partitions"* ]]
}

@test "proceed: allowed once the manual layout is valid" {
  printf '%s\n' '{"screen":"top"}' > "$GUIDED_NAV_FILE"
  printf '%s\n' \
    '{"disk_config":{"kind":"manual","partitions":[{"device":"/dev/sda1","mountpoint":"/boot/efi","fs":"fat32","format":true},{"device":"/dev/sda2","mountpoint":"/","fs":"ext4","format":true}]}}' \
    > "$GUIDED_STATE_FILE"
  run _ctl_proceed_directive
  [ "$output" = "terminal proceed" ]
}

@test "toggle off is non-destructive: a prior override survives" {
  # An override set before manual persists through manual→auto (Config State
  # is non-destructive; the toggle only writes disk_config.kind).
  local s
  s="$(cfgstate_set "$(cfgstate_new)" filesystem '"btrfs"')"
  s="$(_ctl_apply_enum "$s" disk_config.kind manual)"
  s="$(_ctl_apply_enum "$s" disk_config.kind auto)"
  echo "$s" | jq -e '.filesystem == "btrfs"'
  echo "$s" | jq -e '.disk_config.kind == "auto"'
}
