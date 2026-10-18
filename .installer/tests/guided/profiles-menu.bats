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

  source "$BATS_TEST_DIRNAME/../../lib/config/config-state.sh"
  source "$BATS_TEST_DIRNAME/../../lib/config/navigation.sh"
  source "$BATS_TEST_DIRNAME/../../lib/config/edit.sh"
  source "$BATS_TEST_DIRNAME/../../lib/config/menu.sh"
  source "$BATS_TEST_DIRNAME/../../lib/guided/controller.sh"

  printf '%s\n' '{}' > "$GUIDED_STATE_FILE"
  printf '%s\n' '{}' > "$GUIDED_BASELINE_FILE"
  printf '%s\n' '{"screen":"top"}' > "$GUIDED_NAV_FILE"

  # A fixture hosts/ tree with two installable profiles (+ excluded core).
  export INSTALLER_DIR="$TEST_DIR/os"
  mkdir -p "$INSTALLER_DIR/hosts"/{core,desktop,laptop}
  printf '{}\n' > "$INSTALLER_DIR/hosts/core/profile.jsonc"
  cat > "$INSTALLER_DIR/hosts/desktop/profile.jsonc" <<'JSONC'
// Encrypted, impermanent ZFS desktop.
{ "system": { "hostname": "eterniox" },
  "options": { "encryption": true }, "filesystem": "zfs" }
JSONC
  # laptop: no header comment (exercises the dim fallback).
  printf '{ "system": { "hostname": "chronos" } }\n' \
    > "$INSTALLER_DIR/hosts/laptop/profile.jsonc"
}
teardown() { rm -rf "$TEST_DIR"; }

set_navigation() { printf '%s\n' "$1" > "$GUIDED_NAV_FILE"; }

# ── top screen: the Profiles row leads, set off by its own divider ──────────

@test "list(top): a Profiles row leads when installable profiles exist" {
  run guided_controller_list
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "Profiles ▸ start from a saved machine" ]
  [ "${lines[1]}" = "──────────────────────────" ]
  echo "$output" | grep -q "System — "      # categories still follow
  echo "$output" | grep -q "Proceed ▸"
}

@test "list(top): the Profiles row shows even when the hosts tree has none" {
  # ADR 0063: the picker is unconditional — it leads with the reset row, so it is
  # always a first-class entry point, even on a fresh repo with no profiles.
  rm -rf "$INSTALLER_DIR/hosts/desktop" "$INSTALLER_DIR/hosts/laptop"
  run guided_controller_list
  echo "$output" | grep -q "Profiles ▸"
}

@test "enter(top): the Profiles row drills to the profiles screen" {
  run guided_controller_enter "Profiles ▸ start from a saved machine"
  [ "$output" = "render" ]
  [ "$(navigation_screen "$(<"$GUIDED_NAV_FILE")")" = "profiles" ]
}

# ── profiles screen: lists the installable profiles + Back ──────────────────

@test "list(profiles): Reset row leads, then desktop + laptop, then Back" {
  set_navigation '{"screen":"profiles"}'
  run guided_controller_list
  [ "${lines[0]}" = "↺ Reset to blank" ]   # ADR 0063: leads the picker
  [ "${lines[1]}" = "desktop" ]
  [ "${lines[2]}" = "laptop" ]
  echo "$output" | grep -q "← Back"
  ! echo "$output" | grep -qx core
}

@test "list(profiles): a fresh repo shows only the Reset row + Back" {
  rm -rf "$INSTALLER_DIR/hosts/desktop" "$INSTALLER_DIR/hosts/laptop"
  set_navigation '{"screen":"profiles"}'
  run guided_controller_list
  [ "${lines[0]}" = "↺ Reset to blank" ]
  echo "$output" | grep -q "← Back"
}

@test "back(profiles): Esc/Back returns to the top screen" {
  set_navigation '{"screen":"profiles"}'
  run guided_controller_enter "← Back"
  [ "$output" = "render" ]
  [ "$(navigation_screen "$(<"$GUIDED_NAV_FILE")")" = "top" ]
}

# ── preview pane: a deep tree of the resolved machine (ADR 0063) ─────────────

@test "preview(profiles): shows a deep tree of the resolved machine" {
  set_navigation '{"screen":"profiles"}'
  run guided_controller_preview desktop
  echo "$output" | grep -q "eterniox"             # hostname (resolved)
  echo "$output" | grep -q "encryption: on"       # options incl. encryption
  echo "$output" | grep -q "impermanence"         # …and impermanence
  echo "$output" | grep -q "environment"          # environment node
  echo "$output" | grep -q "security"             # security node
  echo "$output" | grep -q "backup"               # backup node
  echo "$output" | grep -q "disks"                # disk skeleton node
}

@test "preview(profiles): expands a user to shell·groups" {
  local installer_directory; installer_directory="$TEST_DIR/os4"
  mkdir -p "$installer_directory/hosts"/{core,box} "$installer_directory/users"/{core,alice}
  printf '{}\n' > "$installer_directory/hosts/core/profile.jsonc"
  printf '{}\n' > "$installer_directory/users/core/profile.jsonc"
  printf '{"system":{"hostname":"box"},"users":["alice"]}\n' \
    > "$installer_directory/hosts/box/profile.jsonc"
  printf '{"shell":"/bin/fish","groups":["wheel","docker"]}\n' \
    > "$installer_directory/users/alice/profile.jsonc"
  export INSTALLER_DIR="$installer_directory"
  set_navigation '{"screen":"profiles"}'
  run guided_controller_preview box
  echo "$output" | grep -q "alice"
  echo "$output" | grep -q "/bin/fish"
  echo "$output" | grep -q "wheel"
}

@test "preview(profiles): resolves over Host Core, not the raw delta" {
  local installer_directory; installer_directory="$TEST_DIR/os5"
  mkdir -p "$installer_directory/hosts"/{core,box}
  printf '{"options":{"bootloader":"grub"}}\n' > "$installer_directory/hosts/core/profile.jsonc"
  printf '{"system":{"hostname":"box"}}\n' > "$installer_directory/hosts/box/profile.jsonc"
  export INSTALLER_DIR="$installer_directory"
  set_navigation '{"screen":"profiles"}'
  run guided_controller_preview box
  echo "$output" | grep -q "bootloader: grub"     # inherited from Host Core
}

# The preview shows what the pick installs: a fleet host folds the Fleet Layer
# (ADR 0157), exactly as the pick and `install.sh --profile` do.
@test "preview(profiles): a fleet host previews its Fleet Layer too" {
  local installer_directory; installer_directory="$TEST_DIR/os6"
  mkdir -p "$installer_directory/hosts"/{core,fleet,box}
  printf '{}\n' > "$installer_directory/hosts/core/profile.jsonc"
  printf '{"options":{"bootloader":"grub"}}\n' \
    > "$installer_directory/hosts/fleet/profile.jsonc"
  printf '{"fleet":true}\n' > "$installer_directory/hosts/box/profile.jsonc"
  export INSTALLER_DIR="$installer_directory"
  set_navigation '{"screen":"profiles"}'
  run guided_controller_preview box
  echo "$output" | grep -q "bootloader: grub"     # from the Fleet Layer
}

@test "preview(profiles): rows stay clean — only the name (no inline hint)" {
  set_navigation '{"screen":"profiles"}'
  run guided_controller_list
  echo "$output" | grep -qx "desktop"             # name only, no hostname hint
}

@test "preview(profiles): Back + Reset row preview nothing" {
  set_navigation '{"screen":"profiles"}'
  run guided_controller_preview "← Back"
  [ -z "$output" ]
  run guided_controller_preview "↺ Reset to blank"
  [ -z "$output" ]
}

# ── ↺ Reset to blank: confirm-gated, undoable full session reset (ADR 0063) ──

@test "enter(profiles): Reset row drills to the confirm screen" {
  set_navigation '{"screen":"profiles"}'
  run guided_controller_enter "↺ Reset to blank"
  [ "$output" = "render" ]
  [ "$(navigation_screen "$(<"$GUIDED_NAV_FILE")")" = "newhost" ]
}

@test "enter(newhost): Back cancels to the picker, session intact" {
  printf '%s\n' '{"users":["alice"]}' > "$GUIDED_STATE_FILE"
  set_navigation '{"screen":"newhost"}'
  run guided_controller_enter "← Back"
  [ "$output" = "render" ]
  [ "$(navigation_screen "$(<"$GUIDED_NAV_FILE")")" = "profiles" ]
  jq -e '.users == ["alice"]' "$GUIDED_STATE_FILE"      # untouched
}

@test "enter(newhost): confirm resets Config State + clears session side-state" {
  # Wire the full session: an override, a session user's editor form, a secret,
  # an in-menu disk binding — plus the undo stack + the reset-undo stash file.
  export GUIDED_HIST_FILE="$TEST_DIR/hist.json"
  export GUIDED_USERFORMS_FILE="$TEST_DIR/userforms.json"
  export GUIDED_SECRETS_FILE="$TEST_DIR/secrets.json"
  export GUIDED_SESSION_UNDO_FILE="$TEST_DIR/undo.json"
  source "$BATS_TEST_DIRNAME/../../lib/config/history.sh"

  printf '%s\n' '{"users":["alice"],"os_pool":{"devices":["/dev/x"]}}' \
    > "$GUIDED_STATE_FILE"
  printf '%s\n' '{"alice":{"shell":"/bin/fish"}}' > "$GUIDED_USERFORMS_FILE"
  printf '%s\n' '{"users":{"alice":{"password":"p"}}}' > "$GUIDED_SECRETS_FILE"
  history_new "$(<"$GUIDED_STATE_FILE")" > "$GUIDED_HIST_FILE"

  set_navigation '{"screen":"newhost"}'
  run guided_controller_enter "Yes — discard session work and start blank"
  [ "$output" = "render" ]
  [ "$(navigation_screen "$(<"$GUIDED_NAV_FILE")")" = "top" ]
  jq -e '. == {}' "$GUIDED_STATE_FILE"                  # Config State → baseline
  jq -e '. == {}' "$GUIDED_USERFORMS_FILE"              # editor forms cleared
  jq -e '. == {}' "$GUIDED_SECRETS_FILE"                # secret overrides cleared
}

@test "enter(newhost): the reset is undoable — a single undo restores it" {
  export GUIDED_HIST_FILE="$TEST_DIR/hist.json"
  export GUIDED_USERFORMS_FILE="$TEST_DIR/userforms.json"
  export GUIDED_SECRETS_FILE="$TEST_DIR/secrets.json"
  export GUIDED_SESSION_UNDO_FILE="$TEST_DIR/undo.json"
  source "$BATS_TEST_DIRNAME/../../lib/config/history.sh"

  printf '%s\n' '{"users":["alice"]}' > "$GUIDED_STATE_FILE"
  printf '%s\n' '{"alice":{"shell":"/bin/fish"}}' > "$GUIDED_USERFORMS_FILE"
  printf '%s\n' '{"users":{"alice":{"password":"p"}}}' > "$GUIDED_SECRETS_FILE"
  history_new "$(<"$GUIDED_STATE_FILE")" > "$GUIDED_HIST_FILE"

  set_navigation '{"screen":"newhost"}'
  guided_controller_enter "Yes — discard session work and start blank" >/dev/null

  run guided_controller_key ctrl-z
  [ "$output" = "render" ]
  jq -e '.users == ["alice"]' "$GUIDED_STATE_FILE"      # Config State restored
  jq -e '.alice.shell == "/bin/fish"' "$GUIDED_USERFORMS_FILE"  # forms restored
  jq -e '.users.alice.password == "p"' "$GUIDED_SECRETS_FILE"   # secrets restored
}

# ── pick re-baselines: the chosen profile IS the session (ADR 0157) ──────────

@test "enter(profiles): picking a profile re-baselines + returns to top" {
  printf '%s\n' '{"system":{"keymap":"de"}}' > "$GUIDED_STATE_FILE"
  set_navigation '{"screen":"profiles"}'
  run guided_controller_enter desktop
  [ "$output" = "render" ]
  [ "$(navigation_screen "$(<"$GUIDED_NAV_FILE")")" = "top" ]
  jq -e '.system.hostname == "eterniox"' "$GUIDED_BASELINE_FILE"
  jq -e '.options.encryption == true' "$GUIDED_BASELINE_FILE"
  jq -e '.filesystem == "zfs"' "$GUIDED_BASELINE_FILE"
  jq -e '. == {}' "$GUIDED_STATE_FILE"         # no ● — earlier edit dropped
}

@test "enter(profiles): a profile with no hostname is named after itself" {
  printf '{ "options": { "encryption": false } }\n' \
    > "$INSTALLER_DIR/hosts/laptop/profile.jsonc"
  set_navigation '{"screen":"profiles"}'
  guided_controller_enter laptop >/dev/null
  jq -e '.system.hostname == "laptop"' "$GUIDED_BASELINE_FILE"
}

@test "enter(profiles): a later pick leaves no residue of an earlier one" {
  set_navigation '{"screen":"profiles"}'
  guided_controller_enter desktop >/dev/null
  set_navigation '{"screen":"profiles"}'
  guided_controller_enter laptop >/dev/null
  jq -e '.system.hostname == "chronos"' "$GUIDED_BASELINE_FILE"
  jq -e '.options.encryption == false' "$GUIDED_BASELINE_FILE" # default, not desktop's
}

@test "enter(profiles): the pick is undoable — undo restores the baseline" {
  export GUIDED_HIST_FILE="$TEST_DIR/hist.json"
  export GUIDED_SESSION_UNDO_FILE="$TEST_DIR/undo.json"
  source "$BATS_TEST_DIRNAME/../../lib/config/history.sh"
  printf '%s\n' '{"marker":1}' > "$GUIDED_BASELINE_FILE"
  printf '%s\n' '{"users":["alice"]}' > "$GUIDED_STATE_FILE"
  history_new "$(<"$GUIDED_STATE_FILE")" > "$GUIDED_HIST_FILE"
  set_navigation '{"screen":"profiles"}'
  guided_controller_enter desktop >/dev/null

  guided_controller_key ctrl-z >/dev/null
  jq -e '. == {"marker":1}' "$GUIDED_BASELINE_FILE"
  jq -e '.users == ["alice"]' "$GUIDED_STATE_FILE"
}

@test "enter(profiles): an unreadable profile warns without touching state" {
  printf '%s\n' '{"seed":"me"}' > "$GUIDED_STATE_FILE"
  set_navigation '{"screen":"profiles"}'
  run guided_controller_enter ghost
  [[ "$output" == notice* ]]
  jq -e '.seed == "me"' "$GUIDED_STATE_FILE"                 # untouched
}

# The baseline a pick installs is the profile resolved by the Profile Loader
# (Host Core + delta), exactly as `install.sh --profile` resolves it.
@test "a picked profile matches profile_loader_load exactly" {
  local installer_directory; installer_directory="$TEST_DIR/os3"
  mkdir -p "$installer_directory/hosts"/{core,desktop}
  cat > "$installer_directory/hosts/core/profile.jsonc" <<'JSON'
{"host_programs":["cups"],"packages":{"repo":{"shell":["htop"]}}}
JSON
  cat > "$installer_directory/hosts/desktop/profile.jsonc" <<'JSON'
{"host_programs":["grub"],"options":{"kernel":["zen"]}}
JSON
  export INSTALLER_DIR="$installer_directory"

  set_navigation "$(navigation_to_profiles)"
  guided_controller_enter "desktop" >/dev/null

  source "$BATS_TEST_DIRNAME/../../lib/config/profile-loader.sh"
  local picked resolved
  picked="$(jq -cS '{host_programs, packages, kernel: .options.kernel}' \
    "$GUIDED_BASELINE_FILE")"
  resolved="$(profile_loader_load desktop \
    | jq -cS '{host_programs, packages, kernel: .options.kernel}')"
  [ "$picked" = "$resolved" ]
}

@test "a profile opting out of Host Core packages carries none" {
  local installer_directory; installer_directory="$TEST_DIR/os4"
  mkdir -p "$installer_directory/hosts"/{core,bare}
  printf '%s\n' '{"packages":{"repo":{"shell":["htop"]}}}' \
    > "$installer_directory/hosts/core/profile.jsonc"
  printf '%s\n' '{"packages":{"inherit":false}}' \
    > "$installer_directory/hosts/bare/profile.jsonc"
  export INSTALLER_DIR="$installer_directory"
  printf '%s\n' '{"packages":{"repo":{"shell":["htop"]}}}' \
    > "$GUIDED_BASELINE_FILE"

  set_navigation "$(navigation_to_profiles)"
  guided_controller_enter "bare" >/dev/null
  jq -e '.packages == null' "$GUIDED_BASELINE_FILE"
}

# ── Proceed needs a user: a blank session presets none (ADR 0157) ───────────

@test "enter(top): Proceed with no user is refused with a notice" {
  printf '%s\n' '{}' > "$GUIDED_BASELINE_FILE"
  printf '%s\n' '{}' > "$GUIDED_STATE_FILE"
  run guided_controller_enter "Proceed ▸ review & install"
  [[ "$output" == "notice No user"* ]]
}

@test "enter(top): Proceed with a user goes to the terminal action" {
  printf '%s\n' '{"users":["alice"]}' > "$GUIDED_STATE_FILE"
  run guided_controller_enter "Proceed ▸ review & install"
  [ "$output" = "terminal proceed" ]
}
