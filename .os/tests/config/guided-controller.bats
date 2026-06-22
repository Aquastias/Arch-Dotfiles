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
  run guided_ctl_enter "Disks — filesystem, encryption, swap, ESP"
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
  echo "$output" | grep -q "Disk layout ▸"
  echo "$output" | grep -q "← Back"
}

@test "enter(category): an enum field opens the value picker" {
  set_nav "$(nav_to_category Disks)"
  run guided_ctl_enter "encryption: false"
  [ "$output" = "render" ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "values" ]
  [ "$(nav_get "$(<"$GUIDED_NAV_FILE")" field)" = "options.encryption" ]
}

@test "enter(category): a text field routes to edit-oneshot" {
  set_nav "$(nav_to_category Host)"
  run guided_ctl_enter "hostname: "
  [ "$output" = "edit-oneshot system.hostname" ]
}

@test "enter(category): a multi field routes to edit-oneshot" {
  set_nav "$(nav_to_category Options)"
  run guided_ctl_enter "kernel: lts"
  [ "$output" = "edit-oneshot options.kernel" ]
}

@test "enter(category): Disk layout routes to edit-oneshot __layout__" {
  set_nav "$(nav_to_category Disks)"
  run guided_ctl_enter "Disk layout ▸ choose preset"
  [ "$output" = "edit-oneshot __layout__" ]
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
