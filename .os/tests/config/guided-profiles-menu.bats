#!/usr/bin/env bats
# Tests for the Guided Installer's in-menu Profiles picker (ADR 0055) — the menu
# MODEL: the top-screen row, the drill screen's list, the header-comment preview,
# and the seed-on-pick. Pure: state/nav files in, rows / directives / state out,
# no fzf. Behaviour under test only. Prior art: guided-controller.bats.

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

  # A fixture hosts/ tree with two installable profiles (+ excluded core).
  export OS_DIR="$TEST_DIR/os"
  mkdir -p "$OS_DIR/hosts"/{core,desktop,laptop}
  printf '{}\n' > "$OS_DIR/hosts/core/profile.jsonc"
  cat > "$OS_DIR/hosts/desktop/profile.jsonc" <<'JSONC'
// Encrypted, impermanent ZFS desktop.
{ "system": { "hostname": "eterniox" },
  "options": { "encryption": true }, "filesystem": "zfs" }
JSONC
  # laptop: no header comment (exercises the dim fallback).
  printf '{ "system": { "hostname": "chronos" } }\n' \
    > "$OS_DIR/hosts/laptop/profile.jsonc"
}
teardown() { rm -rf "$TEST_DIR"; }

set_nav() { printf '%s\n' "$1" > "$GUIDED_NAV_FILE"; }

# ── top screen: the Profiles row leads, set off by its own divider ──────────

@test "list(top): a Profiles row leads when installable profiles exist" {
  run guided_ctl_list
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "Profiles ▸ start from a saved machine" ]
  [ "${lines[1]}" = "──────────────────────────" ]
  echo "$output" | grep -q "Host — "        # categories still follow
  echo "$output" | grep -q "Proceed ▸"
}

@test "list(top): no Profiles row when the hosts tree has none" {
  rm -rf "$OS_DIR/hosts/desktop" "$OS_DIR/hosts/laptop"
  run guided_ctl_list
  ! echo "$output" | grep -q "Profiles ▸"
}

@test "enter(top): the Profiles row drills to the profiles screen" {
  run guided_ctl_enter "Profiles ▸ start from a saved machine"
  [ "$output" = "render" ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "profiles" ]
}

# ── profiles screen: lists the installable profiles + Back ──────────────────

@test "list(profiles): lists desktop + laptop, alphabetical, then Back" {
  set_nav '{"screen":"profiles"}'
  run guided_ctl_list
  [ "${lines[0]}" = "desktop" ]
  [ "${lines[1]}" = "laptop" ]
  echo "$output" | grep -q "← Back"
  ! echo "$output" | grep -qx core
}

@test "back(profiles): Esc/Back returns to the top screen" {
  set_nav '{"screen":"profiles"}'
  run guided_ctl_enter "← Back"
  [ "$output" = "render" ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "top" ]
}

# ── preview pane: the header comment, with the dim fallback ──────────────────

@test "preview(profiles): shows the profile's header comment" {
  set_nav '{"screen":"profiles"}'
  run guided_ctl_preview desktop
  echo "$output" | grep -q "Encrypted, impermanent ZFS desktop."
}

@test "preview(profiles): a header-less profile shows the dim fallback" {
  set_nav '{"screen":"profiles"}'
  run guided_ctl_preview laptop
  echo "$output" | grep -q "no description — hosts/laptop/profile.jsonc"
}

@test "preview(profiles): Back previews nothing" {
  set_nav '{"screen":"profiles"}'
  run guided_ctl_preview "← Back"
  [ -z "$output" ]
}

# ── seed-on-pick: the chosen profile populates the Config State ──────────────

@test "enter(profiles): picking a profile seeds the state + returns to top" {
  set_nav '{"screen":"profiles"}'
  run guided_ctl_enter desktop
  [ "$output" = "render" ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "top" ]
  jq -e '.system.hostname == "eterniox"' "$GUIDED_STATE_FILE"
  jq -e '.options.encryption == true' "$GUIDED_STATE_FILE"
  jq -e '.filesystem == "zfs"' "$GUIDED_STATE_FILE"
}

@test "enter(profiles): a prior edit survives unless the profile overrides it" {
  printf '%s\n' '{"system":{"keymap":"de"}}' > "$GUIDED_STATE_FILE"
  set_nav '{"screen":"profiles"}'
  guided_ctl_enter desktop >/dev/null
  jq -e '.system.keymap == "de"' "$GUIDED_STATE_FILE"        # kept
  jq -e '.system.hostname == "eterniox"' "$GUIDED_STATE_FILE" # merged
}

@test "enter(profiles): an unreadable profile warns without touching state" {
  printf '%s\n' '{"seed":"me"}' > "$GUIDED_STATE_FILE"
  set_nav '{"screen":"profiles"}'
  run guided_ctl_enter ghost
  [[ "$output" == notice* ]]
  jq -e '.seed == "me"' "$GUIDED_STATE_FILE"                 # untouched
}
