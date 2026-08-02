#!/usr/bin/env bats
# Tests for .os/lib/guided-controller.sh — the persistent-fzf controller (ADR
# 0042). The controller is driven entirely through its state files (no fzf, no
# tty), so behaviour is asserted through the public interface: the rendered list
# for a screen, and the (directive + file mutation) of an enter/back. This is
# the slice-01 scope — nav + enum native, text/multi → edit-oneshot.

setup() {
  TEST_DIR="$(mktemp -d)"
  export GUIDED_STATE_FILE="$TEST_DIR/state.json"
  export GUIDED_NAV_FILE="$TEST_DIR/nav.json"
  export GUIDED_BASELINE_FILE="$TEST_DIR/base.json"
  # Hermetic hosts/ root: no installable profiles here, so the top-screen
  # Profiles row (ADR 0055) stays hidden unless a test wires its own tree.
  export OS_DIR="$TEST_DIR"

  source "$BATS_TEST_DIRNAME/../../lib/config/state.sh"
  source "$BATS_TEST_DIRNAME/../../lib/config/nav.sh"
  source "$BATS_TEST_DIRNAME/../../lib/config/edits.sh"
  source "$BATS_TEST_DIRNAME/../../lib/config/menu.sh"
  source "$BATS_TEST_DIRNAME/../../lib/guided-controller.sh"

  printf '%s\n' '{}' > "$GUIDED_STATE_FILE"
  printf '%s\n' '{}' > "$GUIDED_BASELINE_FILE"
  printf '%s\n' '{"screen":"top"}' > "$GUIDED_NAV_FILE"
}
teardown() { rm -rf "$TEST_DIR"; }

set_nav() { printf '%s\n' "$1" > "$GUIDED_NAV_FILE"; }

# ── top screen ───────────────────────────────────────────────────────────────

@test "list(top): the 8 categories, a divider, and the terminal rows" {
  run guided_ctl_list
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Host — "
  echo "$output" | grep -q "Users — "
  echo "$output" | grep -q "Proceed ▸"
  echo "$output" | grep -q "Save profile ▸"
  echo "$output" | grep -q "Export config ▸"
  echo "$output" | grep -q "──────"
}

@test "enter(top): a category drills in (render + nav)" {
  run guided_ctl_enter "Disks — layout, data pools, filesystem, encryption, swap"
  [ "$output" = "render" ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "category" ]
  [ "$(nav_get "$(<"$GUIDED_NAV_FILE")" category)" = "Disks" ]
}

@test "enter(top): Proceed / Save / Export emit terminal directives" {
  [ "$(guided_ctl_enter "Proceed ▸ review & install")" = "terminal proceed" ]
  set_nav '{"screen":"top"}'
  [ "$(guided_ctl_enter "Save profile ▸ x")" = "terminal save" ]
  set_nav '{"screen":"top"}'
  [ "$(guided_ctl_enter "Export config ▸ x")" = "terminal export" ]
}

@test "enter(top): the divider is inert (noop)" {
  run guided_ctl_enter "──────────────────────────"
  [ "$output" = "noop" ]
}

# ── category screen ──────────────────────────────────────────────────────────

@test "list(category Disks): field rows + Disk layout action + Back" {
  set_nav "$(nav_to_category Disks)"
  run guided_ctl_list
  echo "$output" | grep -q "Filesystem: ZFS"
  echo "$output" | grep -qx "Encryption ▸ off"   # collapsed row (ADR 0059)
  echo "$output" | grep -q "Layout: single"   # reflects the default
  echo "$output" | grep -q "← Back"
}

@test "list(category Disks): the Disk layout row reflects the chosen preset" {
  printf '%s\n' "$(nav_to_values Disks __layout__ "layout")" \
    > "$GUIDED_NAV_FILE"
  guided_ctl_enter "os-mirror" >/dev/null    # apply the preset
  set_nav "$(nav_to_category Disks)"
  run guided_ctl_list
  echo "$output" | grep -q "Layout: OS: 2 disks (mirror)"
  echo "$output" | grep -q "●"               # overridden marker
}

@test "enter(category): an enum field opens the value picker" {
  set_nav "$(nav_to_category Disks)"
  run guided_ctl_enter "Filesystem: ZFS"
  [ "$output" = "render" ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "values" ]
  [ "$(nav_get "$(<"$GUIDED_NAV_FILE")" field)" = "filesystem" ]
}

@test "enter(category): a text field opens the native query-line editor" {
  set_nav "$(nav_to_category Host)"
  run guided_ctl_enter "Hostname: "
  [ "$output" = "render" ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "text" ]
  [ "$(nav_get "$(<"$GUIDED_NAV_FILE")" field)" = "system.hostname" ]
}

@test "enter(category): a toggle field opens the multi-select picker" {
  set_nav "$(nav_to_category Options)"
  run guided_ctl_enter "Kernel: LTS"
  [ "$output" = "render" ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "values" ]
  [ "$(nav_get "$(<"$GUIDED_NAV_FILE")" field)" = "options.kernel" ]
}

@test "list(category Packages): empty list fields render as [] not blank" {
  set_nav "$(nav_to_category Packages)"
  run guided_ctl_list
  echo "$output" | grep -q "Extra packages: \[\]"
  echo "$output" | grep -q "System programs: \[\]"
}

@test "list(category): an empty VALUE keeps its column (no dot-shift)" {
  # regression: a tab-IFS read collapses an empty value field and shifts the
  # overridden flag into it — an empty hostname must render "Hostname: " not
  # "Hostname: false"/"…True".
  set_nav "$(nav_to_category Host)"
  run guided_ctl_list
  echo "$output" | grep -qE '^Hostname: *$'
  ! echo "$output" | grep -qiE '^Hostname: (true|false)'
}

@test "list(text esp size): current shows the default 2G, not (unset)" {
  set_nav "$(nav_to_text Disks options.esp_size "esp size")"
  run guided_ctl_list
  echo "$output" | grep -q "current: 2G"
}

# ── multi-select toggle screens (native — never leaves fzf) ──────────────────

@test "list(values toggle): options are marked [x]/[ ] by selection" {
  printf '%s\n' '{"options":{"kernel":["lts"]}}' > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_values Options options.kernel kernel)"
  run guided_ctl_list
  echo "$output" | grep -q "\[x\] LTS"
  echo "$output" | grep -q "\[ \] Zen"
}

@test "enter(values toggle): toggling on adds the option and STAYS on the screen" {
  set_nav "$(nav_to_values Options options.kernel kernel)"
  run guided_ctl_enter "[ ] lts"
  [ "$output" = "refresh" ]   # reload-sync in place (no flicker, query kept)
  [ "$(jq -c '.options.kernel' "$GUIDED_STATE_FILE")" = '["lts"]' ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "values" ]
}

@test "directive→action: refresh re-lists in place via reload-sync" {
  run _guided_directive_to_action refresh /x/entry.sh
  [ "$output" = "reload-sync(bash /x/entry.sh list)+refresh-preview" ]
}

@test "enter(values toggle): toggling an already-selected option removes it" {
  printf '%s\n' '{"options":{"kernel":["lts","zen"]}}' > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_values Options options.kernel kernel)"
  run guided_ctl_enter "[x] zen"
  [ "$(jq -c '.options.kernel' "$GUIDED_STATE_FILE")" = '["lts"]' ]
}

@test "enter(values toggle): the last option toggled off unsets the override" {
  printf '%s\n' '{"options":{"kernel":["lts"]}}' > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_values Options options.kernel kernel)"
  run guided_ctl_enter "[x] lts"
  [ "$(jq -c '. == {}' "$GUIDED_STATE_FILE")" = "true" ]
}

@test "enter(values toggle gpu): auto is mutually exclusive → scalar auto" {
  printf '%s\n' '{"environment":{"gpu":["amd"]}}' > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_values Environment environment.gpu gpu)"
  run guided_ctl_enter "[ ] auto"
  [ "$(jq -r '.environment.gpu' "$GUIDED_STATE_FILE")" = "auto" ]
}

@test "enter(values toggle gpu): picking a vendor clears auto" {
  printf '%s\n' '{"environment":{"gpu":"auto"}}' > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_values Environment environment.gpu gpu)"
  run guided_ctl_enter "[ ] nvidia"
  [ "$(jq -c '.environment.gpu' "$GUIDED_STATE_FILE")" = '["nvidia"]' ]
}

@test "enter(values toggle gpu): AMD + NVIDIA select together (hybrid Legion)" {
  # the Legion 5 hybrid case, driven through the DISPLAYED labels (AMD/NVIDIA),
  # so it also exercises the Display Label reverse lookup for gpu.
  printf '%s\n' '{"environment":{"gpu":"auto"}}' > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_values Environment environment.gpu gpu)"
  guided_ctl_enter "[ ] AMD" >/dev/null       # clears auto, adds amd
  [ "$(jq -c '.environment.gpu' "$GUIDED_STATE_FILE")" = '["amd"]' ]
  guided_ctl_enter "[ ] NVIDIA" >/dev/null    # adds the second vendor
  [ "$(jq -c '.environment.gpu' "$GUIDED_STATE_FILE")" = '["amd","nvidia"]' ]
}

# ── undo / redo / reset (slice 03) ───────────────────────────────────────────

@test "autocommit: guided_ctl_list snapshots a changed state for undo" {
  export GUIDED_HIST_FILE="$TEST_DIR/hist"
  hist_new '{}' > "$GUIDED_HIST_FILE"
  printf '%s\n' '{"options":{"encryption":true}}' > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_category Disks)"
  guided_ctl_list >/dev/null     # the single choke point commits the change
  [ "$(hist_present "$(<"$GUIDED_HIST_FILE")" | jq -c '.options.encryption')" \
    = "true" ]
}

@test "key ctrl-z: undoes the last edit, restoring the prior state" {
  export GUIDED_HIST_FILE="$TEST_DIR/hist"
  hist_new '{}' > "$GUIDED_HIST_FILE"
  printf '%s\n' '{"options":{"encryption":true}}' > "$GUIDED_STATE_FILE"
  guided_ctl_list >/dev/null     # autocommit the change
  run guided_ctl_key ctrl-z
  [ "$output" = "render" ]
  [ "$(jq -c '. == {}' "$GUIDED_STATE_FILE")" = "true" ]
}

@test "key ctrl-y: redoes an undone edit" {
  export GUIDED_HIST_FILE="$TEST_DIR/hist"
  hist_new '{}' > "$GUIDED_HIST_FILE"
  printf '%s\n' '{"a":1}' > "$GUIDED_STATE_FILE"
  guided_ctl_list >/dev/null
  guided_ctl_key ctrl-z >/dev/null
  run guided_ctl_key ctrl-y
  [ "$output" = "render" ]
  [ "$(jq -c '.a' "$GUIDED_STATE_FILE")" = "1" ]
}

@test "key ctrl-r: resets every override, and is itself undoable" {
  export GUIDED_HIST_FILE="$TEST_DIR/hist"
  printf '%s\n' '{"a":1}' > "$GUIDED_STATE_FILE"
  hist_new '{"a":1}' > "$GUIDED_HIST_FILE"
  run guided_ctl_key ctrl-r
  [ "$output" = "render" ]
  [ "$(jq -c '. == {}' "$GUIDED_STATE_FILE")" = "true" ]
  guided_ctl_key ctrl-z >/dev/null              # undo the reset
  [ "$(jq -c '.a' "$GUIDED_STATE_FILE")" = "1" ]
}

@test "key ctrl-r: from inside a pool editor backs out to the category (no ?)" {
  export GUIDED_HIST_FILE="$TEST_DIR/hist"
  printf '%s\n' \
    '{"mode":"multi","os_pool":{"pool_name":"rpool","topology":"mirror","disk_count":2},"data_pools":[{"name":"tank0","topology":"stripe","disk_count":1}]}' \
    > "$GUIDED_STATE_FILE"
  hist_new "$(<"$GUIDED_STATE_FILE")" > "$GUIDED_HIST_FILE"
  set_nav "$(nav_to_pooledit Disks 0 data)"
  run guided_ctl_key ctrl-r
  [ "$output" = "render" ]
  [ "$(jq -c '. == {}' "$GUIDED_STATE_FILE")" = "true" ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "category" ]
  run guided_ctl_list
  ! echo "$output" | grep -q '?'
}

@test "key ctrl-r: from the custom (datapools) editor backs out to the category" {
  export GUIDED_HIST_FILE="$TEST_DIR/hist"
  printf '%s\n' \
    '{"mode":"multi","os_pool":{"pool_name":"rpool","topology":"none","disk_count":1}}' \
    > "$GUIDED_STATE_FILE"
  hist_new "$(<"$GUIDED_STATE_FILE")" > "$GUIDED_HIST_FILE"
  set_nav "$(nav_to_datapools Disks)"
  run guided_ctl_key ctrl-r
  [ "$(jq -c '. == {}' "$GUIDED_STATE_FILE")" = "true" ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "category" ]
}

@test "key ctrl-z: a still-multi layout keeps you in the datapools editor" {
  export GUIDED_HIST_FILE="$TEST_DIR/hist"
  local base='{"mode":"multi","os_pool":{"pool_name":"rpool","topology":"none","disk_count":1}}'
  printf '%s\n' "$base" > "$GUIDED_STATE_FILE"
  hist_new "$base" > "$GUIDED_HIST_FILE"
  printf '%s\n' "$(_ctl_add_data_pool "$base")" > "$GUIDED_STATE_FILE"
  guided_ctl_list >/dev/null          # autocommit the added pool
  set_nav "$(nav_to_datapools Disks)"
  run guided_ctl_key ctrl-z           # undo the add; layout is still multi
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "datapools" ]
}

@test "key ctrl-z: undoing a pool's creation exits its now-dangling editor" {
  export GUIDED_HIST_FILE="$TEST_DIR/hist"
  hist_new '{}' > "$GUIDED_HIST_FILE"
  printf '%s\n' \
    '{"mode":"multi","data_pools":[{"name":"tank0","topology":"stripe","disk_count":1}]}' \
    > "$GUIDED_STATE_FILE"
  guided_ctl_list >/dev/null          # autocommit the creation
  set_nav "$(nav_to_pooledit Disks 0 data)"
  run guided_ctl_key ctrl-z
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "category" ]
}

@test "key ctrl-z: a still-valid pool keeps you in its editor" {
  export GUIDED_HIST_FILE="$TEST_DIR/hist"
  local base='{"mode":"multi","data_pools":[{"name":"tank0","topology":"stripe","disk_count":1}]}'
  printf '%s\n' "$base" > "$GUIDED_STATE_FILE"
  hist_new "$base" > "$GUIDED_HIST_FILE"
  printf '%s\n' "$(jq -c '.data_pools[0].disk_count=2' <<<"$base")" > "$GUIDED_STATE_FILE"
  guided_ctl_list >/dev/null          # autocommit the count change
  set_nav "$(nav_to_pooledit Disks 0 data)"
  run guided_ctl_key ctrl-z           # undo the change; the pool still exists
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "pooledit" ]
}

@test "key: a no-op without a history file" {
  unset GUIDED_HIST_FILE
  run guided_ctl_key ctrl-z
  [ "$output" = "noop" ]
}

@test "enter(category): Disk layout opens the native preset picker" {
  set_nav "$(nav_to_category Disks)"
  run guided_ctl_enter "Layout: single"
  [ "$output" = "render" ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "values" ]
  [ "$(nav_get "$(<"$GUIDED_NAV_FILE")" field)" = "__layout__" ]
}

@test "enter(category): Back returns to the top screen" {
  set_nav "$(nav_to_category Disks)"
  run guided_ctl_enter "← Back"
  [ "$output" = "render" ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "top" ]
}

# ── values screen ────────────────────────────────────────────────────────────

@test "list(values): the enum options + Back" {
  set_nav "$(nav_to_values Options options.bootloader bootloader)"
  run guided_ctl_list
  echo "$output" | grep -q "systemd-boot"
  echo "$output" | grep -q "Grub"
  echo "$output" | grep -q "← Back"
}

@test "enter(values): picking a bool commits it and returns to the category" {
  set_nav "$(nav_to_values Disks options.encryption encryption)"
  run guided_ctl_enter "true"
  [ "$output" = "render" ]
  [ "$(jq -c '.options.encryption' "$GUIDED_STATE_FILE")" = "true" ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "category" ]
  [ "$(nav_get "$(<"$GUIDED_NAV_FILE")" category)" = "Disks" ]
}

@test "enter(values): zfs commits the filesystem" {
  set_nav "$(nav_to_values Disks filesystem filesystem)"
  run guided_ctl_enter "zfs"
  [ "$(jq -r '.filesystem' "$GUIDED_STATE_FILE")" = "zfs" ]
}

# ── issue 09: filesystem axis in the Guided Installer ─────────────────────────
# The root-fs picker offers only filesystems whose adapter is BUILT (all four
# now: zfs/btrfs/ext4/xfs). No "(reserved)" placeholder — each is selectable.
@test "list(values): filesystem picker offers the built adapters, none reserved" {
  set_nav "$(nav_to_values Disks filesystem filesystem)"
  run guided_ctl_list
  local fs
  for fs in ZFS Btrfs Ext4 Xfs; do
    echo "$output" | grep -qx "$fs" || { echo "missing built fs: $fs"; false; }
  done
  ! echo "$output" | grep -qi reserved
}

@test "enter(values): a built non-zfs filesystem (btrfs) commits" {
  set_nav "$(nav_to_values Disks filesystem filesystem)"
  run guided_ctl_enter "btrfs"
  [ "$output" = "render" ]
  [ "$(jq -r '.filesystem' "$GUIDED_STATE_FILE")" = "btrfs" ]
}

@test "enter(values): an unbuilt filesystem is a no-op (defensive)" {
  set_nav "$(nav_to_values Disks filesystem filesystem)"
  run guided_ctl_enter "bcachefs"
  [ "$output" = "render" ]
  [ "$(jq -c '.filesystem // "unset"' "$GUIDED_STATE_FILE")" = '"unset"' ]
}

@test "enter(values): Back leaves the value unchanged" {
  set_nav "$(nav_to_values Disks options.encryption encryption)"
  run guided_ctl_enter "← Back"
  [ "$output" = "render" ]
  [ "$(jq -c '. == {}' "$GUIDED_STATE_FILE")" = "true" ]
}

# ── strict-delta ●: re-picking the seeded default drops the override ──────────
# The baseline seeds every menu default (seed.sh); the apply-time normalise drops
# an override that lands back on that default, so ● (override-only) never lights
# for an unchanged value. Regression for the "select zfs → marked modified" bug.

_seed_baseline() {
  source "$BATS_TEST_DIRNAME/../../lib/config/seed.sh"
  cfgstate_seed_defaults "$(cfgstate_new)" > "$GUIDED_BASELINE_FILE"
}

@test "enter(values): re-picking the default filesystem (zfs) leaves no override" {
  _seed_baseline
  set_nav "$(nav_to_values Disks filesystem filesystem)"
  run guided_ctl_enter "zfs"
  [ "$status" -eq 0 ]
  # zfs == the seeded default → normalised away → no override key, no ●
  [ "$(jq -c 'has("filesystem")' "$GUIDED_STATE_FILE")" = "false" ]
  ! cfgstate_is_overridden "$(<"$GUIDED_STATE_FILE")" filesystem
}

@test "enter(values): a non-default filesystem (btrfs) keeps the override" {
  _seed_baseline
  set_nav "$(nav_to_values Disks filesystem filesystem)"
  run guided_ctl_enter "btrfs"
  [ "$(jq -r '.filesystem' "$GUIDED_STATE_FILE")" = "btrfs" ]
  cfgstate_is_overridden "$(<"$GUIDED_STATE_FILE")" filesystem
}

@test "enter(values): a bool toggled on then back to its default drops the ●" {
  _seed_baseline
  set_nav "$(nav_to_values Disks options.encryption encryption)"
  guided_ctl_enter "true"  >/dev/null   # away from default false → override kept
  cfgstate_is_overridden "$(<"$GUIDED_STATE_FILE")" options.encryption
  set_nav "$(nav_to_values Disks options.encryption encryption)"
  guided_ctl_enter "false" >/dev/null   # back to default false → normalised away
  [ "$(jq -c 'getpath(["options","encryption"]) == null' \
      "$GUIDED_STATE_FILE")" = "true" ]
  ! cfgstate_is_overridden "$(<"$GUIDED_STATE_FILE")" options.encryption
}

# ── disk-layout preset picker (native — no terminal drop, no disk-count) ──────

@test "list(values __layout__): lists the disk-layout presets + Back" {
  set_nav "$(nav_to_values Disks __layout__ "layout")"
  run guided_ctl_list
  echo "$output" | grep -q "single"
  echo "$output" | grep -q "os-mirror"
  echo "$output" | grep -q "data-pools"
  echo "$output" | grep -q "← Back"
}

@test "enter(values __layout__): picking a multi preset opens the editor" {
  set_nav "$(nav_to_values Disks __layout__ "layout")"
  run guided_ctl_enter "os-mirror"
  [ "$output" = "render" ]
  [ "$(jq -c '. != {}' "$GUIDED_STATE_FILE")" = "true" ]   # a skeleton landed
  # ADR 0047: a multi preset now drops into the unified editor, not back-out.
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "datapools" ]
}

# ── disk-layout graph preview ────────────────────────────────────────────────

@test "layout graph: single shows one OS pool" {
  run _ctl_layout_graph "$(skeleton_preset single)"
  echo "$output" | grep -q "rpool"
  echo "$output" | grep -qi "single"
}

@test "layout graph: os-mirror-raidz1 shows OS mirror + data raidz1" {
  run _ctl_layout_graph "$(skeleton_preset os-mirror-raidz1)"
  echo "$output" | grep -q "mirror · 2 disk"
  echo "$output" | grep -q "raidz1 · 3 disk"
}

@test "preview: renders only on the Disk-layout screen" {
  set_nav "$(nav_to_category Disks)"
  run guided_ctl_preview "os-mirror"
  [ -z "$output" ]                                   # off-screen → nothing
  set_nav "$(nav_to_values Disks __layout__ "layout")"
  run guided_ctl_preview "os-mirror"
  echo "$output" | grep -q "mirror"
}

@test "preview(__layout__): a non-preset row graphs the LIVE edited state" {
  printf '%s\n' \
    '{"mode":"multi","os_pool":{"topology":"none","disk_count":1},"data_pools":[{"name":"tank0","topology":"raidz2","disk_count":6}]}' \
    > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_values Disks __layout__ "layout")"
  run guided_ctl_preview "data-pools"          # not a preset → live state
  echo "$output" | grep -q "tank0"
  echo "$output" | grep -q "raidz2 · 6 disk"
}

@test "directive→action(render): layout shows the preview, others hide it" {
  set_nav "$(nav_to_values Disks __layout__ "layout")"
  run _guided_directive_to_action render /x/entry.sh
  echo "$output" | grep -q "change-preview(bash /x/entry.sh preview {})"
  echo "$output" | grep -q "change-preview-window(right,45%)"
  set_nav "$(nav_to_category Disks)"
  run _guided_directive_to_action render /x/entry.sh
  echo "$output" | grep -q "change-preview-window(hidden)"
}

# ── data-pools editor: the live layout-graph preview tracks pool/disk edits ──

@test "preview(pooledit): graphs the LIVE state, reflecting the disk count" {
  printf '%s\n' \
    '{"mode":"multi","os_pool":{"topology":"none","disk_count":1},"data_pools":[{"name":"tank0","topology":"raidz1","disk_count":3}]}' \
    > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_pooledit Disks 0)"
  run guided_ctl_preview "disks: 3   (Enter cycles 1-8)"
  echo "$output" | grep -q "tank0"
  echo "$output" | grep -q "raidz1 · 3 disk"
}

@test "preview(datapools): graphs the LIVE state with every pool" {
  printf '%s\n' \
    '{"mode":"multi","os_pool":{"topology":"none","disk_count":1},"data_pools":[{"name":"tank0","topology":"mirror","disk_count":2},{"name":"tank1","topology":"stripe","disk_count":4}]}' \
    > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_datapools Disks)"
  run guided_ctl_preview "+ Add data pool"
  echo "$output" | grep -q "tank0"
  echo "$output" | grep -q "tank1"
  echo "$output" | grep -q "4 disk"
}

@test "directive→action(render): the data-pool editor shows the preview pane" {
  set_nav "$(nav_to_pooledit Disks 0)"
  run _guided_directive_to_action render /x/entry.sh
  echo "$output" | grep -q "change-preview(bash /x/entry.sh preview {})"
  echo "$output" | grep -q "change-preview-window(right,45%)"
  set_nav "$(nav_to_datapools Disks)"
  run _guided_directive_to_action render /x/entry.sh
  echo "$output" | grep -q "change-preview-window(right,45%)"
}

# ── data-pools editor: multiple pools (tank0/tank1), topology, disk count ─────

@test "list(category Disks): no separate data pools row (it lives under layout)" {
  set_nav "$(nav_to_category Disks)"
  run guided_ctl_list
  ! echo "$output" | grep -q "data pools:"
}

@test "enter(values __layout__): data-pools opens the editor with a starter pool" {
  set_nav "$(nav_to_values Disks __layout__ "layout")"
  run guided_ctl_enter "data-pools"
  [ "$output" = "render" ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "datapools" ]
  [ "$(jq -r '.data_pools[0].name' "$GUIDED_STATE_FILE")" = "tank0" ]
  [ "$(jq -r '.mode' "$GUIDED_STATE_FILE")" = "multi" ]
}

@test "enter(values __layout__): re-entering data-pools adds no second pool" {
  printf '%s\n' '{"mode":"multi","os_pool":{"topology":"none","disk_count":1},"data_pools":[{"name":"tank0","topology":"mirror","disk_count":2}]}' \
    > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_values Disks __layout__ "layout")"
  run guided_ctl_enter "data-pools"
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "datapools" ]
  [ "$(jq '.data_pools | length' "$GUIDED_STATE_FILE")" = "1" ]
}

@test "enter(datapools): + Add appends tank0 (single-disk stripe ×1) and forces multi" {
  set_nav "$(nav_to_datapools Disks)"
  run guided_ctl_enter "+ Add data pool"
  [ "$output" = "refresh" ]
  [ "$(jq -r '.data_pools[0].name' "$GUIDED_STATE_FILE")" = "tank0" ]
  [ "$(jq -r '.data_pools[0].topology' "$GUIDED_STATE_FILE")" = "stripe" ]
  [ "$(jq -r '.data_pools[0].disk_count' "$GUIDED_STATE_FILE")" = "1" ]
  [ "$(jq -r '.mode' "$GUIDED_STATE_FILE")" = "multi" ]
  [ -n "$(jq -r '.os_pool.pool_name' "$GUIDED_STATE_FILE")" ]
}

@test "enter(datapools): a second Add auto-names it tank1" {
  printf '%s\n' \
    '{"data_pools":[{"name":"tank0","topology":"mirror","disk_count":2}]}' \
    > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_datapools Disks)"
  run guided_ctl_enter "+ Add data pool"
  [ "$(jq -r '.data_pools[1].name' "$GUIDED_STATE_FILE")" = "tank1" ]
}

@test "list(datapools): lists each pool as name: topology ×n" {
  printf '%s\n' \
    '{"data_pools":[{"name":"tank0","topology":"raidz1","disk_count":3}]}' \
    > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_datapools Disks)"
  run guided_ctl_list
  echo "$output" | grep -q "tank0: raidz1 ×3"
  echo "$output" | grep -q "+ Add data pool"
}

@test "enter(datapools): selecting a pool opens its editor by index" {
  printf '%s\n' '{"data_pools":[{"name":"tank0","topology":"mirror","disk_count":2},{"name":"tank1","topology":"stripe","disk_count":1}]}' \
    > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_datapools Disks)"
  run guided_ctl_enter "tank1: stripe ×1"
  [ "$output" = "render" ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "pooledit" ]
  [ "$(nav_get "$(<"$GUIDED_NAV_FILE")" index)" = "1" ]
}

@test "enter(pooledit): topology cycles off stripe, disks cycle, remove deletes" {
  printf '%s\n' \
    '{"data_pools":[{"name":"tank0","topology":"stripe","disk_count":2}]}' \
    > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_pooledit Disks 0)"
  run guided_ctl_enter "topology: stripe   (Enter cycles)"
  [ "$(jq -r '.data_pools[0].topology' "$GUIDED_STATE_FILE")" = "mirror" ]
  run guided_ctl_enter "disks: 2   (Enter cycles 1-8)"
  [ "$(jq -r '.data_pools[0].disk_count' "$GUIDED_STATE_FILE")" = "3" ]
  run guided_ctl_enter "✗ remove this pool"
  [ "$(jq -c '.data_pools' "$GUIDED_STATE_FILE")" = "[]" ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "datapools" ]
}

# issue 09: the topology cycle follows the pool's own filesystem — a btrfs group
# cycles single/raid0/raid1/raid10, never the zfs mirror/raidz set.
@test "enter(pooledit): a btrfs pool cycles the btrfs topology set" {
  printf '%s\n' \
    '{"data_pools":[{"name":"tank0","filesystem":"btrfs","topology":"single","disk_count":2}]}' \
    > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_pooledit Disks 0)"
  run guided_ctl_enter "topology: single   (Enter cycles)"
  [ "$(jq -r '.data_pools[0].topology' "$GUIDED_STATE_FILE")" = "raid0" ]
}

@test "enter(pooledit): an ext4 pool topology stays single (single-disk only)" {
  printf '%s\n' \
    '{"data_pools":[{"name":"tank0","filesystem":"ext4","topology":"single","disk_count":1}]}' \
    > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_pooledit Disks 0)"
  run guided_ctl_enter "topology: single   (Enter cycles)"
  [ "$(jq -r '.data_pools[0].topology' "$GUIDED_STATE_FILE")" = "single" ]
}

# issue 09: the pool editor authors a per-group filesystem + encryption.
@test "enter(pooledit): the filesystem row cycles the pool's filesystem" {
  printf '%s\n' \
    '{"data_pools":[{"name":"tank0","filesystem":"zfs","topology":"mirror","disk_count":2}]}' \
    > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_pooledit Disks 0)"
  run guided_ctl_enter "filesystem: zfs   (Enter cycles)"
  [ "$(jq -r '.data_pools[0].filesystem' "$GUIDED_STATE_FILE")" = "btrfs" ]
}

@test "enter(pooledit): cycling a group to ext4 pins it single-disk" {
  printf '%s\n' \
    '{"data_pools":[{"name":"tank0","filesystem":"btrfs","topology":"raid1","disk_count":2}]}' \
    > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_pooledit Disks 0)"
  run guided_ctl_enter "filesystem: btrfs   (Enter cycles)"
  [ "$(jq -r '.data_pools[0].filesystem' "$GUIDED_STATE_FILE")" = "ext4" ]
  [ "$(jq -r '.data_pools[0].topology' "$GUIDED_STATE_FILE")" = "single" ]
  [ "$(jq -r '.data_pools[0].disk_count' "$GUIDED_STATE_FILE")" = "1" ]
}

@test "enter(pooledit): the encryption row toggles the pool's encryption" {
  printf '%s\n' \
    '{"data_pools":[{"name":"tank0","filesystem":"zfs","topology":"mirror","disk_count":2}]}' \
    > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_pooledit Disks 0)"
  run guided_ctl_enter "encryption: false   (Enter toggles)"
  [ "$(jq -r '.data_pools[0].encryption' "$GUIDED_STATE_FILE")" = "true" ]
  run guided_ctl_enter "encryption: true   (Enter toggles)"
  [ "$(jq -r '.data_pools[0].encryption' "$GUIDED_STATE_FILE")" = "false" ]
}

@test "enter(pooledit): an ext4 pool's disk count stays pinned at 1" {
  printf '%s\n' \
    '{"data_pools":[{"name":"tank0","filesystem":"ext4","topology":"single","disk_count":1}]}' \
    > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_pooledit Disks 0)"
  run guided_ctl_enter "disks: 1   (Enter cycles 1-8)"
  [ "$(jq -r '.data_pools[0].disk_count' "$GUIDED_STATE_FILE")" = "1" ]
}

@test "list(pooledit): shows the filesystem and encryption rows" {
  printf '%s\n' \
    '{"data_pools":[{"name":"tank0","filesystem":"btrfs","topology":"raid1","disk_count":2,"encryption":true}]}' \
    > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_pooledit Disks 0)"
  run guided_ctl_list
  echo "$output" | grep -q "filesystem: btrfs"
  echo "$output" | grep -q "encryption: true"
}

# ── swap: one Disks row → swapedit sub-editor (enabled + free-text size) ──────

@test "list(category Disks): one swap row, no separate swap size row" {
  set_nav "$(nav_to_category Disks)"
  run guided_ctl_list
  [ "$(echo "$output" | grep -cE '^Swap:')" = "1" ]
  ! echo "$output" | grep -qE '^Swap size:'
}

@test "list(category Disks): swap row defaults to size + zswap, no dot" {
  set_nav "$(nav_to_category Disks)"
  run guided_ctl_list
  echo "$output" | grep -qE '^Swap: auto · zswap zstd$'   # default on + zswap
}

@test "enter(category): swap opens the swapedit sub-editor" {
  set_nav "$(nav_to_category Disks)"
  run guided_ctl_enter "Swap: auto"
  [ "$output" = "render" ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "swapedit" ]
}

@test "list(swapedit): default shows enabled on + size auto + Back" {
  set_nav "$(nav_to_swapedit Disks)"
  run guided_ctl_list
  echo "$output" | grep -qE '^enabled: on$'
  echo "$output" | grep -qE '^size: auto$'
  echo "$output" | grep -q "← Back"
}

@test "enter(swapedit): toggling enabled flips options.swap and STAYS (refresh)" {
  set_nav "$(nav_to_swapedit Disks)"
  run guided_ctl_enter "enabled: on"
  [ "$output" = "refresh" ]
  [ "$(jq -c '.options.swap' "$GUIDED_STATE_FILE")" = "false" ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "swapedit" ]
}

@test "enter(swapedit): an explicit swap:false toggles back to true (jq // guard)" {
  printf '%s\n' '{"options":{"swap":false}}' > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_swapedit Disks)"
  run guided_ctl_enter "enabled: off"
  [ "$(jq -c '.options.swap' "$GUIDED_STATE_FILE")" = "true" ]
}

@test "list(swapedit): swap off hides the size row" {
  printf '%s\n' '{"options":{"swap":false}}' > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_swapedit Disks)"
  run guided_ctl_list
  echo "$output" | grep -qE '^enabled: off$'
  ! echo "$output" | grep -qE '^size:'
}

@test "enter(swapedit): size opens the text editor; saving returns to swapedit" {
  set_nav "$(nav_to_swapedit Disks)"
  run guided_ctl_enter "size: auto"
  [ "$output" = "render" ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "text" ]
  [ "$(nav_get "$(<"$GUIDED_NAV_FILE")" field)" = "options.swap_size" ]
  run guided_ctl_enter "" "8G"                 # text screen: query is the value
  [ "$(jq -r '.options.swap_size' "$GUIDED_STATE_FILE")" = "8G" ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "swapedit" ]
}

@test "enter(swapedit): Back returns to the Disks category" {
  set_nav "$(nav_to_swapedit Disks)"
  run guided_ctl_enter "← Back"
  [ "$output" = "render" ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "category" ]
}

@test "swap label: off / size · zswap <comp> / size · no zswap" {
  run _ctl_swap_label '{"options":{"swap":false}}'
  [ "$output" = "off" ]
  run _ctl_swap_label '{"options":{"swap_size":"8G"}}'        # zswap default on
  [ "$output" = "8G · zswap zstd" ]
  run _ctl_swap_label '{}'
  [ "$output" = "auto · zswap zstd" ]
  run _ctl_swap_label '{"options":{"zswap":{"enabled":false}}}'
  [ "$output" = "auto · no zswap" ]
  run _ctl_swap_label '{"options":{"zswap":{"compressor":"lz4"}}}'
  [ "$output" = "auto · zswap lz4" ]
}

@test "encryption label: off / on · <tag> (ADR 0059)" {
  run _ctl_encryption_label '{"options":{"encryption":false}}' "default 12345678"
  [ "$output" = "off" ]
  run _ctl_encryption_label '{}' "default 12345678"        # default off
  [ "$output" = "off" ]
  run _ctl_encryption_label '{"options":{"encryption":true}}' "default 12345678"
  [ "$output" = "on · default 12345678" ]
  run _ctl_encryption_label '{"options":{"encryption":true}}' "custom"
  [ "$output" = "on · custom" ]
  run _ctl_encryption_label '{"options":{"encryption":true}}' "from age"
  [ "$output" = "on · from age" ]
}

@test "list(category Disks): swap row shows a dot once overridden" {
  printf '%s\n' '{"options":{"swap":false}}' > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_category Disks)"
  run guided_ctl_list
  echo "$output" | grep -qE '^Swap: off  ●$'
}

# ── swapedit: zswap toggle + compressor / max-pool-% cycles (default on) ──────

@test "list(swapedit): default shows the zswap rows (on, zstd, 20)" {
  set_nav "$(nav_to_swapedit Disks)"
  run guided_ctl_list
  echo "$output" | grep -qE '^zswap: on$'
  echo "$output" | grep -qE '^compressor: zstd'
  echo "$output" | grep -qE '^max pool %: 20'
}

@test "list(swapedit): zswap off hides compressor + max pool %" {
  printf '%s\n' '{"options":{"zswap":{"enabled":false}}}' > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_swapedit Disks)"
  run guided_ctl_list
  echo "$output" | grep -qE '^zswap: off$'
  ! echo "$output" | grep -qE '^compressor:'
  ! echo "$output" | grep -qE '^max pool %:'
}

@test "list(swapedit): swap off hides every zswap row" {
  printf '%s\n' '{"options":{"swap":false}}' > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_swapedit Disks)"
  run guided_ctl_list
  ! echo "$output" | grep -qE '^zswap:'
  ! echo "$output" | grep -qE '^compressor:'
}

@test "enter(swapedit): toggling zswap flips options.zswap.enabled (refresh)" {
  set_nav "$(nav_to_swapedit Disks)"
  run guided_ctl_enter "zswap: on"
  [ "$output" = "refresh" ]
  [ "$(jq -c '.options.zswap.enabled' "$GUIDED_STATE_FILE")" = "false" ]
}

@test "enter(swapedit): an explicit zswap:false toggles back to true (jq guard)" {
  printf '%s\n' '{"options":{"zswap":{"enabled":false}}}' > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_swapedit Disks)"
  run guided_ctl_enter "zswap: off"
  [ "$(jq -c '.options.zswap.enabled' "$GUIDED_STATE_FILE")" = "true" ]
}

@test "enter(swapedit): compressor cycles zstd → lz4 → lzo → zstd" {
  set_nav "$(nav_to_swapedit Disks)"
  run guided_ctl_enter "compressor: zstd   (Enter cycles)"
  [ "$(jq -r '.options.zswap.compressor' "$GUIDED_STATE_FILE")" = "lz4" ]
  run guided_ctl_enter "compressor: lz4   (Enter cycles)"
  [ "$(jq -r '.options.zswap.compressor' "$GUIDED_STATE_FILE")" = "lzo" ]
  run guided_ctl_enter "compressor: lzo   (Enter cycles)"
  [ "$(jq -r '.options.zswap.compressor' "$GUIDED_STATE_FILE")" = "zstd" ]
}

@test "enter(swapedit): max pool % cycles 20 → 40 → 60 → 5" {
  set_nav "$(nav_to_swapedit Disks)"
  run guided_ctl_enter "max pool %: 20   (Enter cycles)"
  [ "$(jq -r '.options.zswap.max_pool_percent' "$GUIDED_STATE_FILE")" = "40" ]
  run guided_ctl_enter "max pool %: 40   (Enter cycles)"
  [ "$(jq -r '.options.zswap.max_pool_percent' "$GUIDED_STATE_FILE")" = "60" ]
  run guided_ctl_enter "max pool %: 60   (Enter cycles)"
  [ "$(jq -r '.options.zswap.max_pool_percent' "$GUIDED_STATE_FILE")" = "5" ]
}

# ── keymap / locale / timezone: big filterable lists + a "selected" side panel ─

@test "enter(category): keymap opens a big filterable list (values screen)" {
  set_nav "$(nav_to_category Host)"
  run guided_ctl_enter "Keymap: us"
  [ "$output" = "render" ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "values" ]
  [ "$(nav_get "$(<"$GUIDED_NAV_FILE")" field)" = "system.keymap" ]
}

@test "list(values keymap): a long MARKED list (multi) that includes us" {
  set_nav "$(nav_to_values Host system.keymap keymap)"
  run guided_ctl_list
  [ "${#lines[@]}" -gt 10 ]
  echo "$output" | grep -qE '\] us$'   # marked toggle row "[x]/[ ] us"
}

@test "enter(values keymap): toggling adds a keymap to the array (multi)" {
  printf '%s\n' '{"system":{"keymap":["us"]}}' > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_values Host system.keymap keymap)"
  run guided_ctl_enter "[ ] de"
  [ "$output" = "refresh" ]
  [ "$(jq -c '.system.keymap' "$GUIDED_STATE_FILE")" = '["us","de"]' ]
}

@test "list(values timezone): includes region/city entries" {
  set_nav "$(nav_to_values Host system.timezone timezone)"
  run guided_ctl_list
  echo "$output" | grep -qE '^[A-Z][A-Za-z_]+/'
}

@test "list(values locale): includes en_US.UTF-8" {
  set_nav "$(nav_to_values Host system.locale locale)"
  run guided_ctl_list
  echo "$output" | grep -qx "en_US.UTF-8"
}

@test "enter(values biglist): picking a value sets the scalar + returns" {
  set_nav "$(nav_to_values Host system.locale locale)"
  run guided_ctl_enter "de_DE.UTF-8"
  [ "$output" = "render" ]
  [ "$(jq -r '.system.locale' "$GUIDED_STATE_FILE")" = "de_DE.UTF-8" ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "category" ]
}

@test "preview(keymap): the side panel lists the selected keymaps" {
  printf '%s\n' '{"system":{"keymap":["us","de"]}}' > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_values Host system.keymap keymap)"
  run guided_ctl_preview "[ ] fr"
  echo "$output" | grep -q "Selected keymaps"
  echo "$output" | grep -q "us"      # a current selection
  echo "$output" | grep -q "fr"      # highlighted candidate (mark stripped)
}

@test "directive→action(render): a keymap screen shows the preview pane" {
  set_nav "$(nav_to_values Host system.keymap keymap)"
  run _guided_directive_to_action render /x/entry.sh
  echo "$output" | grep -q "change-preview-window(right,45%)"
}

# ── text screen: typed INTO fzf's query line, never leaves the window ─────────

@test "enter(text): a typed query commits the scalar + returns to the category" {
  set_nav "$(nav_to_text Host system.hostname hostname)"
  run guided_ctl_enter "current: (unset)" "myhost"
  [ "$output" = "render" ]
  [ "$(jq -r '.system.hostname' "$GUIDED_STATE_FILE")" = "myhost" ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "category" ]
}

@test "enter(text): an empty query leaves the value unchanged" {
  set_nav "$(nav_to_text Host system.hostname hostname)"
  run guided_ctl_enter "current: (unset)" ""
  [ "$output" = "render" ]
  [ "$(jq -c '. == {}' "$GUIDED_STATE_FILE")" = "true" ]
}

@test "enter(text): sysctl parses key=value from the query" {
  set_nav "$(nav_to_text Options sysctl sysctl)"
  run guided_ctl_enter "current: (unset)" "vm.swappiness=20"
  [ "$(jq -c '.sysctl["vm.swappiness"]' "$GUIDED_STATE_FILE")" = "20" ]
}

@test "enter(category): Add persist opens a native text editor (no terminal)" {
  set_nav "$(nav_to_category Disks)"
  run guided_ctl_enter "Add persist directory ▸ extend the curated defaults"
  [ "$output" = "render" ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "text" ]
  [ "$(nav_get "$(<"$GUIDED_NAV_FILE")" field)" = "__persist__" ]
}

@test "enter(text __persist__): a typed path appends to persist.directories" {
  set_nav "$(nav_to_text Disks __persist__ "persist dir")"
  run guided_ctl_enter "current: (unset)" "/var/lib/foo"
  [ "$(jq -c '.persist.directories' "$GUIDED_STATE_FILE")" = '["/var/lib/foo"]' ]
}

# ── sysctl as a list screen (default vm.swappiness=10) ───────────────────────

@test "enter(category): sysctl opens its list screen" {
  set_nav "$(nav_to_category Options)"
  run guided_ctl_enter "Sysctl: "
  [ "$output" = "render" ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "values" ]
  [ "$(nav_get "$(<"$GUIDED_NAV_FILE")" field)" = "sysctl" ]
}

@test "list(values sysctl): lists current pairs + an Add action + Back" {
  printf '%s\n' '{"sysctl":{"vm.swappiness":10}}' > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_values Options sysctl sysctl)"
  run guided_ctl_list
  echo "$output" | grep -q "vm.swappiness=10"
  echo "$output" | grep -q "+ Add sysctl"
  echo "$output" | grep -q "← Back"
}

@test "enter(values sysctl): + Add opens the key=value text editor" {
  set_nav "$(nav_to_values Options sysctl sysctl)"
  run guided_ctl_enter "+ Add sysctl (key=value)"
  [ "$output" = "render" ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "text" ]
  [ "$(nav_get "$(<"$GUIDED_NAV_FILE")" field)" = "sysctl" ]
}

@test "enter(text sysctl): adding a pair returns to the sysctl list screen" {
  set_nav "$(nav_to_text Options sysctl sysctl)"
  run guided_ctl_enter "+ Add sysctl (key=value)" "vm.dirty_ratio=20"
  [ "$(jq -c '.sysctl["vm.dirty_ratio"]' "$GUIDED_STATE_FILE")" = "20" ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "values" ]
  [ "$(nav_get "$(<"$GUIDED_NAV_FILE")" field)" = "sysctl" ]
}

# ── users as a native screen: toggle existing + in-fzf create (no terminal) ──

@test "enter(category): users opens its native screen" {
  set_nav "$(nav_to_category Users)"
  run guided_ctl_enter "Users: "
  [ "$output" = "render" ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "values" ]
  [ "$(nav_get "$(<"$GUIDED_NAV_FILE")" field)" = "users" ]
}

@test "list(values users): existing users marked + Create + Back, core excluded" {
  export OS_DIR="$TEST_DIR"
  mkdir -p "$OS_DIR/users/alice" "$OS_DIR/users/bob" "$OS_DIR/users/core"
  printf '{}' > "$OS_DIR/users/alice/profile.jsonc"
  printf '{}' > "$OS_DIR/users/bob/profile.jsonc"
  printf '{}' > "$OS_DIR/users/core/profile.jsonc"
  printf '%s\n' '{"users":["alice"]}' > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_values Users users users)"
  run guided_ctl_list
  echo "$output" | grep -q "^alice — "          # enabled: name — shell · pw …
  echo "$output" | grep -q "^bob — disabled$"   # disabled: no checkbox
  ! echo "$output" | grep -q "core"
  echo "$output" | grep -q "+ Create user"
}

@test "enter(values users): a user row opens its User Editor (slice 02)" {
  printf '%s\n' '{"users":["alice","bob"]}' > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_values Users users users)"
  run guided_ctl_enter "bob — bash · pw default 12345"
  [ "$output" = "render" ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "useredit" ]
  [ "$(nav_get "$(<"$GUIDED_NAV_FILE")" user)" = "bob" ]
}

@test "enter(values users): + Create opens the new-user text editor" {
  set_nav "$(nav_to_values Users users users)"
  run guided_ctl_enter "+ Create user (name)"
  [ "$output" = "render" ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "text" ]
  [ "$(nav_get "$(<"$GUIDED_NAV_FILE")" field)" = "__newuser__" ]
}

# ── in-menu credentials (ticket 03) ──────────────────────────────────────────

@test "list(values users): rows tag unset secrets 'default 12345' (ADR 0055)" {
  export GUIDED_SECRETS_FILE="$TEST_DIR/secrets.json"; printf '{}\n' > "$GUIDED_SECRETS_FILE"
  printf '%s\n' '{"users":["aquastias"]}' > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_values Users users users)"
  run guided_ctl_list
  echo "$output" | grep -qx "root — bash · pw default 12345"
  echo "$output" | grep -q "^aquastias — zsh · pw default 12345"
  echo "$output" | grep -qE '^ +password \(aquastias\): default 12345$'
}

@test "list(values users): rows tag 'custom' once the secret file has them" {
  export GUIDED_SECRETS_FILE="$TEST_DIR/secrets.json"
  printf '%s\n' '{"root_password":"r","users":{"aquastias":{"password":"a"}}}' \
    > "$GUIDED_SECRETS_FILE"
  printf '%s\n' '{"users":["aquastias"]}' > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_values Users users users)"
  run guided_ctl_list
  echo "$output" | grep -qx "root — bash · pw custom"
  echo "$output" | grep -qE '^ +password \(aquastias\): custom$'
}

@test "list(values users): a wired age key tags unset secrets 'from age'" {
  export GUIDED_SECRETS_FILE="$TEST_DIR/secrets.json"; printf '{}\n' > "$GUIDED_SECRETS_FILE"
  printf '%s\n' '{"users":["aquastias"],"options":{"age_key_url":"https://k/age"}}' \
    > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_values Users users users)"
  run guided_ctl_list
  echo "$output" | grep -qx "root — bash · pw from age"
  echo "$output" | grep -qE '^ +password \(aquastias\): from age$'
}

@test "list(values users): an operator override beats a wired age key ('custom')" {
  export GUIDED_SECRETS_FILE="$TEST_DIR/secrets.json"
  printf '%s\n' '{"root_password":"r"}' > "$GUIDED_SECRETS_FILE"
  printf '%s\n' '{"options":{"age_key_url":"https://k/age"}}' > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_values Users users users)"
  run guided_ctl_list
  echo "$output" | grep -qx "root — bash · pw custom"
}

@test "enter(values users): the merged root row opens the Root Editor (ADR 0063)" {
  set_nav "$(nav_to_values Users users users)"
  run guided_ctl_enter "root — bash · pw default 12345"
  [ "$output" = "render" ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "rooteditor" ]
}

@test "enter(values users): a per-user password row captures for that user" {
  set_nav "$(nav_to_values Users users users)"
  [ "$(guided_ctl_enter "      password (aquastias): default 12345")" \
    = "secret-user aquastias" ]
}

# ── Users screen: no disk-encryption row (ADR 0059) ──────────────────────────
# The disk passphrase moved to the Disks Encryption Editor; the Users screen is
# now strictly accounts. Its rows still report the ACCOUNT default (12345), not
# the disk default — guarding the deliberate split against a single-constant
# refactor.

@test "list(values users): no disk-encryption row, even with encryption on" {
  export GUIDED_SECRETS_FILE="$TEST_DIR/secrets.json"; printf '{}\n' > "$GUIDED_SECRETS_FILE"
  printf '%s\n' '{"users":["aquastias"],"options":{"encryption":true}}' \
    > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_values Users users users)"
  run guided_ctl_list
  ! echo "$output" | grep -q "disk encryption:"
  echo "$output" | grep -qx "root — bash · pw default 12345"   # account default
}

@test "enter(values users): no row routes to the passphrase capture" {
  set_nav "$(nav_to_values Users users users)"
  # the old row line, were it still handled, would emit secret-enc; it must not.
  [ "$(guided_ctl_enter "disk encryption: default 12345678")" != "secret-enc" ]
}

# ── Root Editor: password + shell behind one editor (ADR 0063) ───────────────
# The merged root row opens a Root Editor exposing exactly `password` and `shell`.
# Storage is unchanged (options.root_shell + the no-SOPS root role); only the
# surface moved off the Users list into this editor.

@test "list(rooteditor): shows a password row + a shell row (default bash)" {
  export GUIDED_SECRETS_FILE="$TEST_DIR/secrets.json"
  printf '{}\n' > "$GUIDED_SECRETS_FILE"
  set_nav "$(nav_to_rooteditor Users)"
  run guided_ctl_list
  echo "$output" | grep -qx "password: default 12345"
  echo "$output" | grep -q "shell: bash"
  echo "$output" | grep -q "← Back"
}

@test "enter(rooteditor): shell cycles bash→zsh into options.root_shell" {
  set_nav "$(nav_to_rooteditor Users)"
  run guided_ctl_enter "shell: bash   (Enter cycles)"
  [ "$output" = "refresh" ]
  [ "$(jq -r '.options.root_shell' "$GUIDED_STATE_FILE")" = "/bin/zsh" ]
}

@test "enter(rooteditor): shell cycles zsh→fish" {
  printf '%s\n' '{"options":{"root_shell":"/bin/zsh"}}' > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_rooteditor Users)"
  guided_ctl_enter "shell: zsh   (Enter cycles)" >/dev/null
  [ "$(jq -r '.options.root_shell' "$GUIDED_STATE_FILE")" = "/bin/fish" ]
}

@test "enter(rooteditor): cycling shell to default (bash) drops the override" {
  printf '%s\n' '{"options":{"root_shell":"/bin/fish"}}' > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_rooteditor Users)"
  guided_ctl_enter "shell: fish   (Enter cycles)" >/dev/null
  [ "$(jq -r '.options.root_shell // "unset"' "$GUIDED_STATE_FILE")" = "unset" ]
}

@test "enter(rooteditor): password falls back to execute() without rich chrome" {
  unset GUIDED_RICH_CHROME
  set_nav "$(nav_to_rooteditor Users)"
  [ "$(guided_ctl_enter "password: default 12345")" = "secret-root" ]
}

@test "back(rooteditor): Esc returns to the Users list" {
  set_nav "$(nav_to_rooteditor Users)"
  run guided_ctl_enter "← Back"
  [ "$output" = "render" ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "values" ]
  [ "$(nav_get "$(<"$GUIDED_NAV_FILE")" field)" = "users" ]
}

# ── action rows visible in rich chrome (ADR 0063) ────────────────────────────

@test "list(values users) rich: + Create user + Back render as visible rows" {
  printf '%s\n' '{"users":["alice"]}' > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_values Users users users)"
  GUIDED_RICH_CHROME=1 run guided_ctl_list
  echo "$output" | grep -q "+ Create user"
  echo "$output" | grep -q "← Back"
}

# ── user detail preview (ADR 0063) ───────────────────────────────────────────
# The Users screen joins the preview set; hovering a user row shows its effective
# (core-merged, override-applied) profile. A session-created user reflects its
# in-progress editor-form state (held in the userforms file).

@test "preview(values users): the Users screen is registered for a preview" {
  set_nav "$(nav_to_values Users users users)"
  run _ctl_field_has_preview users
  [ "$status" -eq 0 ]
}

@test "preview(values users): a session user shows its in-progress form state" {
  export GUIDED_USERFORMS_FILE="$TEST_DIR/uf.json"
  printf '%s\n' '{"alice":{"shell":"/bin/fish","sudo":true,
    "groups":["wheel","docker"],"programs":["git"],
    "ssh_authorized_keys":["k1","k2"],"git":{"name":"A","email":"a@x"}}}' \
    > "$GUIDED_USERFORMS_FILE"
  printf '%s\n' '{"users":["alice"]}' > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_values Users users users)"
  run guided_ctl_preview "alice — fish · pw default 12345"
  echo "$output" | grep -q "/bin/fish"        # shell
  echo "$output" | grep -q "sudo:.*on"
  echo "$output" | grep -q "groups:.*wheel, docker"
  echo "$output" | grep -q "programs:"
  echo "$output" | grep -q "git:.*A <a@x>"
  echo "$output" | grep -q "ssh keys:.*2"      # SSH-key count
}

@test "preview(values users): shows effective (core-merged) values" {
  mkdir -p "$OS_DIR/users"/{core,bob}
  printf '{}\n' > "$OS_DIR/users/core/profile.jsonc"
  printf '{"shell":"/bin/bash","groups":["wheel"]}\n' \
    > "$OS_DIR/users/bob/profile.jsonc"
  export GUIDED_USERFORMS_FILE="$TEST_DIR/uf.json"
  printf '{"bob":{"shell":"/bin/zsh"}}\n' > "$GUIDED_USERFORMS_FILE"
  printf '%s\n' '{"users":["bob"]}' > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_values Users users users)"
  run guided_ctl_preview "bob — zsh · pw default 12345"
  echo "$output" | grep -q "/bin/zsh"          # override applied
  echo "$output" | grep -q "wheel"             # committed group merged in
}

@test "preview(values users): the root row shows shell + password source" {
  export GUIDED_SECRETS_FILE="$TEST_DIR/secrets.json"; printf '{}\n' > "$GUIDED_SECRETS_FILE"
  set_nav "$(nav_to_values Users users users)"
  run guided_ctl_preview "root — bash · pw default 12345"
  echo "$output" | grep -q "shell:.*bash"
  echo "$output" | grep -q "password:.*default 12345"
}

@test "preview(values users): + Create user previews nothing" {
  set_nav "$(nav_to_values Users users users)"
  run guided_ctl_preview "+ Create user (name)"
  [ -z "$output" ]
}

@test "proceed gate: never blocked — installs with secrets unset (ADR 0055)" {
  export GUIDED_SECRETS_FILE="$TEST_DIR/secrets.json"; printf '{}\n' > "$GUIDED_SECRETS_FILE"
  printf '%s\n' '{"users":["aquastias"]}' > "$GUIDED_STATE_FILE"
  set_nav '{"screen":"top"}'
  [ "$(guided_ctl_enter "Proceed ▸ review & install")" = "terminal proceed" ]
}

@test "proceed gate: allowed (terminal proceed) once all are set" {
  export GUIDED_SECRETS_FILE="$TEST_DIR/secrets.json"
  printf '%s\n' '{"root_password":"r","users":{"aquastias":{"password":"a"}}}' \
    > "$GUIDED_SECRETS_FILE"
  printf '%s\n' '{"users":["aquastias"]}' > "$GUIDED_STATE_FILE"
  set_nav '{"screen":"top"}'
  [ "$(guided_ctl_enter "Proceed ▸ review & install")" = "terminal proceed" ]
}

@test "proceed gate: inert (proceed) when no secrets file is wired" {
  unset GUIDED_SECRETS_FILE
  set_nav '{"screen":"top"}'
  [ "$(guided_ctl_enter "Proceed ▸ review & install")" = "terminal proceed" ]
}

# ── slice 01: flatten Users + top-level password warning ─────────────────────

@test "enter(top): Users flattens straight to the users screen (no category)" {
  set_nav '{"screen":"top"}'
  run guided_ctl_enter "Users — primary user, extra accounts"
  [ "$output" = "render" ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "values" ]
  [ "$(nav_get "$(<"$GUIDED_NAV_FILE")" field)" = "users" ]
}

@test "back(values users): returns to top, not the category screen" {
  set_nav "$(nav_to_values Users users users)"
  run guided_ctl_back
  [ "$output" = "render" ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "top" ]
}

@test "list(top): no ⚠ block — Proceed reads review & install with pw unset (ADR 0055)" {
  export GUIDED_SECRETS_FILE="$TEST_DIR/secrets.json"; printf '{}\n' > "$GUIDED_SECRETS_FILE"
  printf '%s\n' '{"users":["aquastias"]}' > "$GUIDED_STATE_FILE"
  set_nav '{"screen":"top"}'
  run guided_ctl_list
  ! echo "$output" | grep -q "pw needed"
  ! echo "$output" | grep -q "set passwords first"
  echo "$output" | grep -q "Proceed ▸ review & install"
}

@test "list(top): no ⚠, normal Proceed once every password is set" {
  export GUIDED_SECRETS_FILE="$TEST_DIR/secrets.json"
  printf '%s\n' '{"root_password":"r","users":{"aquastias":{"password":"a"}}}' \
    > "$GUIDED_SECRETS_FILE"
  printf '%s\n' '{"users":["aquastias"]}' > "$GUIDED_STATE_FILE"
  set_nav '{"screen":"top"}'
  run guided_ctl_list
  ! echo "$output" | grep -q "pw needed"
  echo "$output" | grep -q "Proceed ▸ review & install"
}

@test "list(top): undecorated when no secrets file is wired" {
  unset GUIDED_SECRETS_FILE
  set_nav '{"screen":"top"}'
  run guided_ctl_list
  ! echo "$output" | grep -q "pw needed"
  echo "$output" | grep -q "Proceed ▸ review & install"
}

# ── encryption passphrase: never a gate (ADR 0055, supersedes ADR 0054) ──────

@test "list(top): no Disks ⚠ block when passphrase unset (ADR 0055)" {
  export GUIDED_SECRETS_FILE="$TEST_DIR/secrets.json"
  printf '%s\n' '{"root_password":"r"}' > "$GUIDED_SECRETS_FILE"
  printf '%s\n' '{"options":{"encryption":true}}' > "$GUIDED_STATE_FILE"
  set_nav '{"screen":"top"}'
  run guided_ctl_list
  ! echo "$output" | grep -q "pw needed"
  echo "$output" | grep -q "Proceed ▸ review & install"
}

@test "proceed gate: installs even when encryption on + passphrase unset (ADR 0055)" {
  export GUIDED_SECRETS_FILE="$TEST_DIR/secrets.json"
  printf '%s\n' '{"root_password":"r"}' > "$GUIDED_SECRETS_FILE"
  printf '%s\n' '{"options":{"encryption":true}}' > "$GUIDED_STATE_FILE"
  set_nav '{"screen":"top"}'
  [ "$(guided_ctl_enter "Proceed ▸ review & install")" = "terminal proceed" ]
}

@test "proceed gate: allowed once the passphrase is set (encryption on)" {
  export GUIDED_SECRETS_FILE="$TEST_DIR/secrets.json"
  printf '%s\n' '{"root_password":"r","enc_passphrase":"corrhorse"}' \
    > "$GUIDED_SECRETS_FILE"
  printf '%s\n' '{"options":{"encryption":true}}' > "$GUIDED_STATE_FILE"
  set_nav '{"screen":"top"}'
  [ "$(guided_ctl_enter "Proceed ▸ review & install")" = "terminal proceed" ]
}

@test "gate: encryption off does not block, and the passphrase is retained" {
  export GUIDED_SECRETS_FILE="$TEST_DIR/secrets.json"
  printf '%s\n' '{"root_password":"r","enc_passphrase":"corrhorse"}' \
    > "$GUIDED_SECRETS_FILE"
  printf '%s\n' '{"options":{"encryption":false}}' > "$GUIDED_STATE_FILE"
  set_nav '{"screen":"top"}'
  [ "$(guided_ctl_enter "Proceed ▸ review & install")" = "terminal proceed" ]
  run guided_ctl_list
  ! echo "$output" | grep -qE '^Disks — .*pw needed'   # no gate while off
  # retain-silently: the stored passphrase survives the toggle-off
  [ "$(jq -r '.enc_passphrase' "$GUIDED_SECRETS_FILE")" = "corrhorse" ]
}

@test "enter(values users): a disabled user row also opens its editor" {
  printf '%s\n' '{"users":["alice"]}' > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_values Users users users)"
  run guided_ctl_enter "bob — disabled"
  [ "$output" = "render" ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "useredit" ]
  [ "$(nav_get "$(<"$GUIDED_NAV_FILE")" user)" = "bob" ]
}

# ── slice 02: the per-user User Editor ───────────────────────────────────────

@test "back(useredit): returns to the flattened Users list" {
  set_nav "$(nav_to_useredit Users alice)"
  run guided_ctl_back
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "values" ]
  [ "$(nav_get "$(<"$GUIDED_NAV_FILE")" field)" = "users" ]
}

@test "list(useredit committed): enabled + shell (from profile) + Back" {
  export OS_DIR="$TEST_DIR"
  mkdir -p "$OS_DIR/users/alice" "$OS_DIR/users/core"
  printf '{"shell":"/bin/zsh"}' > "$OS_DIR/users/alice/profile.jsonc"
  printf '{}' > "$OS_DIR/users/core/profile.jsonc"
  printf '%s\n' '{"users":["alice"]}' > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_useredit Users alice)"
  run guided_ctl_list
  echo "$output" | grep -q "enabled: on"
  echo "$output" | grep -q "shell: zsh"
  echo "$output" | grep -q "← Back"
  ! echo "$output" | grep -q "remove user"     # committed → no remove
}

@test "list(useredit ad-hoc): remove + shell, no enabled row" {
  export OS_DIR="$TEST_DIR"
  mkdir -p "$OS_DIR/users/core"
  printf '{}' > "$OS_DIR/users/core/profile.jsonc"
  printf '%s\n' '{"users":["dave"]}' > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_useredit Users dave)"
  run guided_ctl_list
  ! echo "$output" | grep -q "enabled:"        # ad-hoc → no enabled
  echo "$output" | grep -q "shell: zsh"        # User Core default
  echo "$output" | grep -q "✗ remove user"
}

@test "enter(useredit): enabled toggles the user out of the install" {
  export OS_DIR="$TEST_DIR"
  mkdir -p "$OS_DIR/users/alice" "$OS_DIR/users/core"
  printf '{}' > "$OS_DIR/users/alice/profile.jsonc"
  printf '{}' > "$OS_DIR/users/core/profile.jsonc"
  printf '%s\n' '{"users":["alice"]}' > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_useredit Users alice)"
  run guided_ctl_enter "enabled: on   (Enter toggles)"
  [ "$output" = "refresh" ]
  [ "$(jq -c '.users' "$GUIDED_STATE_FILE")" = '[]' ]
}

@test "enter(useredit): shell cycles into an install-scoped override" {
  export OS_DIR="$TEST_DIR"
  export GUIDED_USERFORMS_FILE="$TEST_DIR/uf.json"; printf '{}\n' > "$GUIDED_USERFORMS_FILE"
  mkdir -p "$OS_DIR/users/alice" "$OS_DIR/users/core"
  printf '{"shell":"/bin/bash"}' > "$OS_DIR/users/alice/profile.jsonc"
  printf '{}' > "$OS_DIR/users/core/profile.jsonc"
  printf '%s\n' '{"users":["alice"]}' > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_useredit Users alice)"
  run guided_ctl_enter "shell: bash   (Enter cycles)"
  [ "$output" = "refresh" ]
  [ "$(jq -r '.alice.shell' "$GUIDED_USERFORMS_FILE")" = "/bin/zsh" ]
  run guided_ctl_list
  echo "$output" | grep -q "shell: zsh"        # display reflects the override
}

@test "enter(useredit): cycling back to the committed shell drops the override" {
  export OS_DIR="$TEST_DIR"
  export GUIDED_USERFORMS_FILE="$TEST_DIR/uf.json"
  printf '{"alice":{"shell":"/bin/fish"}}\n' > "$GUIDED_USERFORMS_FILE"
  mkdir -p "$OS_DIR/users/alice" "$OS_DIR/users/core"
  printf '{"shell":"/bin/bash"}' > "$OS_DIR/users/alice/profile.jsonc"
  printf '{}' > "$OS_DIR/users/core/profile.jsonc"
  printf '%s\n' '{"users":["alice"]}' > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_useredit Users alice)"
  run guided_ctl_enter "shell: fish   (Enter cycles)"   # fish → wrap bash = committed
  [ "$(jq -c '.' "$GUIDED_USERFORMS_FILE")" = '{}' ]     # strict delta: override gone
}

@test "enter(useredit): remove drops an ad-hoc user + returns to the list" {
  export OS_DIR="$TEST_DIR"
  export GUIDED_USERFORMS_FILE="$TEST_DIR/uf.json"
  printf '{"dave":{"shell":"/bin/zsh"}}\n' > "$GUIDED_USERFORMS_FILE"
  printf '%s\n' '{"users":["dave"]}' > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_useredit Users dave)"
  run guided_ctl_enter "✗ remove user"
  [ "$output" = "render" ]
  [ "$(jq -c '.users' "$GUIDED_STATE_FILE")" = '[]' ]
  [ "$(jq -c '.' "$GUIDED_USERFORMS_FILE")" = '{}' ]     # its form cleared too
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "values" ]
}

@test "directive→action: secret rows execute the masked capture verb" {
  local a; a="$(_guided_directive_to_action secret-root /e)"
  [[ "$a" == *"secret root"* ]]
  a="$(_guided_directive_to_action "secret-user alex" /e)"
  [[ "$a" == *"secret user alex"* ]]
}

@test "directive→action: a notice warns in the header without accepting" {
  local a; a="$(_guided_directive_to_action "notice ⚠ set it" /e)"
  [[ "$a" == *"change-header("* ]]
  [[ "$a" == *"bell"* ]]
  [[ "$a" != *accept* ]]
}

@test "enter(text __newuser__): a typed name is added + drops into the editor" {
  export GUIDED_USERFORMS_FILE="$TEST_DIR/uf.json"; printf '{}\n' > "$GUIDED_USERFORMS_FILE"
  printf '%s\n' '{"users":["alice"]}' > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_text Users __newuser__ "new user")"
  run guided_ctl_enter "+ Create user (name)" "carol"
  [ "$(jq -c '.users' "$GUIDED_STATE_FILE")" = '["alice","carol"]' ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "useredit" ]
  [ "$(nav_get "$(<"$GUIDED_NAV_FILE")" user)" = "carol" ]
  # seeded with the create defaults: User Core shell / sudo on / wheel
  [ "$(jq -c '.carol' "$GUIDED_USERFORMS_FILE")" \
    = '{"shell":"/bin/zsh","sudo":true,"groups":["wheel"]}' ]
}

@test "enter(text __newuser__): a duplicate name is refused with a notice" {
  export OS_DIR="$TEST_DIR"; mkdir -p "$OS_DIR/users/alice"
  printf '{}' > "$OS_DIR/users/alice/profile.jsonc"
  printf '%s\n' '{"users":["alice"]}' > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_text Users __newuser__ "new user")"
  run guided_ctl_enter "+ Create user (name)" "alice"
  [[ "$output" == notice* ]]
  [ "$(jq -c '.users' "$GUIDED_STATE_FILE")" = '["alice"]' ]   # unchanged
}

# ── back / abort ─────────────────────────────────────────────────────────────

@test "back: at the top screen, aborts the whole menu" {
  run guided_ctl_back
  [ "$output" = "abort" ]
}

@test "back: from a category, returns to the top screen" {
  set_nav "$(nav_to_category Options)"
  run guided_ctl_back
  [ "$output" = "render" ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "top" ]
}

# ── directive → fzf action translation (pure) ────────────────────────────────

@test "directive→action: render re-lists in place via reload" {
  run _guided_directive_to_action render /x/entry.sh
  echo "$output" | grep -q "reload(bash /x/entry.sh list)"
}

@test "directive→action: render also re-headers + re-prompts the screen" {
  set_nav "$(nav_to_category Disks)"
  run _guided_directive_to_action render /x/entry.sh
  echo "$output" | grep -q "reload(bash /x/entry.sh list)"
  echo "$output" | grep -q "change-header(Enter edit"
  echo "$output" | grep -q "change-prompt(Disks> )"
}

@test "directive→action: render clears the stale filter query first" {
  run _guided_directive_to_action render /x/entry.sh
  # clear-query must precede reload so a leftover filter can't hide the screen
  [[ "$output" == clear-query+reload* ]]
}

@test "directive→action: edit-oneshot clears the query before re-listing" {
  run _guided_directive_to_action "edit-oneshot options.kernel" /x/entry.sh
  echo "$output" | grep -q "clear-query+reload(bash /x/entry.sh list)"
}

@test "directive→action: abort and noop map to fzf primitives" {
  [ "$(_guided_directive_to_action abort /x/entry.sh)" = "abort" ]
  [ "$(_guided_directive_to_action noop /x/entry.sh)" = "ignore" ]
}

@test "directive→action: terminal writes the verb to the result file + accepts" {
  export GUIDED_RESULT_FILE="$TEST_DIR/result"
  run _guided_directive_to_action "terminal proceed" /x/entry.sh
  echo "$output" | grep -q "proceed"
  echo "$output" | grep -q "$TEST_DIR/result"
  echo "$output" | grep -q "+accept"
}

@test "directive→action: edit-oneshot hands off then re-lists" {
  run _guided_directive_to_action "edit-oneshot system.hostname" /x/entry.sh
  echo "$output" | grep -q "execute(bash /x/entry.sh oneshot system.hostname)"
  echo "$output" | grep -q "reload(bash /x/entry.sh list)"
}

# ── latency fast-path (ticket 04): reload(cat FILE) instead of a second fork ──

@test "fast-path: render reloads via cat of the precomputed list file" {
  export GUIDED_LIST_FILE="$TEST_DIR/list"
  set_nav "$(nav_to_category Disks)"
  run _guided_directive_to_action render /x/entry.sh
  echo "$output" | grep -q "reload(cat "
  ! echo "$output" | grep -q "reload(bash"
}

@test "fast-path: the precomputed file equals guided_ctl_list (output-equiv)" {
  export GUIDED_LIST_FILE="$TEST_DIR/list"
  set_nav "$(nav_to_category Disks)"
  local direct; direct="$(guided_ctl_list)"
  _guided_directive_to_action render /x/entry.sh >/dev/null
  [ "$(cat "$GUIDED_LIST_FILE")" = "$direct" ]
}

@test "fast-path: refresh also cats the precomputed list file" {
  export GUIDED_LIST_FILE="$TEST_DIR/list"
  set_nav "$(nav_to_values Options options.kernel kernel)"
  run _guided_directive_to_action refresh /x/entry.sh
  echo "$output" | grep -q "reload-sync(cat "
}

@test "fast-path: falls back to bash re-render with no list file wired" {
  unset GUIDED_LIST_FILE
  run _guided_directive_to_action render /x/entry.sh
  echo "$output" | grep -q "reload(bash /x/entry.sh list)"
}

# ── slice 03: full-profile User Editor fields (userfield sub-editors) ─────────

adhoc_editor_setup() {          # an ad-hoc user 'dave' with a userforms file
  export OS_DIR="$TEST_DIR"
  mkdir -p "$OS_DIR/users/core"; printf '{}' > "$OS_DIR/users/core/profile.jsonc"
  export GUIDED_USERFORMS_FILE="$TEST_DIR/uf.json"; printf '{}\n' > "$GUIDED_USERFORMS_FILE"
  printf '%s\n' '{"users":["dave"]}' > "$GUIDED_STATE_FILE"
}

@test "list(useredit): shows the full profile rows" {
  adhoc_editor_setup
  set_nav "$(nav_to_useredit Users dave)"
  run guided_ctl_list
  echo "$output" | grep -q "sudo: off"
  echo "$output" | grep -q "groups: (none)"
  echo "$output" | grep -q "git name: (unset)"
  echo "$output" | grep -q "git email: (unset)"
  echo "$output" | grep -q "ssh keys: 0"
  echo "$output" | grep -q "programs: (none)"
}

@test "enter(useredit): sudo toggles into the override" {
  adhoc_editor_setup
  set_nav "$(nav_to_useredit Users dave)"
  run guided_ctl_enter "sudo: off   (Enter toggles)"
  [ "$output" = "refresh" ]
  [ "$(jq -r '.dave.sudo' "$GUIDED_USERFORMS_FILE")" = "true" ]
}

@test "enter(useredit): groups opens a userfield multi-select" {
  adhoc_editor_setup
  set_nav "$(nav_to_useredit Users dave)"
  run guided_ctl_enter "groups: (none)   (Enter edits)"
  [ "$output" = "render" ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "userfield" ]
  [ "$(nav_get "$(<"$GUIDED_NAV_FILE")" field)" = "groups" ]
}

@test "list+enter(userfield groups): mark options + toggle into the override" {
  adhoc_editor_setup
  set_nav "$(nav_to_userfield Users dave groups groups)"
  run guided_ctl_list
  echo "$output" | grep -q "\[ \] docker"
  run guided_ctl_enter "[ ] docker"
  [ "$output" = "refresh" ]
  [ "$(jq -c '.dave.groups' "$GUIDED_USERFORMS_FILE")" = '["docker"]' ]
}

@test "enter(userfield git.name): a typed value commits + backs to the editor" {
  adhoc_editor_setup
  set_nav "$(nav_to_userfield Users dave git.name "git name")"
  run guided_ctl_enter "" "Dave D"
  [ "$output" = "render" ]
  [ "$(jq -r '.dave.git.name' "$GUIDED_USERFORMS_FILE")" = "Dave D" ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "useredit" ]
}

@test "userfield ssh: add opens a text screen, then appends the key" {
  adhoc_editor_setup
  set_nav "$(nav_to_userfield Users dave ssh "ssh keys")"
  run guided_ctl_enter "+ Add SSH key"
  [ "$(nav_get "$(<"$GUIDED_NAV_FILE")" field)" = "ssh.add" ]
  run guided_ctl_enter "" "ssh-ed25519 AAAA"
  [ "$(jq -c '.dave.ssh_authorized_keys' "$GUIDED_USERFORMS_FILE")" \
    = '["ssh-ed25519 AAAA"]' ]
  [ "$(nav_get "$(<"$GUIDED_NAV_FILE")" field)" = "ssh" ]   # back to the key list
}

@test "userfield programs: toggle marks against resolvable program names" {
  adhoc_editor_setup
  # a couple of resolvable programs under OS_DIR/programs/<cat>/<name>
  mkdir -p "$OS_DIR/programs/dev/git" "$OS_DIR/programs/dev/htop"
  set_nav "$(nav_to_userfield Users dave programs programs)"
  run guided_ctl_enter "[ ] git"
  [ "$output" = "refresh" ]
  [ "$(jq -c '.dave.programs' "$GUIDED_USERFORMS_FILE")" = '["git"]' ]
}

# ── extra-packages row routes by kind at ENTRY time ─────────────────────────
# The deleted promotion rule ran in the guided emit path only, so the same
# file installed differently per front-end. Routing at entry keeps the
# convenience while what reaches Config State stays canonical.

@test "extra packages: a plain name stays a repo package" {
  mixed_programs_setup
  set_nav "$(nav_to_text Packages packages.repo.extra "extra packages")"
  run guided_ctl_enter "" "htop"
  [ "$status" -eq 0 ]
  [ "$(jq -c '.packages.repo.extra' "$GUIDED_STATE_FILE")" = '["htop"]' ]
}

@test "extra packages: a system Program name routes to system_programs" {
  mixed_programs_setup
  set_nav "$(nav_to_text Packages packages.repo.extra "extra packages")"
  run guided_ctl_enter "" "cups"
  [ "$status" -eq 0 ]
  [ "$(jq -c '.system_programs' "$GUIDED_STATE_FILE")" = '["cups"]' ]
  # and it is NOT left behind as a package
  [ "$(jq -c '.packages.repo.extra // []' "$GUIDED_STATE_FILE")" = '[]' ]
}

@test "extra packages: a mixed entry splits by kind" {
  mixed_programs_setup
  set_nav "$(nav_to_text Packages packages.repo.extra "extra packages")"
  run guided_ctl_enter "" "htop cups"
  [ "$status" -eq 0 ]
  [ "$(jq -c '.packages.repo.extra' "$GUIDED_STATE_FILE")" = '["htop"]' ]
  [ "$(jq -c '.system_programs' "$GUIDED_STATE_FILE")" = '["cups"]' ]
}

@test "extra packages: routing reports where the name went" {
  mixed_programs_setup
  set_nav "$(nav_to_text Packages packages.repo.extra "extra packages")"
  run guided_ctl_enter "" "cups"
  [[ "$output" == *"routed to system programs"* ]]
  [[ "$output" == *"cups"* ]]
}

# ── program picker option-set MEMBERSHIP (R22) ───────────────────────────────
# The two pickers have opposite requirements and used to share one unfiltered
# list. Assert *which options are offered*, not only the [x]/[ ] marking —
# marking-only assertions are exactly what let the bad option sets through.

# Two programs of each kind under a hermetic OS_DIR.
mixed_programs_setup() {
  export OS_DIR="$TEST_DIR"
  local spec cat name sys
  for spec in "bootloader/grub/true" "printing/cups/true" \
              "virtualization/docker/false" "security/borg/false"; do
    IFS=/ read -r cat name sys <<<"$spec"
    mkdir -p "$OS_DIR/programs/$cat/$name"
    printf '{"name":"%s","system":%s}\n' "$name" "$sys" \
      > "$OS_DIR/programs/$cat/$name/config.jsonc"
    printf '#!/bin/sh\n' > "$OS_DIR/programs/$cat/$name/install.sh"
  done
}

@test "system_programs picker offers exactly the system:true programs" {
  mixed_programs_setup
  set_nav "$(nav_to_values Host system_programs "system programs")"
  run guided_ctl_list
  [ "$status" -eq 0 ]
  echo "$output" | grep -qx "\[ \] cups"
  echo "$output" | grep -qx "\[ \] grub"
  # the system:false programs must not be offered at all
  ! echo "$output" | grep -q "docker"
  ! echo "$output" | grep -q "borg"
  [ "$(echo "$output" | grep -c '^\[')" -eq 2 ]
}

@test "User Editor programs picker offers exactly the system:false programs" {
  mixed_programs_setup
  mkdir -p "$OS_DIR/users/core"
  printf '{}' > "$OS_DIR/users/core/profile.jsonc"
  export GUIDED_USERFORMS_FILE="$TEST_DIR/uf.json"
  printf '{}\n' > "$GUIDED_USERFORMS_FILE"
  printf '%s\n' '{"users":["dave"]}' > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_userfield Users dave programs programs)"
  run guided_ctl_list
  [ "$status" -eq 0 ]
  echo "$output" | grep -qx "\[ \] borg"
  echo "$output" | grep -qx "\[ \] docker"
  # the system:true programs must not be offered at all
  ! echo "$output" | grep -q "cups"
  ! echo "$output" | grep -q "grub"
  [ "$(echo "$output" | grep -c '^\[')" -eq 2 ]
}

@test "back(userfield): returns to the user's editor" {
  adhoc_editor_setup
  set_nav "$(nav_to_userfield Users dave groups groups)"
  run guided_ctl_back
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "useredit" ]
  [ "$(nav_get "$(<"$GUIDED_NAV_FILE")" user)" = "dave" ]
}

@test "userfield groups (committed): dropping back to committed clears override" {
  export OS_DIR="$TEST_DIR"
  mkdir -p "$OS_DIR/users/alice" "$OS_DIR/users/core"
  printf '{}' > "$OS_DIR/users/core/profile.jsonc"
  printf '{"groups":["docker"]}' > "$OS_DIR/users/alice/profile.jsonc"
  export GUIDED_USERFORMS_FILE="$TEST_DIR/uf.json"; printf '{}\n' > "$GUIDED_USERFORMS_FILE"
  printf '%s\n' '{"users":["alice"]}' > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_userfield Users alice groups groups)"
  # committed has docker; toggling it off then on again lands back on committed
  guided_ctl_enter "[x] docker" >/dev/null    # remove → override []
  run guided_ctl_enter "[ ] docker"           # add back → equals committed
  [ "$(jq -c '.' "$GUIDED_USERFORMS_FILE")" = '{}' ]   # strict delta: no override
}

# ── slice 05: inline masked password entry (secret screen) ───────────────────

secret_setup() {
  export GUIDED_SECRETS_FILE="$TEST_DIR/secrets.json"; printf '{}\n' > "$GUIDED_SECRETS_FILE"
  export GUIDED_PWBUF_FILE="$TEST_DIR/pwbuf"; : > "$GUIDED_PWBUF_FILE"
  export GUIDED_PWPENDING_FILE="$TEST_DIR/pwpending"; : > "$GUIDED_PWPENDING_FILE"
}

@test "enter(rooteditor): root pw opens the inline screen under rich chrome" {
  secret_setup; export GUIDED_RICH_CHROME=1
  printf '%s\n' '{"users":["dave"]}' > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_rooteditor Users)"
  run guided_ctl_enter "password: (not set)"
  [ "$output" = "render" ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "secret" ]
  [ "$(nav_get "$(<"$GUIDED_NAV_FILE")" target)" = "root" ]
  [ "$(nav_get "$(<"$GUIDED_NAV_FILE")" phase)" = "entry" ]
}

@test "enter(rooteditor): root pw falls back to execute() without rich chrome" {
  secret_setup; unset GUIDED_RICH_CHROME
  set_nav "$(nav_to_rooteditor Users)"
  [ "$(guided_ctl_enter "password: (not set)")" = "secret-root" ]
}

@test "enter(secret entry): stashes the buffer as pending + moves to confirm" {
  secret_setup
  printf 'hunter2' > "$GUIDED_PWBUF_FILE"
  set_nav "$(nav_to_secret Users root "" entry)"
  run guided_ctl_enter ""
  [ "$output" = "render" ]
  [ "$(nav_get "$(<"$GUIDED_NAV_FILE")" phase)" = "confirm" ]
  [ "$(cat "$GUIDED_PWPENDING_FILE")" = "hunter2" ]
  [ -z "$(cat "$GUIDED_PWBUF_FILE")" ]            # buffer cleared for the retype
}

@test "enter(secret confirm): a match writes the root password + backs out" {
  secret_setup
  printf 'hunter2' > "$GUIDED_PWPENDING_FILE"
  printf 'hunter2' > "$GUIDED_PWBUF_FILE"
  set_nav "$(nav_to_secret Users root "" confirm)"
  run guided_ctl_enter ""
  [ "$output" = "render" ]
  [ "$(jq -r '.root_password' "$GUIDED_SECRETS_FILE")" = "hunter2" ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "values" ]
  [ -z "$(cat "$GUIDED_PWBUF_FILE")" ]
}

@test "enter(secret confirm): a mismatch re-prompts and writes nothing" {
  secret_setup
  printf 'hunter2' > "$GUIDED_PWPENDING_FILE"
  printf 'huntor2' > "$GUIDED_PWBUF_FILE"
  set_nav "$(nav_to_secret Users root "" confirm)"
  run guided_ctl_enter ""
  [ "$output" = "secret-mismatch" ]
  [ "$(nav_get "$(<"$GUIDED_NAV_FILE")" phase)" = "entry" ]
  [ "$(jq -r '.root_password // "unset"' "$GUIDED_SECRETS_FILE")" = "unset" ]
}

@test "enter(secret entry): an empty password is refused" {
  secret_setup
  : > "$GUIDED_PWBUF_FILE"
  set_nav "$(nav_to_secret Users root "" entry)"
  run guided_ctl_enter ""
  [[ "$output" == notice* ]]
  [ "$(nav_get "$(<"$GUIDED_NAV_FILE")" phase)" = "entry" ]
}

@test "secret flow (user): a confirmed match writes that user's password" {
  secret_setup; export GUIDED_RICH_CHROME=1
  printf '%s\n' '{"users":["dave"]}' > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_values Users users users)"
  run guided_ctl_enter "      password (dave): (not set)"
  [ "$(nav_get "$(<"$GUIDED_NAV_FILE")" target)" = "user" ]
  [ "$(nav_get "$(<"$GUIDED_NAV_FILE")" user)" = "dave" ]
  printf 'davepw' > "$GUIDED_PWBUF_FILE"
  guided_ctl_enter "" >/dev/null                 # entry → confirm
  printf 'davepw' > "$GUIDED_PWBUF_FILE"
  guided_ctl_enter "" >/dev/null                 # confirm → save
  [ "$(jq -r '.users.dave.password' "$GUIDED_SECRETS_FILE")" = "davepw" ]
}

# ── Encryption Editor + collapsed Disks row (ADR 0059) ───────────────────────

@test "list(Disks): the Encryption row reads off + no legacy rows when off" {
  export GUIDED_SECRETS_FILE="$TEST_DIR/secrets.json"
  printf '{}\n' > "$GUIDED_SECRETS_FILE"
  set_nav "$(nav_to_category Disks)"
  run guided_ctl_list
  echo "$output" | grep -qx "Encryption ▸ off"
  ! echo "$output" | grep -qE "^Encryption: "        # no generic bool row
  ! echo "$output" | grep -q "encryption password:"  # no old sub-row
}

@test "list(Disks): the Encryption row shows on · default when on + unset" {
  export GUIDED_SECRETS_FILE="$TEST_DIR/secrets.json"; printf '{}\n' > "$GUIDED_SECRETS_FILE"
  printf '%s\n' '{"options":{"encryption":true}}' > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_category Disks)"
  run guided_ctl_list
  echo "$output" | grep -q "Encryption ▸ on · default 12345678"
  ! echo "$output" | grep -q "⚠"                     # no gate warning anymore
}

@test "list(Disks): the Encryption row carries the override dot when on" {
  export GUIDED_SECRETS_FILE="$TEST_DIR/secrets.json"; printf '{}\n' > "$GUIDED_SECRETS_FILE"
  printf '%s\n' '{"options":{"encryption":true}}' > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_category Disks)"
  run guided_ctl_list
  echo "$output" | grep -qE "Encryption ▸ on · default 12345678  ●$"
}

@test "list(Disks): the Encryption row reads on · custom once captured" {
  export GUIDED_SECRETS_FILE="$TEST_DIR/secrets.json"
  printf '%s\n' '{"enc_passphrase":"corrhorse"}' > "$GUIDED_SECRETS_FILE"
  printf '%s\n' '{"options":{"encryption":true}}' > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_category Disks)"
  run guided_ctl_list
  echo "$output" | grep -q "Encryption ▸ on · custom"
}

@test "enter(Disks): the Encryption row opens the Encryption Editor" {
  set_nav "$(nav_to_category Disks)"
  run guided_ctl_enter "Encryption ▸ on · default 12345678"
  [ "$output" = "render" ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "encryption" ]
  [ "$(nav_get "$(<"$GUIDED_NAV_FILE")" category)" = "Disks" ]
}

@test "list(encryption): off shows only the enabled row + Back" {
  printf '%s\n' '{"options":{"encryption":false}}' > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_encryption Disks)"
  run guided_ctl_list
  echo "$output" | grep -qx "enabled: off"
  ! echo "$output" | grep -q "password:"
  echo "$output" | grep -q "← Back"
}

@test "list(encryption): on shows enabled + password + Back" {
  export GUIDED_SECRETS_FILE="$TEST_DIR/secrets.json"; printf '{}\n' > "$GUIDED_SECRETS_FILE"
  printf '%s\n' '{"options":{"encryption":true}}' > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_encryption Disks)"
  run guided_ctl_list
  echo "$output" | grep -qx "enabled: on"
  echo "$output" | grep -qx "password: default 12345678"
}

@test "enter(encryption): enabled toggles in place and stays on the editor" {
  _seed_baseline                                 # so the strict-delta normalise
  set_nav "$(nav_to_encryption Disks)"           # has the default to compare to
  run guided_ctl_enter "enabled: off"
  [ "$output" = "refresh" ]
  [ "$(jq -r '.options.encryption' "$GUIDED_STATE_FILE")" = "true" ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "encryption" ]
  # toggling back to the baseline drops the override (strict delta)
  run guided_ctl_enter "enabled: on"
  [ "$output" = "refresh" ]
  [ "$(jq 'getpath(["options","encryption"]) == null' "$GUIDED_STATE_FILE")" = "true" ]
}

@test "enter(encryption): password opens the inline capture (rich chrome)" {
  secret_setup; export GUIDED_RICH_CHROME=1
  printf '%s\n' '{"options":{"encryption":true}}' > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_encryption Disks)"
  run guided_ctl_enter "password: default 12345678"
  [ "$output" = "render" ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "secret" ]
  [ "$(nav_get "$(<"$GUIDED_NAV_FILE")" target)" = "enc" ]
}

@test "enter(encryption): password falls back to execute() (legacy)" {
  secret_setup; unset GUIDED_RICH_CHROME
  printf '%s\n' '{"options":{"encryption":true}}' > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_encryption Disks)"
  [ "$(guided_ctl_enter "password: default 12345678")" = "secret-enc" ]
}

@test "enter(secret entry enc): a passphrase under 8 chars is refused" {
  secret_setup
  printf 'short7x' > "$GUIDED_PWBUF_FILE"        # 7 chars
  set_nav "$(nav_to_secret Disks enc "" entry)"
  run guided_ctl_enter ""
  [[ "$output" == notice* ]]
  [ "$(nav_get "$(<"$GUIDED_NAV_FILE")" phase)" = "entry" ]
  [ -z "$(cat "$GUIDED_PWPENDING_FILE")" ]        # nothing stashed
}

@test "enter(secret entry enc): 8+ chars advances to confirm" {
  secret_setup
  printf 'eightchr' > "$GUIDED_PWBUF_FILE"        # 8 chars
  set_nav "$(nav_to_secret Disks enc "" entry)"
  run guided_ctl_enter ""
  [ "$output" = "render" ]
  [ "$(nav_get "$(<"$GUIDED_NAV_FILE")" phase)" = "confirm" ]
  [ "$(cat "$GUIDED_PWPENDING_FILE")" = "eightchr" ]
}

@test "secret flow (enc): confirmed passphrase writes enc + returns to the Editor" {
  secret_setup; export GUIDED_RICH_CHROME=1
  printf '%s\n' '{"options":{"encryption":true}}' > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_encryption Disks)"
  run guided_ctl_enter "password: default 12345678"
  [ "$(nav_get "$(<"$GUIDED_NAV_FILE")" target)" = "enc" ]
  printf 'corrhorse' > "$GUIDED_PWBUF_FILE"
  guided_ctl_enter "" >/dev/null                  # entry → confirm
  printf 'corrhorse' > "$GUIDED_PWBUF_FILE"
  guided_ctl_enter "" >/dev/null                  # confirm → save
  [ "$(jq -r '.enc_passphrase' "$GUIDED_SECRETS_FILE")" = "corrhorse" ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "encryption" ]
}

@test "enter(encryption): setting a passphrase leaves enabled unchanged" {
  secret_setup; export GUIDED_RICH_CHROME=1
  printf '%s\n' '{"options":{"encryption":true}}' > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_encryption Disks)"
  guided_ctl_enter "password: default 12345678" >/dev/null
  printf 'corrhorse' > "$GUIDED_PWBUF_FILE"; guided_ctl_enter "" >/dev/null
  printf 'corrhorse' > "$GUIDED_PWBUF_FILE"; guided_ctl_enter "" >/dev/null
  [ "$(jq -r '.options.encryption' "$GUIDED_STATE_FILE")" = "true" ]
}

@test "encryption editor: a stored passphrase survives an off→on toggle" {
  secret_setup
  printf '%s\n' '{"enc_passphrase":"corrhorse"}' > "$GUIDED_SECRETS_FILE"
  printf '%s\n' '{"options":{"encryption":true}}' > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_encryption Disks)"
  guided_ctl_enter "enabled: on"  >/dev/null   # → off (baseline: override dropped)
  guided_ctl_enter "enabled: off" >/dev/null   # → on again
  run guided_ctl_list
  echo "$output" | grep -qx "password: custom"    # retained, not cleared
}

@test "back(encryption): Esc returns to the Disks category" {
  set_nav "$(nav_to_encryption Disks)"
  run guided_ctl_back
  [ "$output" = "render" ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "category" ]
  [ "$(nav_get "$(<"$GUIDED_NAV_FILE")" category)" = "Disks" ]
}

@test "directive→action: secret-enc executes the masked capture verb" {
  local a; a="$(_guided_directive_to_action secret-enc /e)"
  [[ "$a" == *"secret enc"* ]]
}

@test "mask entry: the fzf mask subcommand masks + captures the buffer" {
  export GUIDED_PWBUF_FILE="$TEST_DIR/pwbuf2"; printf 'ab' > "$GUIDED_PWBUF_FILE"
  # query is 2 bullets + a newly typed 'c'
  run bash "$BATS_TEST_DIRNAME/../../lib/guided-fzf-entry.sh" mask "••c"
  [ "$output" = "•••" ]                           # display: 3 bullets
  [ "$(cat "$GUIDED_PWBUF_FILE")" = "abc" ]       # buffer captured the real char
}
