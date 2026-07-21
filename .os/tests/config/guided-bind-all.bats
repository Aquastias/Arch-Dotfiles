#!/usr/bin/env bats
# Tests for In-Menu Disk Binding bind-all — issue 03. Extends binding from data
# pools to the OS pool (topology + disks editable), storage groups
# (binding-only: disks bind, everything else display-only), and the single-disk
# root (a `root disk:` row + picker on-target). Controller seam: per-kind
# pooledit render + dispatch, and the rootdisk screen. Faked by-id via
# PICKER_BY_ID_DIR;
# GUIDED_LIVE_SET="" means no live exclusion. No fzf, no real disks.

setup() {
  TEST_DIR="$(mktemp -d)"
  export GUIDED_STATE_FILE="$TEST_DIR/state.json"
  export GUIDED_NAV_FILE="$TEST_DIR/nav.json"
  export GUIDED_BASELINE_FILE="$TEST_DIR/base.json"

  source "$BATS_TEST_DIRNAME/../../lib/config/state.sh"
  source "$BATS_TEST_DIRNAME/../../lib/config/nav.sh"
  source "$BATS_TEST_DIRNAME/../../lib/config/edits.sh"
  source "$BATS_TEST_DIRNAME/../../lib/config/menu.sh"
  source "$BATS_TEST_DIRNAME/../../lib/guided-controller.sh"

  printf '%s\n' '{}' > "$GUIDED_STATE_FILE"
  printf '%s\n' '{}' > "$GUIDED_BASELINE_FILE"
  printf '%s\n' '{"screen":"top"}' > "$GUIDED_NAV_FILE"

  BY_ID="$TEST_DIR/by-id"; mkdir -p "$BY_ID"
  export PICKER_BY_ID_DIR="$BY_ID" GUIDED_LIVE_SET=""
  : > "$TEST_DIR/n1"; : > "$TEST_DIR/n2"; : > "$TEST_DIR/a3"
  ln -sf ../n1 "$BY_ID/nvme-Disk_One"
  ln -sf ../n2 "$BY_ID/nvme-Disk_Two"
  ln -sf ../a3 "$BY_ID/ata-Disk_Three"

  OS='{"mode":"multi","os_pool":{"pool_name":"rpool","topology":"mirror",
       "disk_count":2}}'
  SG='{"mode":"multi","os_pool":{"pool_name":"rpool","topology":"mirror",
       "disk_count":2},"storage_groups":[{"name":"data","mount":"/data",
       "topology":"raidz1","disk_count":3}]}'
}
teardown() { rm -rf "$TEST_DIR"; }

set_nav() { printf '%s\n' "$1" > "$GUIDED_NAV_FILE"; }

# ── OS pool editor (AC1) ─────────────────────────────────────────────────────

@test "list(pooledit os): topology + disks only, no fs/enc/remove" {
  printf '%s\n' "$OS" > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_pooledit Disks 0 os)"
  run guided_ctl_list
  echo "$output" | grep -q "topology: mirror   (Enter cycles)"
  echo "$output" | grep -q "disks:"
  ! echo "$output" | grep -q "filesystem:"
  ! echo "$output" | grep -q "encryption:"
  ! echo "$output" | grep -q "remove"
}

@test "enter(pooledit os): topology cycles" {
  printf '%s\n' '{"os_pool":{"topology":"stripe","disk_count":2}}' \
    > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_pooledit Disks 0 os)"
  run guided_ctl_enter "topology: stripe   (Enter cycles)"
  [ "$output" = "refresh" ]
  [ "$(jq -r '.os_pool.topology' "$GUIDED_STATE_FILE")" = "mirror" ]
}

@test "enter(pooledit os): device-mode disks opens the sub-screen for os" {
  GUIDED_DEVICE_MODE=1
  printf '%s\n' "$OS" > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_pooledit Disks 0 os)"
  run guided_ctl_enter "disks: 0 bound   (Enter to edit)"
  [ "$output" = "render" ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "pooldisks" ]
  [ "$(nav_get "$(<"$GUIDED_NAV_FILE")" kind)" = "os" ]
}

@test "enter(pooldisks os): binds to os_pool.devices with derived count" {
  GUIDED_DEVICE_MODE=1
  printf '%s\n' "$OS" > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_pooldisks Disks 0 os)"
  run guided_ctl_enter "[ ] nvme-Disk_One"
  [ "$output" = "refresh" ]
  [ "$(jq -r '.os_pool.devices[0]' "$GUIDED_STATE_FILE")" \
    = "$BY_ID/nvme-Disk_One" ]
  [ "$(jq -r '.os_pool.disk_count' "$GUIDED_STATE_FILE")" = "1" ]
}

# ── Storage group editor: topology/disks editable, mount fixed (AC2) ─────────
# Storage groups are authorable in Custom (rebuild os-mirror-raidz1): topology +
# disk count cycle and the group is removable; mount stays display-only and there
# are no per-group fs/encryption rows (a storage group inherits the root fs).

@test "list(pooledit storage): topology/disks editable, mount fixed, removable" {
  GUIDED_DEVICE_MODE=1
  printf '%s\n' "$SG" > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_pooledit Disks 0 storage)"
  run guided_ctl_list
  echo "$output" | grep -q "name: data"
  echo "$output" | grep -q "mount: /data"
  ! echo "$output" | grep -q "mount: /data   (Enter to edit)"
  echo "$output" | grep -q "topology: raidz1   (Enter cycles)"
  echo "$output" | grep -q "disks: 0 bound   (Enter to edit)"
  ! echo "$output" | grep -q "filesystem:"
  echo "$output" | grep -q "remove"
}

@test "enter(pooledit storage): topology cycles (raidz1 → raidz2)" {
  printf '%s\n' "$SG" > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_pooledit Disks 0 storage)"
  run guided_ctl_enter "topology: raidz1   (Enter cycles)"
  [ "$(jq -r '.storage_groups[0].topology' "$GUIDED_STATE_FILE")" = "raidz2" ]
}

@test "enter(pooledit storage): device-mode disks opens the sub-screen" {
  GUIDED_DEVICE_MODE=1
  printf '%s\n' "$SG" > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_pooledit Disks 0 storage)"
  run guided_ctl_enter "disks: 0 bound   (Enter to edit)"
  [ "$output" = "render" ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "pooldisks" ]
  [ "$(nav_get "$(<"$GUIDED_NAV_FILE")" kind)" = "storage" ]
}

@test "enter(pooledit storage): count-mode disks cycles (3 → 4)" {
  GUIDED_DEVICE_MODE=0
  printf '%s\n' "$SG" > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_pooledit Disks 0 storage)"
  run guided_ctl_enter "disks: 3   (Enter cycles 1-8)"
  [ "$(jq -r '.storage_groups[0].disk_count' "$GUIDED_STATE_FILE")" = "4" ]
}

@test "enter(pooledit storage): remove deletes the group, returns to the list" {
  printf '%s\n' "$SG" > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_pooledit Disks 0 storage)"
  run guided_ctl_enter "✗ remove this group"
  [ "$(jq -c '.storage_groups' "$GUIDED_STATE_FILE")" = "[]" ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "datapools" ]
}

# Storage groups share dpool's encryption (the disk-wide setting) — shown read-
# only, so Enter is a no-op (no independent per-group key; that is the data path).
@test "list(pooledit storage): encryption line reflects the disk-wide setting" {
  printf '%s\n' \
    '{"mode":"multi","options":{"encryption":true},"storage_groups":[{"name":"data","mount":"/data","topology":"raidz1","disk_count":3}]}' \
    > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_pooledit Disks 0 storage)"
  run guided_ctl_list
  echo "$output" | grep -q "encryption: on   (disk-wide, shared)"
}

@test "enter(pooledit storage): encryption row is read-only (noop)" {
  printf '%s\n' \
    '{"options":{"encryption":true},"storage_groups":[{"name":"data","mount":"/data","topology":"raidz1","disk_count":3}]}' \
    > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_pooledit Disks 0 storage)"
  run guided_ctl_enter "encryption: on   (disk-wide, shared)"
  [ "$output" = "refresh" ]
  [ "$(jq -r '.storage_groups[0] | has("encryption")' "$GUIDED_STATE_FILE")" = "false" ]
}

# ── single-disk root row + picker (AC3) ──────────────────────────────────────

@test "list(category Disks): device-mode single shows the root disk row" {
  GUIDED_DEVICE_MODE=1
  set_nav "$(nav_to_category Disks)"
  run guided_ctl_list
  echo "$output" | grep -q "root disk:"
}

@test "list(category Disks): count-mode has no root disk row" {
  GUIDED_DEVICE_MODE=0
  set_nav "$(nav_to_category Disks)"
  run guided_ctl_list
  ! echo "$output" | grep -q "root disk:"
}

@test "list(category Disks): device-mode multi has no root disk row" {
  GUIDED_DEVICE_MODE=1
  printf '%s\n' "$OS" > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_category Disks)"
  run guided_ctl_list
  ! echo "$output" | grep -q "root disk:"
}

@test "enter(category root disk): opens the rootdisk picker" {
  GUIDED_DEVICE_MODE=1
  set_nav "$(nav_to_category Disks)"
  run guided_ctl_enter "root disk: (none)   (Enter to pick)"
  [ "$output" = "render" ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "rootdisk" ]
}

@test "list(rootdisk): lists free disks + Back" {
  set_nav "$(nav_to_rootdisk Disks)"
  run guided_ctl_list
  echo "$output" | grep -q "nvme-Disk_One"
  echo "$output" | grep -q "← Back"
}

@test "enter(rootdisk): picking a disk sets root_disk + returns to category" {
  set_nav "$(nav_to_rootdisk Disks)"
  run guided_ctl_enter "( ) nvme-Disk_Two"
  [ "$output" = "render" ]
  [ "$(jq -r '.root_disk' "$GUIDED_STATE_FILE")" = "$BY_ID/nvme-Disk_Two" ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "category" ]
}

@test "enter(rootdisk): a second pick replaces the first" {
  printf '{"root_disk":"%s/nvme-Disk_One"}\n' "$BY_ID" > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_rootdisk Disks)"
  run guided_ctl_enter "( ) ata-Disk_Three"
  [ "$(jq -r '.root_disk' "$GUIDED_STATE_FILE")" = "$BY_ID/ata-Disk_Three" ]
}

@test "enter(rootdisk): Back returns to the category" {
  set_nav "$(nav_to_rootdisk Disks)"
  run guided_ctl_enter "← Back"
  [ "$output" = "render" ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "category" ]
}

# ── cross-group Free Set (AC4) ───────────────────────────────────────────────

@test "_ctl_free_disks: a disk bound to os is not free for a data pool" {
  local s='{"os_pool":{"devices":["'"$BY_ID"'/nvme-Disk_One"]},
            "data_pools":[{"name":"tank0"}]}'
  run _ctl_free_disks "$s"
  ! echo "$output" | grep -q "nvme-Disk_One"
  echo "$output" | grep -q "nvme-Disk_Two"
}

@test "_ctl_free_disks: the single-disk root pick disappears everywhere" {
  local s='{"root_disk":"'"$BY_ID"'/ata-Disk_Three"}'
  run _ctl_free_disks "$s"
  ! echo "$output" | grep -q "ata-Disk_Three"
}

@test "list(rootdisk): the current pick shows marked, still selectable" {
  printf '{"root_disk":"%s/nvme-Disk_One"}\n' "$BY_ID" > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_rootdisk Disks)"
  run guided_ctl_list
  echo "$output" | grep -q '^(\*) nvme-Disk_One'
  echo "$output" | grep -q '^( ) nvme-Disk_Two'
}
