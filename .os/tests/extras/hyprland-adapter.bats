#!/usr/bin/env bats
# Tests for extras/desktop/hyprland/hyprland.sh (ADR 0062).
#
# Strategy: run the adapter as a subprocess with pacman and systemctl stubbed as
# executables in a temp bin dir prepended to PATH. Injectable seams:
#   WAYLAND_SESSIONS_DIR — session-override dir (default; written under ROOT)
#   ROOT                 — prefix for session override + aquamarine pin writes
#   STATE                — install-state.json for the resolved .gpu array
#
# The display manager is no longer this adapter's concern (ADR 0069) — it only
# writes the curated session files; a separate Display Manager Adapter owns the
# greeter.

setup() {
  TEST_DIR="$(mktemp -d)"
  STUB_BIN="$TEST_DIR/bin"
  mkdir -p "$STUB_BIN"

  PACMAN_LOG="$TEST_DIR/pacman.log"
  SYSTEMCTL_LOG="$TEST_DIR/systemctl.log"
  ROOT="$TEST_DIR/root"
  STATE="$TEST_DIR/state.json"
  SESSION="$ROOT/usr/local/share/wayland-sessions/hyprland.desktop"
  ADAPTER="$BATS_TEST_DIRNAME/../../extras/desktop/hyprland/hyprland.sh"

  export PACMAN_LOG SYSTEMCTL_LOG ROOT STATE

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
  for p in hyprland seatd xdg-desktop-portal-hyprland \
           xdg-desktop-portal-gtk polkit-kde-agent wl-clipboard; do
    grep -q "$p" "$PACMAN_LOG" || { echo "core missing: $p"; return 1; }
  done
}

# uwsm is not installed (ADR 0070): its session deadlocks on first-boot login
# under impermanence, so the uwsm session is dropped and the package with it.
@test "does not install uwsm" {
  run_hypr "hyprland"
  [ "$status" -eq 0 ]
  ! grep -qw "uwsm" "$PACMAN_LOG"
}

# aquamarine can't get DRM master via logind on some hardware (atomic KMS
# commit → "Permission denied", compositor retry-loops → black screen); it uses
# seatd instead, which must be enabled (ADR 0068).
@test "enables seatd so aquamarine gets DRM master" {
  run_hypr "hyprland"
  [ "$status" -eq 0 ]
  grep -q "systemctl enable seatd" "$SYSTEMCTL_LOG"
}

@test "enables seatd on a KDE co-install too" {
  run_hypr "kde hyprland"
  [ "$status" -eq 0 ]
  grep -q "systemctl enable seatd" "$SYSTEMCTL_LOG"
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

# ── session override (start-hyprland, DRM backend) ───────────────────────────

@test "ships a wayland-session override that launches start-hyprland on DRM" {
  run_hypr "hyprland"
  [ "$status" -eq 0 ]
  [ -f "$SESSION" ]
  # start-hyprland (Hyprland 0.53+ recommended, kills the red warning; the old
  # crash was the DRM-master issue, fixed by seatd), WAYLAND_DISPLAY/DISPLAY
  # unset so aquamarine uses the DRM backend not the nested one (ADR 0067/0068).
  grep -qx 'Exec=env -u WAYLAND_DISPLAY -u DISPLAY start-hyprland' "$SESSION"
}

@test "does not offer a uwsm session (dropped, ADR 0070)" {
  run_hypr "kde hyprland"
  [ "$status" -eq 0 ]
  [ ! -e "$ROOT/usr/local/share/wayland-sessions/hyprland-uwsm.desktop" ]
}

# ── display manager relinquished to the DM adapter (ADR 0069) ────────────────
# The Hyprland adapter no longer installs or enables any greeter; it only writes
# the curated session files the selected Display Manager Adapter offers.

@test "Hyprland adapter installs no greeter and enables no display manager" {
  run_hypr "hyprland"
  [ "$status" -eq 0 ]
  ! grep -q "greetd" "$PACMAN_LOG"
  ! grep -q "enable greetd" "$SYSTEMCTL_LOG"
  ! grep -q "enable sddm" "$SYSTEMCTL_LOG"
}

@test "KDE co-installed: curated dir offers Plasma + start-hyprland" {
  run_hypr "kde hyprland"
  [ "$status" -eq 0 ]
  # The /usr/share duplicates never reach the picker — the greeter is pointed
  # at this curated dir (greetd via --sessions, sddm via pinned SessionDir).
  [ -L "$ROOT/usr/local/share/wayland-sessions/plasma.desktop" ]
  [ ! -e "$ROOT/usr/local/share/wayland-sessions/hyprland-uwsm.desktop" ]
  [ -f "$SESSION" ]
}

@test "KDE co-installed: Plasma session is curated regardless of DE order" {
  run_hypr "hyprland kde"
  [ "$status" -eq 0 ]
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
