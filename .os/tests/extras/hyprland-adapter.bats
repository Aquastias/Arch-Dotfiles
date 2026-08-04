#!/usr/bin/env bats
# Tests for extras/desktop/hyprland/hyprland.sh (ADR 0062).
#
# Strategy: run the adapter as a subprocess with pacman and systemctl stubbed as
# executables in a temp bin dir prepended to PATH. Injectable seams:
#   GREETD_CONF_DIR      — greetd config dir
#   WAYLAND_SESSIONS_DIR — session-override dir (default; written under ROOT)
#   ROOT                 — prefix for session override + aquamarine pin writes
#   STATE                — install-state.json for the resolved .gpu array

setup() {
  TEST_DIR="$(mktemp -d)"
  STUB_BIN="$TEST_DIR/bin"
  mkdir -p "$STUB_BIN"

  PACMAN_LOG="$TEST_DIR/pacman.log"
  SYSTEMCTL_LOG="$TEST_DIR/systemctl.log"
  GREETD_CONF_DIR="$TEST_DIR/greetd"
  ROOT="$TEST_DIR/root"
  STATE="$TEST_DIR/state.json"
  SESSION="$ROOT/usr/local/share/wayland-sessions/hyprland.desktop"
  ADAPTER="$BATS_TEST_DIRNAME/../../extras/desktop/hyprland/hyprland.sh"

  export PACMAN_LOG SYSTEMCTL_LOG GREETD_CONF_DIR ROOT STATE

  printf '#!/usr/bin/env bash\necho "pacman $*" >> "$PACMAN_LOG"\n' \
    > "$STUB_BIN/pacman"
  printf '#!/usr/bin/env bash\necho "systemctl $*" >> "$SYSTEMCTL_LOG"\n' \
    > "$STUB_BIN/systemctl"
  chmod +x "$STUB_BIN/pacman" "$STUB_BIN/systemctl"

  export PATH="$STUB_BIN:$PATH"
}

teardown() { rm -rf "$TEST_DIR"; }

run_hypr() { run env ENVIRONMENT_DESKTOP="$1" bash "$ADAPTER"; }

# ── core packages ───────────────────────────────────────────────────────────

@test "installs exactly the working-session core" {
  run_hypr "hyprland"
  [ "$status" -eq 0 ]
  local p
  for p in hyprland xdg-desktop-portal-hyprland xdg-desktop-portal-gtk \
           polkit-kde-agent wl-clipboard; do
    grep -q "$p" "$PACMAN_LOG" || { echo "core missing: $p"; return 1; }
  done
}

@test "installs no companion packages and no qt6ct" {
  run_hypr "hyprland"
  [ "$status" -eq 0 ]
  local p
  for p in waybar dunst fuzzel rofi-wayland wofi alacritty hyprlock \
           hypridle hyprpaper grim slurp nwg-look qt6ct qt6ct-kde; do
    ! grep -q "$p" "$PACMAN_LOG" || { echo "unexpected package: $p"; return 1; }
  done
}

# ── session override (direct Hyprland, not start-hyprland) ───────────────────

@test "ships a wayland-session override that launches Hyprland on DRM" {
  run_hypr "hyprland"
  [ "$status" -eq 0 ]
  [ -f "$SESSION" ]
  # Direct Hyprland (no start-hyprland) with WAYLAND_DISPLAY/DISPLAY unset so
  # aquamarine uses the DRM backend, not its nested Wayland one (ADR 0067).
  grep -qx 'Exec=env -u WAYLAND_DISPLAY -u DISPLAY Hyprland' "$SESSION"
}

@test "session override Exec never points at start-hyprland" {
  run_hypr "kde hyprland"
  [ "$status" -eq 0 ]
  [ -f "$SESSION" ]
  ! grep -qE '^Exec=.*start-hyprland' "$SESSION"
}

# ── display manager: greetd whenever Hyprland is installed (ADR 0067) ────────

@test "Hyprland-only: greetd installed, enabled, tuigreet --cmd Hyprland" {
  run_hypr "hyprland"
  [ "$status" -eq 0 ]
  grep -q "greetd" "$PACMAN_LOG"
  grep -q "systemctl enable greetd" "$SYSTEMCTL_LOG"
  grep -q "tuigreet --cmd Hyprland" "$GREETD_CONF_DIR/config.toml"
}

@test "KDE co-installed: greetd owns the DM with a curated session picker" {
  run_hypr "kde hyprland"
  [ "$status" -eq 0 ]
  grep -q "greetd" "$PACMAN_LOG"
  grep -q "systemctl enable greetd" "$SYSTEMCTL_LOG"
  # A session picker over the curated dir, NOT a fixed --cmd Hyprland.
  grep -q -- "--sessions.*wayland-sessions" "$GREETD_CONF_DIR/config.toml"
  ! grep -q -- "--cmd Hyprland" "$GREETD_CONF_DIR/config.toml"
  # Plasma is symlinked into the curated dir so the picker offers it (and our
  # Hyprland override) — never the packaged crashy start-hyprland session.
  [ -L "$ROOT/usr/local/share/wayland-sessions/plasma.desktop" ]
}

@test "KDE co-installed: greetd is enabled regardless of DE order" {
  run_hypr "hyprland kde"
  [ "$status" -eq 0 ]
  grep -q "systemctl enable greetd" "$SYSTEMCTL_LOG"
  [ -L "$ROOT/usr/local/share/wayland-sessions/plasma.desktop" ]
}

# ── aquamarine DRM pinning: hybrid amd+nvidia only ───────────────────────────

@test "hybrid amd+nvidia: writes the udev rule and AQ_DRM_DEVICES pin" {
  printf '{"gpu":["amd","nvidia"]}\n' > "$STATE"
  run_hypr "hyprland"
  [ "$status" -eq 0 ]
  [ -f "$ROOT/usr/lib/udev/rules.d/60-aq-drm-devices.rules" ]
  grep -q 'AQ_DRM_DEVICES=/dev/dri/aq-igpu' "$ROOT/etc/environment"
}

@test "single-vendor GPU: neither udev rule nor pin is written" {
  printf '{"gpu":["amd"]}\n' > "$STATE"
  run_hypr "hyprland"
  [ "$status" -eq 0 ]
  [ ! -f "$ROOT/usr/lib/udev/rules.d/60-aq-drm-devices.rules" ]
  [ ! -f "$ROOT/etc/environment" ]
}

@test "no install-state present: pin is skipped without error" {
  rm -f "$STATE"
  run_hypr "hyprland"
  [ "$status" -eq 0 ]
  [ ! -f "$ROOT/usr/lib/udev/rules.d/60-aq-drm-devices.rules" ]
}
