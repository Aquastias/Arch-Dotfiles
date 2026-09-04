#!/usr/bin/env bats
# Tests for extras/dm/sddm/sddm.sh — the SDDM Display Manager Adapter.
#
# Strategy: run the adapter as a subprocess with pacman and systemctl stubbed
# as executables in a temp bin dir prepended to PATH; config writes redirected
# to a temp ROOT. Injectable seams: SDDM_CONF_DIR, WAYLAND_SESSIONS_DIR, ROOT.

setup() {
  TEST_DIR="$(mktemp -d)"
  STUB_BIN="$TEST_DIR/bin"
  ROOT="$TEST_DIR/root"
  mkdir -p "$STUB_BIN" "$ROOT"

  PACMAN_LOG="$TEST_DIR/pacman.log"
  SYSTEMCTL_LOG="$TEST_DIR/systemctl.log"
  SDDM_CONF_DIR="/etc/sddm.conf.d"
  XORG_CONF_DIR="/etc/X11/xorg.conf.d"
  WAYLAND_SESSIONS_DIR="/usr/local/share/wayland-sessions"
  ADAPTER="$BATS_TEST_DIRNAME/../../extras/dm/sddm/sddm.sh"

  export PACMAN_LOG SYSTEMCTL_LOG SDDM_CONF_DIR XORG_CONF_DIR \
    WAYLAND_SESSIONS_DIR ROOT

  printf '#!/usr/bin/env bash\necho "pacman $*" >> "$PACMAN_LOG"\n' \
    > "$STUB_BIN/pacman"
  printf '#!/usr/bin/env bash\necho "systemctl $*" >> "$SYSTEMCTL_LOG"\n' \
    > "$STUB_BIN/systemctl"
  chmod +x "$STUB_BIN/pacman" "$STUB_BIN/systemctl"

  export PATH="$STUB_BIN:$PATH"
  CONF="$ROOT$SDDM_CONF_DIR/10-session-dirs.conf"
  XORG_CURSOR="$ROOT$XORG_CONF_DIR/10-vm-sw-cursor.conf"

  # Default: bare metal, so the base tests are host-independent. VM tests
  # override with _stub_detect_virt 0.
  _stub_detect_virt 1
}

# Stub systemd-detect-virt: exit 0 (a VM) or 1 (bare metal) per arg.
_stub_detect_virt() {
  printf '#!/usr/bin/env bash\nexit %s\n' "$1" > "$STUB_BIN/systemd-detect-virt"
  chmod +x "$STUB_BIN/systemd-detect-virt"
}

teardown() { rm -rf "$TEST_DIR"; }

@test "installs sddm" {
  run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  grep -q "sddm" "$PACMAN_LOG"
}

@test "enables the sddm service" {
  run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  grep -qx "systemctl enable sddm" "$SYSTEMCTL_LOG"
}

@test "writes an sddm.conf.d SessionDir drop-in" {
  run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  [ -f "$CONF" ]
}

@test "pins the curated wayland dir ahead of /usr/share" {
  run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  grep -q \
    "SessionDir=$WAYLAND_SESSIONS_DIR,/usr/share/wayland-sessions" "$CONF"
}

@test "pins the curated xsessions dir ahead of /usr/share" {
  run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  grep -q \
    "SessionDir=/usr/local/share/xsessions,/usr/share/xsessions" "$CONF"
}

# VM-only Xorg software-cursor drop-in (ADR 0106): SDDM's Xorg greeter would
# otherwise program the virtio cursor plane, drawn as a stale SPICE "X".
@test "in a VM: forces Xorg SWcursor for the greeter (ADR 0106)" {
  _stub_detect_virt 0   # a VM
  run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  [ -f "$XORG_CURSOR" ]
  grep -q 'Option "SWcursor" "true"' "$XORG_CURSOR"
  grep -q 'Driver "modesetting"' "$XORG_CURSOR"
}

@test "on bare metal: no Xorg SWcursor drop-in (real HW cursor kept)" {
  _stub_detect_virt 1   # not a VM
  run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  [ ! -e "$XORG_CURSOR" ]
}
