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
  echo "$output" | grep -q "filesystem: zfs"
  echo "$output" | grep -q "encryption: false"
  echo "$output" | grep -q "layout: single"   # reflects the default
  echo "$output" | grep -q "← Back"
}

@test "list(category Disks): the Disk layout row reflects the chosen preset" {
  printf '%s\n' "$(nav_to_values Disks __layout__ "layout")" \
    > "$GUIDED_NAV_FILE"
  guided_ctl_enter "os-mirror" >/dev/null    # apply the preset
  set_nav "$(nav_to_category Disks)"
  run guided_ctl_list
  echo "$output" | grep -q "layout: OS: 2 disks (mirror)"
  echo "$output" | grep -q "●"               # overridden marker
}

@test "enter(category): an enum field opens the value picker" {
  set_nav "$(nav_to_category Disks)"
  run guided_ctl_enter "encryption: false"
  [ "$output" = "render" ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "values" ]
  [ "$(nav_get "$(<"$GUIDED_NAV_FILE")" field)" = "options.encryption" ]
}

@test "enter(category): a text field opens the native query-line editor" {
  set_nav "$(nav_to_category Host)"
  run guided_ctl_enter "hostname: "
  [ "$output" = "render" ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "text" ]
  [ "$(nav_get "$(<"$GUIDED_NAV_FILE")" field)" = "system.hostname" ]
}

@test "enter(category): a toggle field opens the multi-select picker" {
  set_nav "$(nav_to_category Options)"
  run guided_ctl_enter "kernel: lts"
  [ "$output" = "render" ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "values" ]
  [ "$(nav_get "$(<"$GUIDED_NAV_FILE")" field)" = "options.kernel" ]
}

@test "list(category Packages): empty list fields render as [] not blank" {
  set_nav "$(nav_to_category Packages)"
  run guided_ctl_list
  echo "$output" | grep -q "extra packages: \[\]"
  echo "$output" | grep -q "system programs: \[\]"
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
  echo "$output" | grep -q "\[x\] lts"
  echo "$output" | grep -q "\[ \] zen"
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
  [ "$output" = "reload-sync(bash /x/entry.sh list)" ]
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

@test "key: a no-op without a history file" {
  unset GUIDED_HIST_FILE
  run guided_ctl_key ctrl-z
  [ "$output" = "noop" ]
}

@test "enter(category): Disk layout opens the native preset picker" {
  set_nav "$(nav_to_category Disks)"
  run guided_ctl_enter "layout: single"
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
  echo "$output" | grep -q "grub"
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

@test "enter(values): a reserved filesystem is a no-op but still returns" {
  set_nav "$(nav_to_values Disks filesystem filesystem)"
  run guided_ctl_enter "btrfs (reserved)"
  [ "$output" = "render" ]
  [ "$(jq -c '.filesystem // "unset"' "$GUIDED_STATE_FILE")" = '"unset"' ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "category" ]
}

@test "enter(values): zfs commits the filesystem" {
  set_nav "$(nav_to_values Disks filesystem filesystem)"
  run guided_ctl_enter "zfs"
  [ "$(jq -r '.filesystem' "$GUIDED_STATE_FILE")" = "zfs" ]
}

@test "enter(values): Back leaves the value unchanged" {
  set_nav "$(nav_to_values Disks options.encryption encryption)"
  run guided_ctl_enter "← Back"
  [ "$output" = "render" ]
  [ "$(jq -c '. == {}' "$GUIDED_STATE_FILE")" = "true" ]
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

@test "enter(values __layout__): picking a preset applies the skeleton" {
  set_nav "$(nav_to_values Disks __layout__ "layout")"
  run guided_ctl_enter "os-mirror"
  [ "$output" = "render" ]
  [ "$(jq -c '. != {}' "$GUIDED_STATE_FILE")" = "true" ]   # a skeleton landed
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "category" ]
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

@test "directive→action(render): layout shows the preview, others hide it" {
  set_nav "$(nav_to_values Disks __layout__ "layout")"
  run _guided_directive_to_action render /x/entry.sh
  echo "$output" | grep -q "change-preview(bash /x/entry.sh preview {})"
  echo "$output" | grep -q "change-preview-window(right,45%)"
  set_nav "$(nav_to_category Disks)"
  run _guided_directive_to_action render /x/entry.sh
  echo "$output" | grep -q "change-preview-window(hidden)"
}

# ── data-pools editor: multiple pools (tank0/tank1), topology, disk count ─────

@test "list(category Disks): shows the data pools row" {
  set_nav "$(nav_to_category Disks)"
  run guided_ctl_list
  echo "$output" | grep -q "data pools: none"
}

@test "enter(category): data pools opens the editor" {
  set_nav "$(nav_to_category Disks)"
  run guided_ctl_enter "data pools: none"
  [ "$output" = "render" ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "datapools" ]
}

@test "enter(datapools): + Add appends tank0 (mirror ×2) and forces multi" {
  set_nav "$(nav_to_datapools Disks)"
  run guided_ctl_enter "+ Add data pool"
  [ "$output" = "refresh" ]
  [ "$(jq -r '.data_pools[0].name' "$GUIDED_STATE_FILE")" = "tank0" ]
  [ "$(jq -r '.data_pools[0].topology' "$GUIDED_STATE_FILE")" = "mirror" ]
  [ "$(jq -r '.data_pools[0].disk_count' "$GUIDED_STATE_FILE")" = "2" ]
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

# ── keymap / locale / timezone: big filterable lists + a "selected" side panel ─

@test "enter(category): keymap opens a big filterable list (values screen)" {
  set_nav "$(nav_to_category Host)"
  run guided_ctl_enter "keymap: us"
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
  run guided_ctl_enter "sysctl: "
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
  run guided_ctl_enter "users: "
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
  echo "$output" | grep -q "\[x\] alice"
  echo "$output" | grep -q "\[ \] bob"
  ! echo "$output" | grep -q "core"
  echo "$output" | grep -q "+ Create user"
}

@test "enter(values users): toggling a user flips membership (full override)" {
  printf '%s\n' '{"users":["alice","bob"]}' > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_values Users users users)"
  run guided_ctl_enter "[x] bob"
  [ "$output" = "refresh" ]
  [ "$(jq -c '.users' "$GUIDED_STATE_FILE")" = '["alice"]' ]
}

@test "enter(values users): toggling the last user off yields an empty list" {
  printf '%s\n' '{"users":["alice"]}' > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_values Users users users)"
  run guided_ctl_enter "[x] alice"
  [ "$(jq -c '.users' "$GUIDED_STATE_FILE")" = '[]' ]   # set [], not unset
}

@test "enter(values users): + Create opens the new-user text editor" {
  set_nav "$(nav_to_values Users users users)"
  run guided_ctl_enter "+ Create user (name)"
  [ "$output" = "render" ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "text" ]
  [ "$(nav_get "$(<"$GUIDED_NAV_FILE")" field)" = "__newuser__" ]
}

@test "enter(text __newuser__): a typed name is added + returns to the user list" {
  printf '%s\n' '{"users":["alice"]}' > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_text Users __newuser__ "new user")"
  run guided_ctl_enter "+ Create user (name)" "carol"
  [ "$(jq -c '.users' "$GUIDED_STATE_FILE")" = '["alice","carol"]' ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "values" ]
  [ "$(nav_get "$(<"$GUIDED_NAV_FILE")" field)" = "users" ]
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
