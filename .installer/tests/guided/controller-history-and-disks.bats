#!/usr/bin/env bats
# Tests: history, values and disks (split from controller.bats;
# shared setup in controller-helpers.bash)

load controller-helpers


# ── undo / redo / reset (slice 03) ───────────────────────────────────────────

@test "autocommit: guided_controller_list snapshots a changed state for undo" {
  export GUIDED_HIST_FILE="$TEST_DIR/hist"
  history_new '{}' > "$GUIDED_HIST_FILE"
  printf '%s\n' '{"options":{"encryption":true}}' > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_category Disks)"
  guided_controller_list >/dev/null     # the single choke point commits the change
  [ "$(history_present "$(<"$GUIDED_HIST_FILE")" | jq -c '.options.encryption')" \
    = "true" ]
}

@test "key ctrl-z: undoes the last edit, restoring the prior state" {
  export GUIDED_HIST_FILE="$TEST_DIR/hist"
  history_new '{}' > "$GUIDED_HIST_FILE"
  printf '%s\n' '{"options":{"encryption":true}}' > "$GUIDED_STATE_FILE"
  guided_controller_list >/dev/null     # autocommit the change
  run guided_controller_key ctrl-z
  [ "$output" = "render" ]
  [ "$(jq -c '. == {}' "$GUIDED_STATE_FILE")" = "true" ]
}

@test "key ctrl-y: redoes an undone edit" {
  export GUIDED_HIST_FILE="$TEST_DIR/hist"
  history_new '{}' > "$GUIDED_HIST_FILE"
  printf '%s\n' '{"a":1}' > "$GUIDED_STATE_FILE"
  guided_controller_list >/dev/null
  guided_controller_key ctrl-z >/dev/null
  run guided_controller_key ctrl-y
  [ "$output" = "render" ]
  [ "$(jq -c '.a' "$GUIDED_STATE_FILE")" = "1" ]
}

@test "key ctrl-r: resets every override, and is itself undoable" {
  export GUIDED_HIST_FILE="$TEST_DIR/hist"
  printf '%s\n' '{"a":1}' > "$GUIDED_STATE_FILE"
  history_new '{"a":1}' > "$GUIDED_HIST_FILE"
  run guided_controller_key ctrl-r
  [ "$output" = "render" ]
  [ "$(jq -c '. == {}' "$GUIDED_STATE_FILE")" = "true" ]
  guided_controller_key ctrl-z >/dev/null              # undo the reset
  [ "$(jq -c '.a' "$GUIDED_STATE_FILE")" = "1" ]
}

@test "key ctrl-r: from inside a pool editor backs out to the category (no ?)" {
  export GUIDED_HIST_FILE="$TEST_DIR/hist"
  printf '%s\n' \
    '{"mode":"multi","os_pool":{"pool_name":"rpool","topology":"mirror","disk_count":2},"data_pools":[{"name":"tank0","topology":"stripe","disk_count":1}]}' \
    > "$GUIDED_STATE_FILE"
  history_new "$(<"$GUIDED_STATE_FILE")" > "$GUIDED_HIST_FILE"
  set_navigation "$(navigation_to_pool_edit Disks 0 data)"
  run guided_controller_key ctrl-r
  [ "$output" = "render" ]
  [ "$(jq -c '. == {}' "$GUIDED_STATE_FILE")" = "true" ]
  [ "$(navigation_screen "$(<"$GUIDED_NAV_FILE")")" = "category" ]
  run guided_controller_list
  ! echo "$output" | grep -q '?'
}

@test "key ctrl-r: from the custom (datapools) editor backs out to the category" {
  export GUIDED_HIST_FILE="$TEST_DIR/hist"
  printf '%s\n' \
    '{"mode":"multi","os_pool":{"pool_name":"rpool","topology":"none","disk_count":1}}' \
    > "$GUIDED_STATE_FILE"
  history_new "$(<"$GUIDED_STATE_FILE")" > "$GUIDED_HIST_FILE"
  set_navigation "$(navigation_to_data_pools Disks)"
  run guided_controller_key ctrl-r
  [ "$(jq -c '. == {}' "$GUIDED_STATE_FILE")" = "true" ]
  [ "$(navigation_screen "$(<"$GUIDED_NAV_FILE")")" = "category" ]
}

@test "key ctrl-z: a still-multi layout keeps you in the datapools editor" {
  export GUIDED_HIST_FILE="$TEST_DIR/hist"
  local base='{"mode":"multi","os_pool":{"pool_name":"rpool","topology":"none","disk_count":1}}'
  printf '%s\n' "$base" > "$GUIDED_STATE_FILE"
  history_new "$base" > "$GUIDED_HIST_FILE"
  printf '%s\n' "$(_controller_add_data_pool "$base")" > "$GUIDED_STATE_FILE"
  guided_controller_list >/dev/null          # autocommit the added pool
  set_navigation "$(navigation_to_data_pools Disks)"
  run guided_controller_key ctrl-z           # undo the add; layout is still multi
  [ "$(navigation_screen "$(<"$GUIDED_NAV_FILE")")" = "datapools" ]
}

@test "key ctrl-z: undoing a pool's creation exits its now-dangling editor" {
  export GUIDED_HIST_FILE="$TEST_DIR/hist"
  history_new '{}' > "$GUIDED_HIST_FILE"
  printf '%s\n' \
    '{"mode":"multi","data_pools":[{"name":"tank0","topology":"stripe","disk_count":1}]}' \
    > "$GUIDED_STATE_FILE"
  guided_controller_list >/dev/null          # autocommit the creation
  set_navigation "$(navigation_to_pool_edit Disks 0 data)"
  run guided_controller_key ctrl-z
  [ "$(navigation_screen "$(<"$GUIDED_NAV_FILE")")" = "category" ]
}

@test "key ctrl-z: a still-valid pool keeps you in its editor" {
  export GUIDED_HIST_FILE="$TEST_DIR/hist"
  local base='{"mode":"multi","data_pools":[{"name":"tank0","topology":"stripe","disk_count":1}]}'
  printf '%s\n' "$base" > "$GUIDED_STATE_FILE"
  history_new "$base" > "$GUIDED_HIST_FILE"
  printf '%s\n' "$(jq -c '.data_pools[0].disk_count=2' <<<"$base")" > "$GUIDED_STATE_FILE"
  guided_controller_list >/dev/null          # autocommit the count change
  set_navigation "$(navigation_to_pool_edit Disks 0 data)"
  run guided_controller_key ctrl-z           # undo the change; the pool still exists
  [ "$(navigation_screen "$(<"$GUIDED_NAV_FILE")")" = "pooledit" ]
}

@test "key: a no-op without a history file" {
  unset GUIDED_HIST_FILE
  run guided_controller_key ctrl-z
  [ "$output" = "noop" ]
}

@test "enter(category): Disk layout opens the native preset picker" {
  set_navigation "$(navigation_to_category Disks)"
  run guided_controller_enter "Layout: single"
  [ "$output" = "render" ]
  [ "$(navigation_screen "$(<"$GUIDED_NAV_FILE")")" = "values" ]
  [ "$(navigation_get "$(<"$GUIDED_NAV_FILE")" field)" = "__layout__" ]
}

@test "enter(category): Back returns to the top screen" {
  set_navigation "$(navigation_to_category Disks)"
  run guided_controller_enter "← Back"
  [ "$output" = "render" ]
  [ "$(navigation_screen "$(<"$GUIDED_NAV_FILE")")" = "top" ]
}


# ── values screen ────────────────────────────────────────────────────────────

@test "list(values): the enum options + Back" {
  set_navigation "$(navigation_to_values Bootloader options.bootloader bootloader)"
  run guided_controller_list
  echo "$output" | grep -q "systemd-boot"
  echo "$output" | grep -q "Grub"
  echo "$output" | grep -q "← Back"
}

# Regression: environment.display_manager is a single-select enum, so its picker
# must offer Auto/greetd/SDDM — not the true/false bool default (ADR 0069).
@test "list(values): display_manager picker offers auto/greetd/sddm, not bools" {
  set_navigation \
    "$(navigation_to_values Environment environment.display_manager 'display manager')"
  run guided_controller_list
  echo "$output" | grep -q "Auto"
  echo "$output" | grep -q "greetd"
  echo "$output" | grep -q "SDDM"
  ! echo "$output" | grep -qx "true"
  ! echo "$output" | grep -qx "false"
}

# fzf returns the Display Label "SDDM"; the enter handler reverse-maps it to the
# stored value "sddm" and commits it as a scalar (not a bool).
@test "enter(values): picking SDDM commits environment.display_manager=sddm" {
  set_navigation \
    "$(navigation_to_values Environment environment.display_manager 'display manager')"
  run guided_controller_enter "SDDM"
  [ "$(jq -r '.environment.display_manager' "$GUIDED_STATE_FILE")" = "sddm" ]
}

@test "enter(values): picking a bool commits it and returns to the category" {
  set_navigation "$(navigation_to_values Disks options.encryption encryption)"
  run guided_controller_enter "true"
  [ "$output" = "render" ]
  [ "$(jq -c '.options.encryption' "$GUIDED_STATE_FILE")" = "true" ]
  [ "$(navigation_screen "$(<"$GUIDED_NAV_FILE")")" = "category" ]
  [ "$(navigation_get "$(<"$GUIDED_NAV_FILE")" category)" = "Disks" ]
}

@test "enter(values): zfs commits the filesystem" {
  set_navigation "$(navigation_to_values Disks filesystem filesystem)"
  run guided_controller_enter "zfs"
  [ "$(jq -r '.filesystem' "$GUIDED_STATE_FILE")" = "zfs" ]
}


# ── issue 09: filesystem axis in the Guided Installer ─────────────────────────
# The root-fs picker offers only filesystems whose adapter is BUILT (all four
# now: zfs/btrfs/ext4/xfs). No "(reserved)" placeholder — each is selectable.
@test "list(values): filesystem picker offers the built adapters, none reserved" {
  set_navigation "$(navigation_to_values Disks filesystem filesystem)"
  run guided_controller_list
  local filesystem
  for filesystem in ZFS Btrfs Ext4 Xfs; do
    echo "$output" | grep -qx "$filesystem" || { echo "missing built fs: $filesystem"; false; }
  done
  ! echo "$output" | grep -qi reserved
}

@test "enter(values): a built non-zfs filesystem (btrfs) commits" {
  set_navigation "$(navigation_to_values Disks filesystem filesystem)"
  run guided_controller_enter "btrfs"
  [ "$output" = "render" ]
  [ "$(jq -r '.filesystem' "$GUIDED_STATE_FILE")" = "btrfs" ]
}

@test "enter(values): an unbuilt filesystem is a no-op (defensive)" {
  set_navigation "$(navigation_to_values Disks filesystem filesystem)"
  run guided_controller_enter "bcachefs"
  [ "$output" = "render" ]
  [ "$(jq -c '.filesystem // "unset"' "$GUIDED_STATE_FILE")" = '"unset"' ]
}

@test "enter(values): Back leaves the value unchanged" {
  set_navigation "$(navigation_to_values Disks options.encryption encryption)"
  run guided_controller_enter "← Back"
  [ "$output" = "render" ]
  [ "$(jq -c '. == {}' "$GUIDED_STATE_FILE")" = "true" ]
}


# ── strict-delta ●: re-picking the seeded default drops the override ──────────

@test "enter(values): re-picking the default filesystem (zfs) leaves no override" {
  _seed_baseline
  set_navigation "$(navigation_to_values Disks filesystem filesystem)"
  run guided_controller_enter "zfs"
  [ "$status" -eq 0 ]
  # zfs == the seeded default → normalised away → no override key, no ●
  [ "$(jq -c 'has("filesystem")' "$GUIDED_STATE_FILE")" = "false" ]
  ! config_state_is_overridden "$(<"$GUIDED_STATE_FILE")" filesystem
}

@test "enter(values): a non-default filesystem (btrfs) keeps the override" {
  _seed_baseline
  set_navigation "$(navigation_to_values Disks filesystem filesystem)"
  run guided_controller_enter "btrfs"
  [ "$(jq -r '.filesystem' "$GUIDED_STATE_FILE")" = "btrfs" ]
  config_state_is_overridden "$(<"$GUIDED_STATE_FILE")" filesystem
}

@test "enter(values): a bool toggled on then back to its default drops the ●" {
  _seed_baseline
  set_navigation "$(navigation_to_values Disks options.encryption encryption)"
  guided_controller_enter "true"  >/dev/null   # away from default false → override kept
  config_state_is_overridden "$(<"$GUIDED_STATE_FILE")" options.encryption
  set_navigation "$(navigation_to_values Disks options.encryption encryption)"
  guided_controller_enter "false" >/dev/null   # back to default false → normalised away
  [ "$(jq -c 'getpath(["options","encryption"]) == null' \
      "$GUIDED_STATE_FILE")" = "true" ]
  ! config_state_is_overridden "$(<"$GUIDED_STATE_FILE")" options.encryption
}


# ── disk-layout preset picker (native — no terminal drop, no disk-count) ──────

@test "list(values __layout__): lists the disk-layout presets + Back" {
  set_navigation "$(navigation_to_values Disks __layout__ "layout")"
  run guided_controller_list
  echo "$output" | grep -q "single"
  echo "$output" | grep -q "os-mirror"
  echo "$output" | grep -q "data-pools"
  echo "$output" | grep -q "← Back"
}

@test "enter(values __layout__): picking a multi preset opens the editor" {
  set_navigation "$(navigation_to_values Disks __layout__ "layout")"
  run guided_controller_enter "os-mirror"
  [ "$output" = "render" ]
  [ "$(jq -c '. != {}' "$GUIDED_STATE_FILE")" = "true" ]   # a skeleton landed
  # ADR 0047: a multi preset now drops into the unified editor, not back-out.
  [ "$(navigation_screen "$(<"$GUIDED_NAV_FILE")")" = "datapools" ]
}


# ── disk-layout graph preview ────────────────────────────────────────────────

@test "layout graph: single shows one OS pool" {
  run _controller_layout_graph "$(skeleton_preset single)"
  echo "$output" | grep -q "rpool"
  echo "$output" | grep -qi "single"
}

@test "layout graph: os-mirror-raidz1 shows OS mirror + data raidz1" {
  run _controller_layout_graph "$(skeleton_preset os-mirror-raidz1)"
  echo "$output" | grep -q "mirror · 2 disk"
  echo "$output" | grep -q "raidz1 · 3 disk"
}

@test "preview: category shows the always-on detail pane; layout graphs" {
  # ADR 0071: the category screen now renders the master-detail pane (parent
  # column of its fields), while the __layout__ values screen keeps its graph.
  set_navigation "$(navigation_to_category Disks)"
  run guided_controller_preview "Filesystem: zfs"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "filesystem"              # its field column
  set_navigation "$(navigation_to_values Disks __layout__ "layout")"
  run guided_controller_preview "os-mirror"
  echo "$output" | grep -q "mirror"
}

@test "preview(__layout__): a non-preset row graphs the LIVE edited state" {
  printf '%s\n' \
    '{"mode":"multi","os_pool":{"topology":"none","disk_count":1},"data_pools":[{"name":"tank0","topology":"raidz2","disk_count":6}]}' \
    > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_values Disks __layout__ "layout")"
  run guided_controller_preview "data-pools"          # not a preset → live state
  echo "$output" | grep -q "tank0"
  echo "$output" | grep -q "raidz2 · 6 disk"
}

@test "directive→action(render): layout + category show the pane, plain values hide it" {
  set_navigation "$(navigation_to_values Disks __layout__ "layout")"
  run _controller_directive_to_action render /x/entry.sh
  echo "$output" | grep -q "change-preview(bash /x/entry.sh preview {})"
  echo "$output" | grep -q "change-preview-window(right,45%)"
  # ADR 0071: the category screen now shows the always-on detail pane too.
  set_navigation "$(navigation_to_category Disks)"
  run _controller_directive_to_action render /x/entry.sh
  echo "$output" | grep -q "change-preview-window(right,45%)"
  # every field screen is populated now — even a plain enum values screen.
  set_navigation "$(navigation_to_values Kernels options.kernel kernel)"
  run _controller_directive_to_action render /x/entry.sh
  echo "$output" | grep -q "change-preview-window(right,45%)"
}


# ── data-pools editor: the live layout-graph preview tracks pool/disk edits ──

@test "preview(pooledit): graphs the LIVE state, reflecting the disk count" {
  printf '%s\n' \
    '{"mode":"multi","os_pool":{"topology":"none","disk_count":1},"data_pools":[{"name":"tank0","topology":"raidz1","disk_count":3}]}' \
    > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_pool_edit Disks 0)"
  run guided_controller_preview "disks: 3   (Enter cycles 1-8)"
  echo "$output" | grep -q "tank0"
  echo "$output" | grep -q "raidz1 · 3 disk"
}

@test "preview(datapools): graphs the LIVE state with every pool" {
  printf '%s\n' \
    '{"mode":"multi","os_pool":{"topology":"none","disk_count":1},"data_pools":[{"name":"tank0","topology":"mirror","disk_count":2},{"name":"tank1","topology":"stripe","disk_count":4}]}' \
    > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_data_pools Disks)"
  run guided_controller_preview "+ Add data pool"
  echo "$output" | grep -q "tank0"
  echo "$output" | grep -q "tank1"
  echo "$output" | grep -q "4 disk"
}

@test "directive→action(render): the data-pool editor shows the preview pane" {
  set_navigation "$(navigation_to_pool_edit Disks 0)"
  run _controller_directive_to_action render /x/entry.sh
  echo "$output" | grep -q "change-preview(bash /x/entry.sh preview {})"
  echo "$output" | grep -q "change-preview-window(right,45%)"
  set_navigation "$(navigation_to_data_pools Disks)"
  run _controller_directive_to_action render /x/entry.sh
  echo "$output" | grep -q "change-preview-window(right,45%)"
}
