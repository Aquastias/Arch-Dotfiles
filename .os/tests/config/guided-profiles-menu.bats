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

@test "list(top): the Profiles row shows even when the hosts tree has none" {
  # ADR 0063: the picker is unconditional — it leads with `+ New host`, so it is
  # always a first-class entry point, even on a fresh repo with no profiles.
  rm -rf "$OS_DIR/hosts/desktop" "$OS_DIR/hosts/laptop"
  run guided_ctl_list
  echo "$output" | grep -q "Profiles ▸"
}

@test "enter(top): the Profiles row drills to the profiles screen" {
  run guided_ctl_enter "Profiles ▸ start from a saved machine"
  [ "$output" = "render" ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "profiles" ]
}

# ── profiles screen: lists the installable profiles + Back ──────────────────

@test "list(profiles): New host leads, then desktop + laptop, then Back" {
  set_nav '{"screen":"profiles"}'
  run guided_ctl_list
  [ "${lines[0]}" = "+ New host (start blank)" ]   # ADR 0063: leads the picker
  [ "${lines[1]}" = "desktop" ]
  [ "${lines[2]}" = "laptop" ]
  echo "$output" | grep -q "← Back"
  ! echo "$output" | grep -qx core
}

@test "list(profiles): a fresh repo shows only New host + Back" {
  rm -rf "$OS_DIR/hosts/desktop" "$OS_DIR/hosts/laptop"
  set_nav '{"screen":"profiles"}'
  run guided_ctl_list
  [ "${lines[0]}" = "+ New host (start blank)" ]
  echo "$output" | grep -q "← Back"
}

@test "back(profiles): Esc/Back returns to the top screen" {
  set_nav '{"screen":"profiles"}'
  run guided_ctl_enter "← Back"
  [ "$output" = "render" ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "top" ]
}

# ── preview pane: a deep tree of the resolved machine (ADR 0063) ─────────────

@test "preview(profiles): shows a deep tree of the resolved machine" {
  set_nav '{"screen":"profiles"}'
  run guided_ctl_preview desktop
  echo "$output" | grep -q "eterniox"             # hostname (resolved)
  echo "$output" | grep -q "encryption: on"       # options incl. encryption
  echo "$output" | grep -q "impermanence"         # …and impermanence
  echo "$output" | grep -q "environment"          # environment node
  echo "$output" | grep -q "security"             # security node
  echo "$output" | grep -q "backup"               # backup node
  echo "$output" | grep -q "disks"                # disk skeleton node
}

@test "preview(profiles): expands a user to shell·groups" {
  local d; d="$TEST_DIR/os4"
  mkdir -p "$d/hosts"/{core,box} "$d/users"/{core,alice}
  printf '{}\n' > "$d/hosts/core/profile.jsonc"
  printf '{}\n' > "$d/users/core/profile.jsonc"
  printf '{"system":{"hostname":"box"},"users":["alice"]}\n' \
    > "$d/hosts/box/profile.jsonc"
  printf '{"shell":"/bin/fish","groups":["wheel","docker"]}\n' \
    > "$d/users/alice/profile.jsonc"
  export OS_DIR="$d"
  set_nav '{"screen":"profiles"}'
  run guided_ctl_preview box
  echo "$output" | grep -q "alice"
  echo "$output" | grep -q "/bin/fish"
  echo "$output" | grep -q "wheel"
}

@test "preview(profiles): resolves over Host Core, not the raw delta" {
  local d; d="$TEST_DIR/os5"
  mkdir -p "$d/hosts"/{core,box}
  printf '{"options":{"bootloader":"grub"}}\n' > "$d/hosts/core/profile.jsonc"
  printf '{"system":{"hostname":"box"}}\n' > "$d/hosts/box/profile.jsonc"
  export OS_DIR="$d"
  set_nav '{"screen":"profiles"}'
  run guided_ctl_preview box
  echo "$output" | grep -q "bootloader: grub"     # inherited from Host Core
}

@test "preview(profiles): rows stay clean — only the name (no inline hint)" {
  set_nav '{"screen":"profiles"}'
  run guided_ctl_list
  echo "$output" | grep -qx "desktop"             # name only, no hostname hint
}

@test "preview(profiles): Back + New host preview nothing" {
  set_nav '{"screen":"profiles"}'
  run guided_ctl_preview "← Back"
  [ -z "$output" ]
  run guided_ctl_preview "+ New host (start blank)"
  [ -z "$output" ]
}

# ── + New host: confirm-gated, undoable full session reset (ADR 0063) ────────

@test "enter(profiles): New host drills to the confirm screen" {
  set_nav '{"screen":"profiles"}'
  run guided_ctl_enter "+ New host (start blank)"
  [ "$output" = "render" ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "newhost" ]
}

@test "enter(newhost): Back cancels to the picker, session intact" {
  printf '%s\n' '{"users":["alice"]}' > "$GUIDED_STATE_FILE"
  set_nav '{"screen":"newhost"}'
  run guided_ctl_enter "← Back"
  [ "$output" = "render" ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "profiles" ]
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
  hist_new "$(<"$GUIDED_STATE_FILE")" > "$GUIDED_HIST_FILE"

  set_nav '{"screen":"newhost"}'
  run guided_ctl_enter "Yes — discard session work and start blank"
  [ "$output" = "render" ]
  [ "$(nav_screen "$(<"$GUIDED_NAV_FILE")")" = "top" ]
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
  hist_new "$(<"$GUIDED_STATE_FILE")" > "$GUIDED_HIST_FILE"

  set_nav '{"screen":"newhost"}'
  guided_ctl_enter "Yes — discard session work and start blank" >/dev/null

  run guided_ctl_key ctrl-z
  [ "$output" = "render" ]
  jq -e '.users == ["alice"]' "$GUIDED_STATE_FILE"      # Config State restored
  jq -e '.alice.shell == "/bin/fish"' "$GUIDED_USERFORMS_FILE"  # forms restored
  jq -e '.users.alice.password == "p"' "$GUIDED_SECRETS_FILE"   # secrets restored
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

# ── seeding a profile must match what --profile installs (ADR 0058) ─────────
# A committed profile is a DELTA over Host Core, and Config State is an
# override map that REPLACES baseline values. Seeding the raw delta therefore
# showed (and installed) only the delta, where `install.sh --profile <name>`
# resolves core+delta. The picker resolves before seeding so one profile
# produces one install through every front-end.

@test "seeding resolves the profile over Host Core, not the raw delta" {
  local d; d="$TEST_DIR/os2"
  mkdir -p "$d/hosts"/{core,desktop}
  cat > "$d/hosts/core/profile.jsonc" <<'JSON'
{"system_programs":["cups"],
 "packages":{"repo":{"shell":["htop"]}},"sysctl":{"vm.swappiness":10}}
JSON
  cat > "$d/hosts/desktop/profile.jsonc" <<'JSON'
{"system_programs":["grub"],"packages":{"repo":{"virt":["qemu-full"]}}}
JSON
  export OS_DIR="$d"
  printf '%s\n' '{}' > "$GUIDED_STATE_FILE"

  set_nav "$(nav_to_profiles)"
  run guided_ctl_enter "desktop"
  [ "$status" -eq 0 ]

  # the seeded state carries core's contribution as well as the delta
  jq -e '.system_programs == ["cups","grub"]' "$GUIDED_STATE_FILE"
  jq -e '.packages.repo.shell == ["htop"]'    "$GUIDED_STATE_FILE"
  jq -e '.packages.repo.virt == ["qemu-full"]' "$GUIDED_STATE_FILE"
  jq -e '.sysctl["vm.swappiness"] == 10'      "$GUIDED_STATE_FILE"
}

@test "a seeded profile matches load_profile exactly" {
  local d; d="$TEST_DIR/os3"
  mkdir -p "$d/hosts"/{core,desktop}
  cat > "$d/hosts/core/profile.jsonc" <<'JSON'
{"system_programs":["cups"],"packages":{"repo":{"shell":["htop"]}}}
JSON
  cat > "$d/hosts/desktop/profile.jsonc" <<'JSON'
{"system_programs":["grub"],"options":{"kernel":["zen"]}}
JSON
  export OS_DIR="$d"
  printf '%s\n' '{}' > "$GUIDED_STATE_FILE"

  set_nav "$(nav_to_profiles)"
  guided_ctl_enter "desktop" >/dev/null

  source "$BATS_TEST_DIRNAME/../../lib/config/profile.sh"
  local seeded resolved
  seeded="$(jq -cS '{system_programs, packages, options}' "$GUIDED_STATE_FILE")"
  resolved="$(load_profile desktop \
    | jq -cS '{system_programs, packages, options}')"
  [ "$seeded" = "$resolved" ]
}
