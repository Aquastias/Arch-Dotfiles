#!/usr/bin/env bats
# Tests for extras/desktop/umbriel/umbriel.sh (ADR 0159).
#
# Strategy: run the adapter as a subprocess with pacman and systemctl stubbed
# as executables in a temp bin dir prepended to PATH; session writes go under a
# temp ROOT. Umbriel itself is AUR-only (the adapter's install-umbriel.jsonc
# `aur` list, installed later by the Profiles Runner's paru pass), so the
# adapter installs only its repo core and curates a session entry that resolves
# once the package lands.

setup() {
  TEST_DIR="$(mktemp -d)"
  STUB_BIN="$TEST_DIR/bin"
  ROOT="$TEST_DIR/root"
  mkdir -p "$STUB_BIN" "$ROOT"

  PACMAN_LOG="$TEST_DIR/pacman.log"
  SYSTEMCTL_LOG="$TEST_DIR/systemctl.log"
  WAYLAND_SESSIONS_DIR="/usr/local/share/wayland-sessions"
  ADAPTER="$BATS_TEST_DIRNAME/../../extras/desktop/umbriel/umbriel.sh"
  AUR_LIST="$BATS_TEST_DIRNAME/../../extras/desktop/umbriel/install-umbriel.jsonc"
  export PACMAN_LOG SYSTEMCTL_LOG WAYLAND_SESSIONS_DIR ROOT

  printf '#!/usr/bin/env bash\necho "pacman $*" >> "$PACMAN_LOG"\n' \
    > "$STUB_BIN/pacman"
  printf '#!/usr/bin/env bash\necho "systemctl $*" >> "$SYSTEMCTL_LOG"\n' \
    > "$STUB_BIN/systemctl"
  chmod +x "$STUB_BIN/pacman" "$STUB_BIN/systemctl"
  export PATH="$STUB_BIN:$PATH"
  CURATED="$ROOT$WAYLAND_SESSIONS_DIR"
}

teardown() { rm -rf "$TEST_DIR"; }

@test "installs exactly the repo session core" {
  run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  grep -qx "pacman -S --noconfirm --needed seatd xdg-desktop-portal-gtk \
wl-clipboard" "$PACMAN_LOG"
  [ "$(grep -c '^pacman ' "$PACMAN_LOG")" -eq 1 ]
}

@test "enables seatd so Umbriel gets DRM master (ADR 0068)" {
  run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  grep -qx "systemctl enable seatd" "$SYSTEMCTL_LOG"
}

@test "declares the compositor and its portal for the vetted paru pass" {
  run bash -c "sed 's://.*::' '$AUR_LIST' | jq -r '.aur[] | keys[]'"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qx umbriel-git
  echo "$output" | grep -qx xdg-desktop-portal-umbriel-git
}

@test "curates the packaged Umbriel session into the shared /usr/local dir" {
  run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  [ "$(readlink "$CURATED/umbriel.desktop")" == \
    /usr/share/wayland-sessions/umbriel.desktop ]
}

@test "KDE co-installed: the curated dir also offers Plasma" {
  ENVIRONMENT_DESKTOP="umbriel kde" run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  [ "$(readlink "$CURATED/plasma.desktop")" == \
    /usr/share/wayland-sessions/plasma.desktop ]
}

@test "Umbriel alone: no Plasma session in the curated dir" {
  ENVIRONMENT_DESKTOP="umbriel" run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  [ ! -L "$CURATED/plasma.desktop" ]
}

@test "installs no greeter and enables no display manager (ADR 0069)" {
  run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  ! grep -Eq "greetd|sddm" "$PACMAN_LOG"
  ! grep -Eq "greetd|sddm" "$SYSTEMCTL_LOG"
}
