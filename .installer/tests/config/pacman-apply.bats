#!/usr/bin/env bats
# Tests for apply_pacman_options in .installer/lib/packages/list.sh — the authoritative
# Pacman Options apply step (ADR 0074). Seam 2: run it against a fixture
# `[options]` block and assert the resulting file. External behaviour only (the
# file contents), never internals.

setup() {
  TEST_DIR="$(mktemp -d)"
  export CONFIG_FILE="$TEST_DIR/install.jsonc"
  CONF="$TEST_DIR/pacman.conf"

  info()    { :; }
  warn()    { :; }
  error()   { echo "[error] $*" >&2; return 1; }
  section() { :; }
  export -f info warn error section

  # shellcheck source=../../lib/config/accessors.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/accessors.sh"
  # shellcheck source=../../lib/packages/list.sh
  source "$BATS_TEST_DIRNAME/../../lib/packages/list.sh"

  # A realistic Arch [options] block followed by two repo sections.
  cat > "$CONF" <<'EOF'
[options]
#RootDir     = /
HoldPkg     = pacman glibc
#Color
#NoProgressBar
CheckSpace
#VerbosePkgLists
ParallelDownloads = 5
SigLevel    = Required DatabaseOptional
LocalFileSigLevel = Optional

[core]
Include = /etc/pacman.d/mirrorlist

[extra]
Include = /etc/pacman.d/mirrorlist
EOF
}

teardown() { rm -rf "$TEST_DIR"; }

write_cfg() { printf '%s\n' "$1" > "$CONFIG_FILE"; }

# ── defaults: on flags uncommented/appended, off flags left commented ────────

@test "apply: defaults enable Color/Verbose/ILoveCandy, keep NoProgressBar off" {
  write_cfg '{}'
  run apply_pacman_options "$CONF"
  [ "$status" -eq 0 ]
  grep -qx 'Color' "$CONF"
  grep -qx 'VerbosePkgLists' "$CONF"
  grep -qx 'ILoveCandy' "$CONF"           # not shipped → appended
  grep -qx 'ParallelDownloads = 5' "$CONF"
  grep -qx '#NoProgressBar' "$CONF"       # default off → stays commented
  ! grep -qx 'NoProgressBar' "$CONF"
  ! grep -q 'DisableDownloadTimeout' "$CONF"  # off + absent → never added
}

# ── untouched: SigLevel, includes, CheckSpace, repo sections stay verbatim ───

@test "apply: leaves SigLevel, Include, CheckSpace and repo sections untouched" {
  write_cfg '{}'
  run apply_pacman_options "$CONF"
  [ "$status" -eq 0 ]
  grep -qxF 'SigLevel    = Required DatabaseOptional' "$CONF"
  grep -qxF 'CheckSpace' "$CONF"          # owned by disable_checkspace, not us
  grep -qxF '[core]' "$CONF"
  [ "$(grep -cF 'Include = /etc/pacman.d/mirrorlist' "$CONF")" -eq 2 ]
}

# ── off toggles are authoritative: a shipped-on flag gets commented out ───────

@test "apply: color=false comments Color, ilovecandy=false drops ILoveCandy" {
  write_cfg '{"options":{"pacman":{"color":false,"ilovecandy":false}}}'
  run apply_pacman_options "$CONF"
  [ "$status" -eq 0 ]
  grep -qx '#Color' "$CONF"
  ! grep -qx 'Color' "$CONF"
  ! grep -qx 'ILoveCandy' "$CONF"
}

@test "apply: no_progress_bar=true uncomments the shipped #NoProgressBar" {
  write_cfg '{"options":{"pacman":{"no_progress_bar":true}}}'
  run apply_pacman_options "$CONF"
  [ "$status" -eq 0 ]
  grep -qx 'NoProgressBar' "$CONF"
  ! grep -qx '#NoProgressBar' "$CONF"
}

# ── the numeric value is set to the operator's choice ────────────────────────

@test "apply: parallel_downloads=10 sets ParallelDownloads = 10" {
  write_cfg '{"options":{"pacman":{"parallel_downloads":10}}}'
  run apply_pacman_options "$CONF"
  [ "$status" -eq 0 ]
  grep -qx 'ParallelDownloads = 10' "$CONF"
  ! grep -qx 'ParallelDownloads = 5' "$CONF"
}

# ── DisableDownloadTimeout on appends the flag ───────────────────────────────

@test "apply: disable_download_timeout=true adds the flag" {
  write_cfg '{"options":{"pacman":{"disable_download_timeout":true}}}'
  run apply_pacman_options "$CONF"
  [ "$status" -eq 0 ]
  grep -qx 'DisableDownloadTimeout' "$CONF"
}

# ── idempotent: a second run converges to the same file ──────────────────────

@test "apply: running twice yields an identical file" {
  write_cfg '{"options":{"pacman":{"color":true,"ilovecandy":true,
    "no_progress_bar":false,"parallel_downloads":8}}}'
  apply_pacman_options "$CONF"
  cp "$CONF" "$TEST_DIR/after-first"
  apply_pacman_options "$CONF"
  diff "$TEST_DIR/after-first" "$CONF"
}

# ── a missing conf is a no-op, not a failure ─────────────────────────────────

@test "apply: a missing pacman.conf is a no-op" {
  write_cfg '{}'
  run apply_pacman_options "$TEST_DIR/does-not-exist.conf"
  [ "$status" -eq 0 ]
}
