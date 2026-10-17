#!/usr/bin/env bats
# Tests for .installer/lib/config/config-state.sh — the Guided Installer's default
# seeder
# (guided-installer-redesign issue 01 / M3): a pure helper that fills a launch
# Config State with this operator's computed defaults, so an untouched run is
# ready to install. Pure: a Config State in, the seeded state out, no TTY.
#
# Behaviour under test (external only — the seeded state the helper produces),
# never internal structure. Prior art: tests/config/guided-state.bats.

setup() {
  error() { echo "[error] $*" >&2; return 1; }
  export -f error

  # The baseline is LOADED from Host Core now (ADR 0058), so the seeder needs
  # an INSTALLER_DIR to read. A representative core: one System Program, a
  # sysctl
  # default, and a package list — the three things that used to be invisible
  # in the menu because they were hand-copied or not copied at all.
  TEST_DIR="$(mktemp -d)"
  export INSTALLER_DIR="$TEST_DIR"
  mkdir -p "$INSTALLER_DIR/hosts/core"
  cat > "$INSTALLER_DIR/hosts/core/profile.jsonc" <<'JSON'
{"users":[],"host_programs":["cups"],"sysctl":{"vm.swappiness":10},
 "packages":{"repo":{"shell":["htop"]},"aur":{"misc":["brave-bin"]}}}
JSON

  # shellcheck source=../../lib/config/config-state.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/config-state.sh"
}

# assert_extras_off <config> — no Security & Backup Extra is on (absent or off).
assert_extras_off() {
  jq -e '(.post_install.security.firewall // "none") == "none"
    and ([.post_install // {} | .. | booleans | select(.)] | length) == 0' \
    <<<"$1" >/dev/null
}

teardown() { rm -rf "$TEST_DIR"; }

# ── tracer: the seeded launch state carries the default hostname ────────────

@test "config_state_seed_defaults: seeds the neutral hostname archlinux" {
  run config_state_seed_defaults "$(config_state_new)"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.system.hostname == "archlinux"'
}

# ── no user is preset: the operator picks or creates one (ADR 0157) ─────────

@test "config_state_seed_defaults: presets no user" {
  run config_state_seed_defaults "$(config_state_new)"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '(.users // []) == []'
}

# ── the common case needs no decision: single-disk layout by default ────────

@test "config_state_seed_defaults: seeds the single-disk layout" {
  run config_state_seed_defaults "$(config_state_new)"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.mode == "single"'
}

# ── locale / keymap seed; the timezone is autodetected at install (ADR 0118) ─

@test "config_state_seed_defaults: seeds locale and keymap, no timezone" {
  run config_state_seed_defaults "$(config_state_new)"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.system.locale == "en_US.UTF-8"'
  echo "$output" | jq -e '.system.timezone == null'
  echo "$output" | jq -e '.system.keymap == "us"'
}

# ── Host Core is loaded, not hand-copied (ADR 0058) ─────────────────────────
# `cups` installs on every host and used to appear nowhere in the menu, because
# the seeder hand-copied a few core values rather than loading core.

@test "config_state_seed_defaults: seeds vm.swappiness=10 from Host Core" {
  run config_state_seed_defaults "$(config_state_new)"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.sysctl["vm.swappiness"] == 10'
}

@test "config_state_seed_defaults: Host Core's system programs surface" {
  run config_state_seed_defaults "$(config_state_new)"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.host_programs == ["cups"]'
}

@test "config_state_seed_defaults: Host Core's packages surface" {
  run config_state_seed_defaults "$(config_state_new)"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.packages.repo.shell == ["htop"]'
  echo "$output" | jq -e '.packages.aur.misc == ["brave-bin"]'
}

# The ordered selections still replace whatever core declared — the baseline
# fold is the Layer Resolver, not a blanket concat.
@test "config_state_seed_defaults: a core kernel does not concat with the default" {
  cat > "$INSTALLER_DIR/hosts/core/profile.jsonc" <<'JSON'
{"options":{"kernel":["zen"]}}
JSON
  run config_state_seed_defaults "$(config_state_new)"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.options.kernel == ["lts"]'
}

@test "config_state_seed_defaults: with no Host Core it still seeds the defaults" {
  rm -rf "$INSTALLER_DIR/hosts"
  run config_state_seed_defaults "$(config_state_new)"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.system.hostname == "archlinux"'
}

@test "config_state_seed_defaults: seeds selection defaults (no field opens empty)" {
  run config_state_seed_defaults "$(config_state_new)"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.options.kernel == ["lts"]'
  echo "$output" | jq -e '.environment.gpu == "auto"'
  echo "$output" | jq -e '.environment.desktop == []'   # none (ADR 0157)
  echo "$output" | jq -e '.options.mirror_countries == null'  # worldwide
}

@test "config_state_seed_defaults: pre-ticks no Security/Backup extra" {
  run config_state_seed_defaults "$(config_state_new)"
  [ "$status" -eq 0 ]
  assert_extras_off "$output"   # all off (ADR 0157)
}

# ── Guided Launch Presets never shadow an Install Default (ADR 0154) ────────

@test "seed: no launch preset sits on a field with an Install Default" {
  local owned preset
  owned="$(install_config_default_object $(install_config_schema_names) \
    | jq -r 'paths(scalars or (type == "array")) | join(".")')"
  preset="$(_config_state_preset_defaults '{}' \
    | jq -r '[paths(scalars or (type == "array"))]
             | map(select(.[-1] | type == "string")) | .[] | join(".")')"
  while IFS= read -r path; do
    grep -qx "$path" <<<"$owned" \
      && { echo "preset shadows an Install Default: $path"; return 1; }
  done <<<"$preset"
  return 0
}
