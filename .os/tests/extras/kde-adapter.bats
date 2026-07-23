#!/usr/bin/env bats
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

  export PACMAN_LOG SYSTEMCTL_LOG KDE_JSON

  printf '#!/usr/bin/env bash\necho "pacman $*" >> "$PACMAN_LOG"\n' \
    > "$STUB_BIN/pacman"
  printf '#!/usr/bin/env bash\necho "systemctl $*" >> "$SYSTEMCTL_LOG"\n' \
    > "$STUB_BIN/systemctl"
  # Cache-clean runs regardless of shell/apps; stub paccache so it never
  # touches the host's real /var/cache/pacman.
  printf '#!/usr/bin/env bash\ntrue\n' > "$STUB_BIN/paccache"
  chmod +x "$STUB_BIN/pacman" "$STUB_BIN/systemctl" "$STUB_BIN/paccache"

  export PATH="$STUB_BIN:$PATH"
}

teardown() { rm -rf "$TEST_DIR"; }

# ── apps_list (categorized, bool mode) ──────────────────────────────────────

@test "selected app under a category is installed" {
  cat > "$KDE_JSON" <<'JSON'
{"shell":false,"apps":true,"apps_list":{"files":{"sentinel-app":true}}}
JSON
  run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  grep -q "sentinel-app" "$PACMAN_LOG"
}

@test "deselected leaf (false) is not installed" {
  cat > "$KDE_JSON" <<'JSON'
{"shell":false,"apps":true,"apps_list":{"files":
{"sentinel-keep":true,"sentinel-drop":false}}}
JSON
  run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  grep -q "sentinel-keep" "$PACMAN_LOG"
  ! grep -q "sentinel-drop" "$PACMAN_LOG"
}

@test "plasma-extras members are installed" {
  cat > "$KDE_JSON" <<'JSON'
{"shell":false,"apps":true,"apps_list":{"plasma-extras":
{"sddm-kcm":true,"kimageformats5":true,"xdg-desktop-portal-kde":true}}}
JSON
  run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  grep -q "sddm-kcm" "$PACMAN_LOG"
  grep -q "kimageformats5" "$PACMAN_LOG"
  grep -q "xdg-desktop-portal-kde" "$PACMAN_LOG"
}

# ── display manager (greetd owns the DM when Hyprland is co-installed) ───────

@test "sddm enabled for a KDE-only install" {
  printf '{"shell":true,"apps":true,"apps_list":{"files":{"x":false}}}\n' \
    > "$KDE_JSON"
  run env ENVIRONMENT_DESKTOP="kde" bash "$ADAPTER"
  [ "$status" -eq 0 ]
  grep -q "systemctl enable sddm" "$SYSTEMCTL_LOG"
}

@test "sddm not enabled when Hyprland is co-installed" {
  printf '{"shell":true,"apps":true,"apps_list":{"files":{"x":false}}}\n' \
    > "$KDE_JSON"
  run env ENVIRONMENT_DESKTOP="kde hyprland" bash "$ADAPTER"
  [ "$status" -eq 0 ]
  ! grep -q "enable sddm" "$SYSTEMCTL_LOG"
}

# ── malformed apps_list aborts the install ──────────────────────────────────

@test "old flat shape (bool leaf at top) aborts with parser error" {
  cat > "$KDE_JSON" <<'JSON'
{"shell":false,"apps":true,"apps_list":{"ark":true}}
JSON
  run bash "$ADAPTER"
  [ "$status" -ne 0 ]
  [[ "$output" == *"apps_list.ark"* ]]
  [[ "$output" == *"expected object"* ]]
}

@test "non-bool leaf aborts with parser error" {
  cat > "$KDE_JSON" <<'JSON'
{"shell":false,"apps":true,"apps_list":{"files":{"dolphin":"yes"}}}
JSON
  run bash "$ADAPTER"
  [ "$status" -ne 0 ]
  [[ "$output" == *"apps_list.files.dolphin"* ]]
  [[ "$output" == *"expected boolean leaf"* ]]
}

@test "invalid category name aborts with parser error" {
  cat > "$KDE_JSON" <<'JSON'
{"shell":false,"apps":true,"apps_list":{"Bad_Cat":{"dolphin":true}}}
JSON
  run bash "$ADAPTER"
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid category name"* ]]
}

# ── shipped install-kde.jsonc regression lock ───────────────────────────────

@test "shipped apps_list parses (bool) to the full prior 24-app set" {
  # shellcheck source=../../lib/common.sh
  source "$BATS_TEST_DIRNAME/../../lib/common.sh"
  # shellcheck source=../../lib/config/categorized-list.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/categorized-list.sh"
  local real="$BATS_TEST_DIRNAME/../../extras/desktop/kde/install-kde.jsonc"
  local apps_json
  apps_json="$(jsonc "$real" | jq -c '.apps_list')"

  run categorized_list_parse "$apps_json" bool apps_list
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '%s\n' \
    ark calligra dolphin filelight gwenview kate kdiff3 keditbookmarks \
    kimageformats5 kleopatra kompare konsole krename krita krusader \
    ktorrent kwalletmanager okular pacmanlogviewer partitionmanager \
    sddm-kcm skanlite skanpage xdg-desktop-portal-kde | sort)" ]
}
