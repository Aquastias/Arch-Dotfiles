#!/usr/bin/env bats
# Tests for freeform custom layouts — issue 05. The data-pools editor becomes a
# UNIFIED layout editor listing OS pool + storage groups + data pools; a data
# pool gains an editable mount row (default /<name>); a `Custom…` preset seeds a
# blank multi skeleton; and every multi preset now OPENS the editor instead of
# backing out. Controller + skeleton seams, no fzf, no real disks.

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

  # a multi skeleton with all three kinds present
  ALL='{"mode":"multi",
        "os_pool":{"pool_name":"rpool","topology":"mirror","disk_count":2},
        "storage_groups":[{"name":"data","mount":"/data",
                           "topology":"raidz1","disk_count":3}],
        "data_pools":[{"name":"tank0","topology":"mirror","disk_count":2}]}'
}
teardown() { rm -rf "$TEST_DIR"; }

set_nav() { printf '%s\n' "$1" > "$GUIDED_NAV_FILE"; }

# ── Custom… seed (skeleton seam) ─────────────────────────────────────────────

@test "skeleton_custom_seed: blank multi with a single-disk none OS pool" {
  run skeleton_custom_seed
  [ "$status" -eq 0 ]
  [ "$(jq -r '.mode' <<<"$output")" = "multi" ]
  [ "$(jq -r '.os_pool.pool_name' <<<"$output")" = "rpool" ]
  [ "$(jq -r '.os_pool.topology' <<<"$output")" = "none" ]
  [ "$(jq -r '.os_pool.disk_count' <<<"$output")" = "1" ]
  [ "$(jq -r '.data_pools // "absent"' <<<"$output")" = "absent" ]
}

# ── unified editor list (AC1) ────────────────────────────────────────────────

@test "list(datapools): lists OS pool + storage + data pools together" {
  printf '%s\n' "$ALL" > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_datapools Disks)"
  run guided_ctl_list
  echo "$output" | grep -q "OS pool: mirror ×2"
  echo "$output" | grep -q "data (storage): raidz1 ×3"
  echo "$output" | grep -q "tank0: mirror ×2"
  echo "$output" | grep -q "+ Add data pool"
  echo "$output" | grep -q "← Back"
}

@test "list(datapools): offers both + Add data pool and + Add storage group" {
  printf '%s\n' "$ALL" > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_datapools Disks)"
  run guided_ctl_list
  echo "$output" | grep -q "+ Add data pool"
  echo "$output" | grep -q "+ Add storage group"
}

@test "enter(datapools): + Add storage group appends data at /data (mirror ×2)" {
  set_nav "$(nav_to_datapools Disks)"
  run guided_ctl_enter "+ Add storage group"
  [ "$output" = "refresh" ]
  [ "$(jq -r '.storage_groups[0].name' "$GUIDED_STATE_FILE")" = "data" ]
  [ "$(jq -r '.storage_groups[0].mount' "$GUIDED_STATE_FILE")" = "/data" ]
  [ "$(jq -r '.storage_groups[0].topology' "$GUIDED_STATE_FILE")" = "mirror" ]
  [ "$(jq -r '.storage_groups[0].disk_count' "$GUIDED_STATE_FILE")" = "2" ]
  [ "$(jq -r '.mode' "$GUIDED_STATE_FILE")" = "multi" ]
}

@test "enter(datapools): a second + Add storage group auto-names it data1" {
  printf '%s\n' \
    '{"storage_groups":[{"name":"data","mount":"/data","topology":"raidz1","disk_count":3}]}' \
    > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_datapools Disks)"
  run guided_ctl_enter "+ Add storage group"
  [ "$(jq -r '.storage_groups[1].name' "$GUIDED_STATE_FILE")" = "data1" ]
  [ "$(jq -r '.storage_groups[1].mount' "$GUIDED_STATE_FILE")" = "/data1" ]
}

# End-to-end: Custom seed → OS mirror ×2 + a raidz1 ×3 storage group is byte-
# identical to the os-mirror-raidz1 preset (AC3: reconstruct every preset).
@test "custom authoring reconstructs the os-mirror-raidz1 preset exactly" {
  _ctl_write_state "$(edit_apply_skeleton '{}' "$(skeleton_custom_seed)")"
  # OS pool → mirror ×2
  set_nav "$(nav_to_pooledit Disks 0 os)"
  guided_ctl_enter "topology: none   (Enter cycles)" >/dev/null
  guided_ctl_enter "disks: 1   (Enter cycles 1-8)" >/dev/null
  # + storage group → raidz1 ×3
  set_nav "$(nav_to_datapools Disks)"
  guided_ctl_enter "+ Add storage group" >/dev/null
  set_nav "$(nav_to_pooledit Disks 0 storage)"
  guided_ctl_enter "topology: mirror   (Enter cycles)" >/dev/null
  guided_ctl_enter "disks: 2   (Enter cycles 1-8)" >/dev/null

  local authored preset
  authored="$(jq -S '{mode,os_pool,storage_groups}' "$GUIDED_STATE_FILE")"
  preset="$(skeleton_preset os-mirror-raidz1 | jq -S '{mode,os_pool,storage_groups}')"
  [ "$authored" = "$preset" ]
}

@test "enter(datapools): the OS pool row opens the os pool editor" {
  printf '%s\n' "$ALL" > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_datapools Disks)"
  run guided_ctl_enter "OS pool: mirror ×2"
  [ "$output" = "render" ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "pooledit" ]
  [ "$(nav_get "$(<"$GUIDED_NAV_FILE")" kind)" = "os" ]
}

@test "enter(datapools): a storage row opens its editor by index" {
  printf '%s\n' "$ALL" > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_datapools Disks)"
  run guided_ctl_enter "data (storage): raidz1 ×3"
  [ "$output" = "render" ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "pooledit" ]
  [ "$(nav_get "$(<"$GUIDED_NAV_FILE")" kind)" = "storage" ]
  [ "$(nav_get "$(<"$GUIDED_NAV_FILE")" index)" = "0" ]
}

@test "enter(datapools): a data pool row still opens its editor by index" {
  printf '%s\n' "$ALL" > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_datapools Disks)"
  run guided_ctl_enter "tank0: mirror ×2"
  [ "$output" = "render" ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "pooledit" ]
  [ "$(nav_get "$(<"$GUIDED_NAV_FILE")" kind)" = "data" ]
  [ "$(nav_get "$(<"$GUIDED_NAV_FILE")" index)" = "0" ]
}

# ── data pool mount row (AC2) ────────────────────────────────────────────────

@test "list(pooledit data): shows a mount row defaulting to /<name>" {
  printf '%s\n' '{"data_pools":[{"name":"tank0","topology":"mirror","disk_count":2}]}' \
    > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_pooledit Disks 0 data)"
  run guided_ctl_list
  echo "$output" | grep -q "mount: /tank0   (Enter to edit)"
}

@test "list(pooledit data): a set mount is shown verbatim" {
  printf '%s\n' '{"data_pools":[{"name":"tank0","mount":"/srv/x","topology":"mirror","disk_count":2}]}' \
    > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_pooledit Disks 0 data)"
  run guided_ctl_list
  echo "$output" | grep -q "mount: /srv/x   (Enter to edit)"
}

@test "enter(pooledit data): the mount row opens a text editor" {
  printf '%s\n' '{"data_pools":[{"name":"tank0","topology":"mirror","disk_count":2}]}' \
    > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_pooledit Disks 0 data)"
  run guided_ctl_enter "mount: /tank0   (Enter to edit)"
  [ "$output" = "render" ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "text" ]
  [ "$(nav_get "$(<"$GUIDED_NAV_FILE")" field)" = "__poolmount__" ]
  [ "$(nav_get "$(<"$GUIDED_NAV_FILE")" index)" = "0" ]
}

@test "enter(text __poolmount__): a typed mount commits to the data pool" {
  printf '%s\n' '{"data_pools":[{"name":"tank0","topology":"mirror","disk_count":2}]}' \
    > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_poolmount Disks 0)"
  run guided_ctl_enter "" "/srv/media"
  [ "$output" = "render" ]
  [ "$(jq -r '.data_pools[0].mount' "$GUIDED_STATE_FILE")" = "/srv/media" ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "pooledit" ]
}

@test "enter(text __poolmount__): a blank input keeps the default (no mount)" {
  printf '%s\n' '{"data_pools":[{"name":"tank0","topology":"mirror","disk_count":2}]}' \
    > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_poolmount Disks 0)"
  run guided_ctl_enter "" ""
  [ "$output" = "render" ]
  [ "$(jq -r '.data_pools[0] | has("mount")' "$GUIDED_STATE_FILE")" = "false" ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "pooledit" ]
}

# storage mount is display-only — Enter on it is a no-op.
@test "enter(pooledit storage): the mount row is display-only (noop)" {
  printf '%s\n' "$ALL" > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_pooledit Disks 0 storage)"
  run guided_ctl_enter "mount: /data"
  [ "$output" = "refresh" ]
  [ "$(jq -r '.storage_groups[0].mount' "$GUIDED_STATE_FILE")" = "/data" ]
}

# ── Custom… + preset entry flow (AC3, AC4) ───────────────────────────────────

@test "list(values __layout__): Custom… appears in the preset picker" {
  set_nav "$(nav_to_values Disks __layout__ "layout")"
  run guided_ctl_list
  echo "$output" | grep -q "Custom…"
}

@test "enter(values __layout__): Custom… seeds a blank multi + opens the editor" {
  set_nav "$(nav_to_values Disks __layout__ "layout")"
  run guided_ctl_enter "Custom…"
  [ "$output" = "render" ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "datapools" ]
  [ "$(jq -r '.mode' "$GUIDED_STATE_FILE")" = "multi" ]
  [ "$(jq -r '.os_pool.topology' "$GUIDED_STATE_FILE")" = "none" ]
}

@test "enter(values __layout__): a multi preset opens the editor, not back-out" {
  set_nav "$(nav_to_values Disks __layout__ "layout")"
  run guided_ctl_enter "os-mirror"
  [ "$output" = "render" ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "datapools" ]
  [ "$(jq -r '.os_pool.topology' "$GUIDED_STATE_FILE")" = "mirror" ]
}

@test "enter(values __layout__): os-mirror-raidz1 opens the editor" {
  set_nav "$(nav_to_values Disks __layout__ "layout")"
  run guided_ctl_enter "os-mirror-raidz1"
  [ "$output" = "render" ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "datapools" ]
  [ "$(jq -r '.storage_groups[0].name' "$GUIDED_STATE_FILE")" = "data" ]
}

@test "enter(values __layout__): single applies and backs out to the category" {
  set_nav "$(nav_to_values Disks __layout__ "layout")"
  run guided_ctl_enter "single"
  [ "$output" = "render" ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "category" ]
  [ "$(jq -r '.mode' "$GUIDED_STATE_FILE")" = "single" ]
}
