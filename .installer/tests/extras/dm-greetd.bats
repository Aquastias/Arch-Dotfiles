#!/usr/bin/env bats
# Tests for extras/dm/greetd/greetd.sh — the greetd Display Manager Adapter.
#
# Strategy: run the adapter as a subprocess with pacman and systemctl stubbed
# as executables in a temp bin dir prepended to PATH; config writes redirected
# to a temp ROOT. Injectable seams: GREETD_CONF_DIR, WAYLAND_SESSIONS_DIR, ROOT.

setup() {
  TEST_DIR="$(mktemp -d)"
  STUB_BIN="$TEST_DIR/bin"
  ROOT="$TEST_DIR/root"
  mkdir -p "$STUB_BIN" "$ROOT"

  PACMAN_LOG="$TEST_DIR/pacman.log"
  SYSTEMCTL_LOG="$TEST_DIR/systemctl.log"
  GREETD_CONF_DIR="/etc/greetd"
  WAYLAND_SESSIONS_DIR="/usr/local/share/wayland-sessions"
  ADAPTER="$BATS_TEST_DIRNAME/../../extras/dm/greetd/greetd.sh"

  export PACMAN_LOG SYSTEMCTL_LOG GREETD_CONF_DIR WAYLAND_SESSIONS_DIR ROOT

  printf '#!/usr/bin/env bash\necho "pacman $*" >> "$PACMAN_LOG"\n' \
    > "$STUB_BIN/pacman"
  printf '#!/usr/bin/env bash\necho "systemctl $*" >> "$SYSTEMCTL_LOG"\n' \
    > "$STUB_BIN/systemctl"
  chmod +x "$STUB_BIN/pacman" "$STUB_BIN/systemctl"

  export PATH="$STUB_BIN:$PATH"
  CONF="$ROOT$GREETD_CONF_DIR/config.toml"
}

teardown() { rm -rf "$TEST_DIR"; }

@test "installs greetd and greetd-tuigreet" {
  run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  grep -q "greetd" "$PACMAN_LOG"
  grep -q "greetd-tuigreet" "$PACMAN_LOG"
}

@test "enables the greetd service" {
  run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  grep -qx "systemctl enable greetd" "$SYSTEMCTL_LOG"
}

@test "writes a greetd config.toml with a tuigreet default_session" {
  run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  [ -f "$CONF" ]
  grep -q "tuigreet" "$CONF"
  grep -q 'user = "greeter"' "$CONF"
}

@test "points tuigreet at the curated dir when it exists" {
  mkdir -p "$ROOT$WAYLAND_SESSIONS_DIR"
  run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  grep -q -- "--sessions $WAYLAND_SESSIONS_DIR" "$CONF"
}

@test "falls back to /usr/share when the curated dir is absent" {
  # No curated dir (no Hyprland adapter ran — e.g. KDE-only greetd).
  run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  grep -q -- "--sessions /usr/share/wayland-sessions" "$CONF"
}
