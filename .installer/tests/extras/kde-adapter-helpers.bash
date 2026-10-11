# kde-adapter-helpers.bash — shared setup for the kde-adapter-*.bats parts
# Tests for extras/desktop/kde/kde.sh.
#
# Strategy: run the adapter as a subprocess with pacman and systemctl stubbed
# as executables in a temp bin dir prepended to PATH. Injectable seam:
#   KDE_JSON — path to install-kde.jsonc
#
# apps_list is the 2-level Categorized List shape { category: { pkg: bool } },
# consumed via the Categorized List Parser in bool mode.

setup() {
  TEST_DIR="$(mktemp -d)"
  STUB_BIN="$TEST_DIR/bin"
  mkdir -p "$STUB_BIN"

  PACMAN_LOG="$TEST_DIR/pacman.log"
  SYSTEMCTL_LOG="$TEST_DIR/systemctl.log"
  KDE_JSON="$TEST_DIR/install-kde.jsonc"
  ADAPTER="$BATS_TEST_DIRNAME/../../extras/desktop/kde/kde.sh"
  # Seed DE defaults into the temp tree, never the real /etc/skel.
  KDE_SEED_ROOT="$TEST_DIR/seed"

  export PACMAN_LOG SYSTEMCTL_LOG KDE_JSON KDE_SEED_ROOT

  printf '#!/usr/bin/env bash\necho "pacman $*" >> "$PACMAN_LOG"\n' \
    > "$STUB_BIN/pacman"
  printf '#!/usr/bin/env bash\necho "systemctl $*" >> "$SYSTEMCTL_LOG"\n' \
    > "$STUB_BIN/systemctl"
  chmod +x "$STUB_BIN/pacman" "$STUB_BIN/systemctl"

  export PATH="$STUB_BIN:$PATH"
}

teardown() { rm -rf "$TEST_DIR"; }

