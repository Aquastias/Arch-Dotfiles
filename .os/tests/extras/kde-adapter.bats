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
  chmod +x "$STUB_BIN/pacman" "$STUB_BIN/systemctl"

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

# The shell section owns the DE-tied non-applications: sddm-kcm (a KCM, and
# not in plasma-meta) plus the wayland/portal/icon pieces relocated out of the
# host profiles (ADR 0021, R10/R21).
@test "shell section installs the DE-tied non-applications" {
  cat > "$KDE_JSON" <<'JSON'
{"shell":true,"apps":false,"apps_list":{}}
JSON
  run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  local p
  for p in plasma-meta sddm sddm-kcm papirus-icon-theme \
           qt5-wayland qt6-wayland xdg-utils; do
    grep -q "$p" "$PACMAN_LOG" \
      || { echo "shell section missing: $p"; return 1; }
  done
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

# apps_list is exactly the 20 kde-applications entries. The membership rule is
# mechanical: a package belongs here iff its pacman Groups contains
# `kde-applications` (R21). Five non-applications were removed — sddm-kcm to
# the shell section, xdg-desktop-portal-kde and kimageformats5 as redundant
# (already in plasma-meta's tree / a stale KF5 parallel stack), and
# pacmanlogviewer + octopi to Host Core because they are not KDE at all.
@test "shipped apps_list is exactly the 20 kde-applications entries" {
  # shellcheck source=../../lib/common.sh
  source "$BATS_TEST_DIRNAME/../../lib/common.sh"
  # shellcheck source=../../lib/config/categorized-list.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/categorized-list.sh"
  local real="$BATS_TEST_DIRNAME/../../extras/desktop/kde/install-kde.jsonc"
  local apps_json
  apps_json="$(jsonc "$real" | jq -c '.apps_list')"

  run categorized_list_parse "$apps_json" bool apps_list
  [ "$status" -eq 0 ]
  [ "$(wc -l <<<"$output")" -eq 20 ]
  [ "$output" = "$(printf '%s\n' \
    ark calligra dolphin filelight gwenview kate kdiff3 keditbookmarks \
    kleopatra kompare konsole krename krita krusader \
    ktorrent kwalletmanager okular partitionmanager \
    skanlite skanpage | sort)" ]
}

@test "the plasma-extras category is gone" {
  local real="$BATS_TEST_DIRNAME/../../extras/desktop/kde/install-kde.jsonc"
  # shellcheck source=../../lib/jsonc.sh
  source "$BATS_TEST_DIRNAME/../../lib/jsonc.sh"
  jsonc_strip "$real" | jq -e '.apps_list | has("plasma-extras") | not'
}

@test "the removed non-applications appear nowhere in apps_list" {
  local real="$BATS_TEST_DIRNAME/../../extras/desktop/kde/install-kde.jsonc"
  source "$BATS_TEST_DIRNAME/../../lib/jsonc.sh"
  local names
  names="$(jsonc_strip "$real" \
    | jq -r '.apps_list | to_entries[].value | keys[]')"
  local p
  for p in sddm-kcm xdg-desktop-portal-kde kimageformats5 pacmanlogviewer \
           octopi; do
    ! grep -qx "$p" <<<"$names" || { echo "still in apps_list: $p"; return 1; }
  done
}

# Selecting KDE must not install a third-party pacman frontend.
@test "selecting KDE installs no third-party pacman frontend" {
  local real="$BATS_TEST_DIRNAME/../../extras/desktop/kde/install-kde.jsonc"
  source "$BATS_TEST_DIRNAME/../../lib/jsonc.sh"
  local all
  all="$(jsonc_strip "$real" | jq -r '
    [(.apps_list // {}), (.aur // {})] | .[] | to_entries[].value | keys[]')"
  ! grep -qx "octopi" <<<"$all"
  ! grep -qx "pacmanlogviewer" <<<"$all"
}

# pacmanlogviewer + octopi are not KDE — they belong to a host, and the
# curation put them in Host Core so both machines still get them.
@test "pacmanlogviewer and octopi are declared in Host Core" {
  local core="$BATS_TEST_DIRNAME/../../hosts/core/profile.jsonc"
  source "$BATS_TEST_DIRNAME/../../lib/jsonc.sh"
  jsonc_strip "$core" | jq -e '[.packages.repo | to_entries[].value[]]
    | index("pacmanlogviewer")'
  jsonc_strip "$core" | jq -e '[.packages.aur | to_entries[].value[]]
    | index("octopi")'
}
