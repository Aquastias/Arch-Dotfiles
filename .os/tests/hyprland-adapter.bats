#!/usr/bin/env bats
# Tests for extras/desktop/hyprland/hyprland.sh.
#
# Strategy: run the adapter as a subprocess with pacman and systemctl stubbed
# as executables in a temp bin dir prepended to PATH. Injectable seams:
#   HYPR_JSON      — path to install-hyprland.jsonc
#   GREETD_CONF_DIR — directory where greetd/config.toml is written

setup() {
  TEST_DIR="$(mktemp -d)"
  STUB_BIN="$TEST_DIR/bin"
  mkdir -p "$STUB_BIN"

  PACMAN_LOG="$TEST_DIR/pacman.log"
  SYSTEMCTL_LOG="$TEST_DIR/systemctl.log"
  GREETD_CONF_DIR="$TEST_DIR/greetd"
  HYPR_JSON="$TEST_DIR/install-hyprland.jsonc"
  ADAPTER="$BATS_TEST_DIRNAME/../extras/desktop/hyprland/hyprland.sh"

  export PACMAN_LOG SYSTEMCTL_LOG GREETD_CONF_DIR HYPR_JSON

  printf '#!/usr/bin/env bash\necho "pacman $*" >> "$PACMAN_LOG"\n' > "$STUB_BIN/pacman"
  printf '#!/usr/bin/env bash\necho "systemctl $*" >> "$SYSTEMCTL_LOG"\n' > "$STUB_BIN/systemctl"
  chmod +x "$STUB_BIN/pacman" "$STUB_BIN/systemctl"

  export PATH="$STUB_BIN:$PATH"

  # Default: all companions enabled
  printf '{"bar":true,"notifications":true,"launcher":true,"rofi":true,"terminal":true,"lock":true,"idle":true,"wallpaper":true}' \
    > "$HYPR_JSON"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# ── core packages ─────────────────────────────────────────────────────────

@test "hyprland and portal packages always installed" {
  run env ENVIRONMENT_DESKTOP="hyprland" bash "$ADAPTER"
  [ "$status" -eq 0 ]
  grep -q "hyprland" "$PACMAN_LOG"
  grep -q "xdg-desktop-portal-hyprland" "$PACMAN_LOG"
  grep -q "polkit-kde-agent" "$PACMAN_LOG"
}

# ── display manager ───────────────────────────────────────────────────────

@test "greetd installed and enabled when only hyprland" {
  run env ENVIRONMENT_DESKTOP="hyprland" bash "$ADAPTER"
  [ "$status" -eq 0 ]
  grep -q "greetd" "$PACMAN_LOG"
  grep -q "greetd-tuigreet" "$PACMAN_LOG"
  grep -q "systemctl enable greetd" "$SYSTEMCTL_LOG"
}

@test "greetd config.toml written when only hyprland" {
  run env ENVIRONMENT_DESKTOP="hyprland" bash "$ADAPTER"
  [ "$status" -eq 0 ]
  [ -f "${GREETD_CONF_DIR}/config.toml" ]
  grep -q "tuigreet" "${GREETD_CONF_DIR}/config.toml"
}

@test "greetd not installed when kde also in ENVIRONMENT_DESKTOP" {
  run env ENVIRONMENT_DESKTOP="kde hyprland" bash "$ADAPTER"
  [ "$status" -eq 0 ]
  ! grep -q "greetd" "$PACMAN_LOG"
}

# ── companion toggles ─────────────────────────────────────────────────────

@test "disabled companion not passed to pacman" {
  printf '{"bar":false,"notifications":true,"launcher":true,"rofi":true,"terminal":true,"lock":true,"idle":true,"wallpaper":true}' \
    > "$HYPR_JSON"
  run env ENVIRONMENT_DESKTOP="hyprland" bash "$ADAPTER"
  [ "$status" -eq 0 ]
  ! grep -q "waybar" "$PACMAN_LOG"
}

@test "all companions installed when all enabled" {
  run env ENVIRONMENT_DESKTOP="hyprland" bash "$ADAPTER"
  [ "$status" -eq 0 ]
  grep -q "waybar"       "$PACMAN_LOG"
  grep -q "dunst"        "$PACMAN_LOG"
  grep -q "fuzzel"       "$PACMAN_LOG"
  grep -q "rofi-wayland" "$PACMAN_LOG"
  grep -q "alacritty"    "$PACMAN_LOG"
  grep -q "hyprlock"     "$PACMAN_LOG"
  grep -q "hypridle"     "$PACMAN_LOG"
  grep -q "hyprpaper"    "$PACMAN_LOG"
}
