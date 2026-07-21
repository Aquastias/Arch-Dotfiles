#!/usr/bin/env bats
# Tests for rich chrome + the legacy version gate — issue 06 (ADR 0047). Actions
# (Back/Add/remove/create) move off the lists onto keybindings (^A/^X/Esc); rich
# chrome adds a change-footer (context + summary), a change-list-label breadcrumb,
# and a change-header nav line, gated on fzf ≥ 0.62. Below that, legacy action
# rows stay in the lists and no footer/breadcrumb is emitted. Controller +
# directive seams, no fzf, no tty.

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

  DP='{"mode":"multi","os_pool":{"topology":"none","disk_count":1},
       "data_pools":[{"name":"tank0","topology":"mirror","disk_count":2}]}'
}
teardown() { rm -rf "$TEST_DIR"; }

set_nav() { printf '%s\n' "$1" > "$GUIDED_NAV_FILE"; }

# ── version gate (pure) — AC3 ────────────────────────────────────────────────

@test "_ctl_fzf_rich_for_version: 0.62.0 is rich" {
  run _ctl_fzf_rich_for_version "0.62.0 (abc)"
  [ "$status" -eq 0 ]
}

@test "_ctl_fzf_rich_for_version: 0.61.0 is legacy" {
  run _ctl_fzf_rich_for_version "0.61.0 (abc)"
  [ "$status" -ne 0 ]
}

@test "_ctl_fzf_rich_for_version: 0.36.0 is legacy" {
  run _ctl_fzf_rich_for_version "0.36.0"
  [ "$status" -ne 0 ]
}

@test "_ctl_fzf_rich_for_version: 0.65.1 and 1.0.0 are rich" {
  run _ctl_fzf_rich_for_version "0.65.1"; [ "$status" -eq 0 ]
  run _ctl_fzf_rich_for_version "1.0.0";  [ "$status" -eq 0 ]
}

@test "_ctl_detect_rich_chrome: reads fzf --version off PATH, prints 1/0" {
  # stub fzf ≥ 0.62 on PATH
  printf '#!/usr/bin/env bash\necho "0.62.0 (stub)"\n' > "$TEST_DIR/fzf"
  chmod +x "$TEST_DIR/fzf"
  PATH="$TEST_DIR:$PATH" run _ctl_detect_rich_chrome
  [ "$output" = "1" ]
  printf '#!/usr/bin/env bash\necho "0.50.0 (stub)"\n' > "$TEST_DIR/fzf"
  PATH="$TEST_DIR:$PATH" run _ctl_detect_rich_chrome
  [ "$output" = "0" ]
}

@test "_ctl_rich_chrome: rc 0 only when GUIDED_RICH_CHROME=1" {
  GUIDED_RICH_CHROME=1 run _ctl_rich_chrome; [ "$status" -eq 0 ]
  GUIDED_RICH_CHROME=0 run _ctl_rich_chrome; [ "$status" -ne 0 ]
  run _ctl_rich_chrome; [ "$status" -ne 0 ]        # unset → legacy default
}

# ── rich mode: lists hold only data (AC1) ────────────────────────────────────

@test "list(datapools) rich: add row stays visible, other action rows drop" {
  printf '%s\n' "$DP" > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_datapools Disks)"
  GUIDED_RICH_CHROME=1 run guided_ctl_list
  echo "$output" | grep -q "tank0: mirror ×2"
  # "+ Add data pool" is the exception: it is the primary way to build the pool
  # list, so it stays visible even in rich chrome (footer-only ^A undiscoverable).
  echo "$output" | grep -q "+ Add data pool"
  ! echo "$output" | grep -q "← Back"
}

@test "list(pooledit data) rich: no remove/back rows, data rows stay" {
  printf '%s\n' "$DP" > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_pooledit Disks 0 data)"
  GUIDED_RICH_CHROME=1 run guided_ctl_list
  echo "$output" | grep -q "topology: mirror"
  ! echo "$output" | grep -q "remove"
  ! echo "$output" | grep -q "← Back"
}

# ── legacy mode: action rows stay (AC4) ──────────────────────────────────────

@test "list(datapools) legacy: action rows remain" {
  printf '%s\n' "$DP" > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_datapools Disks)"
  run guided_ctl_list
  echo "$output" | grep -q "+ Add data pool"
  echo "$output" | grep -q "← Back"
}

# ── ^A / ^X action dispatch (AC1) ────────────────────────────────────────────

@test "action add: on datapools appends a pool" {
  printf '%s\n' "$DP" > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_datapools Disks)"
  run guided_ctl_action add
  [ "$output" = "refresh" ]
  [ "$(jq '.data_pools | length' "$GUIDED_STATE_FILE")" = "2" ]
}

@test "action remove: on a data pool editor deletes it and returns to the list" {
  printf '%s\n' "$DP" > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_pooledit Disks 0 data)"
  run guided_ctl_action remove
  [ "$output" = "render" ]
  [ "$(jq -c '.data_pools' "$GUIDED_STATE_FILE")" = "[]" ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "datapools" ]
}

@test "action add-storage: on datapools appends a storage group (^S)" {
  printf '%s\n' "$DP" > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_datapools Disks)"
  run guided_ctl_action add-storage
  [ "$output" = "refresh" ]
  [ "$(jq -r '.storage_groups[0].name' "$GUIDED_STATE_FILE")" = "data" ]
  [ "$(jq -r '.storage_groups[0].mount' "$GUIDED_STATE_FILE")" = "/data" ]
}

@test "action remove: ^X on a highlighted data pool row deletes it in place" {
  printf '%s\n' "$DP" > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_datapools Disks)"
  run guided_ctl_action remove "tank0: mirror ×2"
  [ "$output" = "refresh" ]
  [ "$(jq -c '.data_pools' "$GUIDED_STATE_FILE")" = "[]" ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "datapools" ]
}

@test "action remove: ^X on a highlighted storage row deletes it in place" {
  printf '%s\n' \
    '{"storage_groups":[{"name":"data","mount":"/data","topology":"raidz1","disk_count":3}]}' \
    > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_datapools Disks)"
  run guided_ctl_action remove "data (storage): raidz1 ×3"
  [ "$output" = "refresh" ]
  [ "$(jq -c '.storage_groups' "$GUIDED_STATE_FILE")" = "[]" ]
}

@test "action remove: ^X on the OS pool row is a noop" {
  printf '%s\n' "$DP" > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_datapools Disks)"
  run guided_ctl_action remove "OS pool: none ×1"
  [ "$output" = "noop" ]
  [ "$(jq -r '.os_pool.topology' "$GUIDED_STATE_FILE")" = "none" ]
}

@test "action add: on the sysctl list opens the add-text screen" {
  set_nav "$(nav_to_values Options sysctl sysctl)"
  run guided_ctl_action add
  [ "$output" = "render" ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "text" ]
  [ "$(nav_get "$(<"$GUIDED_NAV_FILE")" field)" = "sysctl" ]
}

@test "action remove: on the OS pool editor is a noop (not removable)" {
  printf '%s\n' "$DP" > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_pooledit Disks 0 os)"
  run guided_ctl_action remove
  [ "$output" = "noop" ]
}

# ── render action string carries chrome (AC2) ────────────────────────────────

@test "directive→action(render) rich: carries footer, breadcrumb, header" {
  printf '%s\n' "$DP" > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_datapools Disks)"
  GUIDED_RICH_CHROME=1 run _guided_directive_to_action render /x/entry.sh
  echo "$output" | grep -q "change-footer("
  echo "$output" | grep -q "change-list-label("
  echo "$output" | grep -q "change-header("
  echo "$output" | grep -q "Disks"          # breadcrumb names the category
}

@test "directive→action(render) legacy: no footer or breadcrumb" {
  set_nav "$(nav_to_datapools Disks)"
  run _guided_directive_to_action render /x/entry.sh
  ! echo "$output" | grep -q "change-footer("
  ! echo "$output" | grep -q "change-list-label("
  echo "$output" | grep -q "change-header("   # header stays in both modes
}

@test "directive→action(refresh) rich: re-emits the live footer summary" {
  printf '%s\n' "$DP" > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_pooledit Disks 0 data)"
  GUIDED_RICH_CHROME=1 run _guided_directive_to_action refresh /x/entry.sh
  echo "$output" | grep -q "reload-sync(bash"
  echo "$output" | grep -q "change-footer("
}

@test "directive→action(refresh) legacy: no footer emitted" {
  set_nav "$(nav_to_datapools Disks)"
  run _guided_directive_to_action refresh /x/entry.sh
  echo "$output" | grep -q "reload-sync(bash"
  ! echo "$output" | grep -q "change-footer("
}

# ── breadcrumb + footer builders (pure) ──────────────────────────────────────

@test "_ctl_breadcrumb: pooledit names category ▸ layout ▸ pool" {
  printf '%s\n' "$DP" > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_pooledit Disks 0 data)"
  run _ctl_breadcrumb "$(<"$GUIDED_NAV_FILE")"
  echo "$output" | grep -q "Disks"
  echo "$output" | grep -q "tank0"
}

@test "_ctl_footer: datapools footer mentions the add key" {
  printf '%s\n' "$DP" > "$GUIDED_STATE_FILE"
  set_nav "$(nav_to_datapools Disks)"
  run _ctl_footer "$(<"$GUIDED_NAV_FILE")"
  echo "$output" | grep -q "\^A"
}
