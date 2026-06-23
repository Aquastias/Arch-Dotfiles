#!/usr/bin/env bats
# Tests for .os/lib/config/seed.sh — the Guided Installer's default seeder
# (guided-installer-redesign issue 01 / M3): a pure helper that fills a launch
# Config State with this operator's computed defaults, so an untouched run is
# ready to install. Pure: a Config State in, the seeded state out, no TTY.
#
# Behaviour under test (external only — the seeded state the helper produces),
# never internal structure. Prior art: tests/config/guided-state.bats.

setup() {
  error() { echo "[error] $*" >&2; return 1; }
  export -f error

  # shellcheck source=../../lib/config/state.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/state.sh"
  # shellcheck source=../../lib/config/seed.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/seed.sh"
}

# ── tracer: the seeded launch state carries the default hostname ────────────

@test "cfgstate_seed_defaults: seeds hostname eterniox" {
  run cfgstate_seed_defaults "$(cfgstate_new)"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.system.hostname == "eterniox"'
}

# ── the Primary User is seeded explicitly (so the host is never userless) ────

@test "cfgstate_seed_defaults: seeds aquastias as the Primary User" {
  run cfgstate_seed_defaults "$(cfgstate_new)"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.users == ["aquastias"]'
}

# ── the common case needs no decision: single-disk layout by default ────────

@test "cfgstate_seed_defaults: seeds the single-disk layout" {
  run cfgstate_seed_defaults "$(cfgstate_new)"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.mode == "single"'
}

# ── locale / timezone / keymap default to this operator's values ────────────
# (back-end-required identity; surfaced as editable Host rows over these seeds.)

@test "cfgstate_seed_defaults: seeds locale, timezone and keymap" {
  run cfgstate_seed_defaults "$(cfgstate_new)"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.system.locale == "en_US.UTF-8"'
  echo "$output" | jq -e '.system.timezone == "Europe/Bucharest"'
  echo "$output" | jq -e '.system.keymap == "us"'
}

# ── the secure baseline is pre-ticked: firewalld + all tools on (ADR 0041) ──

@test "cfgstate_seed_defaults: seeds vm.swappiness=10 (Host Core default)" {
  run cfgstate_seed_defaults "$(cfgstate_new)"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.sysctl["vm.swappiness"] == 10'
}

@test "cfgstate_seed_defaults: seeds selection defaults (no field opens empty)" {
  run cfgstate_seed_defaults "$(cfgstate_new)"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.options.kernel == ["lts"]'
  echo "$output" | jq -e '.environment.gpu == "auto"'
  echo "$output" | jq -e '.environment.desktop == ["kde","hyprland"]'
  echo "$output" | jq -e '(.options.mirror_countries | length) == 5'
}

@test "cfgstate_seed_defaults: seeds the secure Security/Backup baseline" {
  run cfgstate_seed_defaults "$(cfgstate_new)"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.post_install.security.firewall == "firewalld"'
  echo "$output" | jq -e '.post_install.security.antivirus == true'
  echo "$output" | jq -e '.post_install.security.rootkit == true'
  echo "$output" | jq -e '.post_install.security.apparmor == true'
  echo "$output" | jq -e '.post_install.backup.zfs_auto_snapshot == true'
  echo "$output" | jq -e '.post_install.backup.borg == true'
}
