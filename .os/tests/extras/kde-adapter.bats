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
  for p in plasma-meta sddm-kcm papirus-icon-theme \
           qt5-wayland qt6-wayland xdg-utils; do
    grep -q "$p" "$PACMAN_LOG" \
      || { echo "shell section missing: $p"; return 1; }
  done
}

# ── display manager is no longer the KDE adapter's concern (ADR 0069) ─────────
# The display manager is an operator choice owned by a separate Display Manager
# Adapter. The KDE adapter installs sddm-kcm (a KDE config app) but neither the
# sddm PACKAGE nor its enablement — those moved to dm-sddm.

@test "KDE adapter enables no display manager" {
  cat > "$KDE_JSON" <<'JSON'
{"shell":true,"apps":false,"apps_list":{}}
JSON
  run env ENVIRONMENT_DESKTOP="kde" bash "$ADAPTER"
  [ "$status" -eq 0 ]
  ! grep -q "enable sddm" "$SYSTEMCTL_LOG"
  ! grep -q "enable greetd" "$SYSTEMCTL_LOG"
}

@test "KDE adapter installs sddm-kcm but not the sddm package" {
  cat > "$KDE_JSON" <<'JSON'
{"shell":true,"apps":false,"apps_list":{}}
JSON
  run env ENVIRONMENT_DESKTOP="kde hyprland" bash "$ADAPTER"
  [ "$status" -eq 0 ]
  grep -q "sddm-kcm" "$PACMAN_LOG"
  # the bare sddm package is not installed by KDE — dm-sddm owns it
  ! grep -qE '(^|[[:space:]])sddm([[:space:]]|$)' "$PACMAN_LOG"
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

# ── apps_extra (categorized, bool mode) ─────────────────────────────────────
# apps_extra installs in the same pacman pass as apps_list (ADR 0087).

@test "selected app under apps_extra is installed" {
  cat > "$KDE_JSON" <<'JSON'
{"shell":false,"apps":true,"apps_list":{},
"apps_extra":{"gfx":{"sentinel-extra":true}}}
JSON
  run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  grep -q "sentinel-extra" "$PACMAN_LOG"
}

@test "deselected apps_extra leaf (false) is not installed" {
  cat > "$KDE_JSON" <<'JSON'
{"shell":false,"apps":true,"apps_list":{},
"apps_extra":{"gfx":{"sentinel-keep":true,"sentinel-drop":false}}}
JSON
  run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  grep -q "sentinel-keep" "$PACMAN_LOG"
  ! grep -q "sentinel-drop" "$PACMAN_LOG"
}

@test "malformed apps_extra aborts with a pathed parser error" {
  cat > "$KDE_JSON" <<'JSON'
{"shell":false,"apps":true,"apps_list":{},
"apps_extra":{"gfx":{"krita":"yes"}}}
JSON
  run bash "$ADAPTER"
  [ "$status" -ne 0 ]
  [[ "$output" == *"apps_extra.gfx.krita"* ]]
  [[ "$output" == *"expected boolean leaf"* ]]
}

# ── shipped install-kde.jsonc regression lock ───────────────────────────────

# apps_list holds exactly the operator's kde-applications-group roster plus the
# three plasma-group no-ops (spectacle / plasma-systemmonitor / discover) that
# plasma-meta already pulls. Membership is mechanical (R21, ADR 0087): a repo
# app belongs here iff its pacman Groups contains `kde-applications`; every
# non-group KDE app lives in apps_extra instead.
@test "shipped apps_list matches the curated roster" {
  # shellcheck source=../../lib/common.sh
  source "$BATS_TEST_DIRNAME/../../lib/common.sh"
  # shellcheck source=../../lib/config/categorized-list.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/categorized-list.sh"
  local real="$BATS_TEST_DIRNAME/../../extras/desktop/kde/install-kde.jsonc"
  local apps_json
  apps_json="$(jsonc "$real" | jq -c '.apps_list')"

  run categorized_list_parse "$apps_json" bool apps_list
  [ "$status" -eq 0 ]
  [ "$(wc -l <<<"$output")" -eq 34 ]
  [ "$(sort <<<"$output")" = "$(printf '%s\n' \
    ark calligra discover dolphin elisa filelight ghostwriter gwenview \
    isoimagewriter k3b kate kcalc kcolorchooser kdeconnect kdenlive keysmith \
    kfind kiten kleopatra kmag kolourpaint konsole krdc krfb ktorrent \
    kwalletmanager merkuro okular partitionmanager plasma-systemmonitor \
    skanpage spectacle sweeper yakuake | sort)" ]
}

@test "shipped apps_extra is exactly the non-group KDE apps" {
  source "$BATS_TEST_DIRNAME/../../lib/common.sh"
  source "$BATS_TEST_DIRNAME/../../lib/config/categorized-list.sh"
  local real="$BATS_TEST_DIRNAME/../../extras/desktop/kde/install-kde.jsonc"
  local extra_json
  extra_json="$(jsonc "$real" | jq -c '.apps_extra')"

  run categorized_list_parse "$extra_json" bool apps_extra
  [ "$status" -eq 0 ]
  [ "$(sort <<<"$output")" = "$(printf '%s\n' \
    digikam haruna kdiff3 kommit krename krusader krita okteta | sort)" ]
}

@test "the plasma-extras category is gone" {
  local real="$BATS_TEST_DIRNAME/../../extras/desktop/kde/install-kde.jsonc"
  # shellcheck source=../../lib/jsonc.sh
  source "$BATS_TEST_DIRNAME/../../lib/jsonc.sh"
  jsonc_strip "$real" | jq -e '.apps_list | has("plasma-extras") | not'
}

@test "the pruned/removed apps appear in no section" {
  local real="$BATS_TEST_DIRNAME/../../extras/desktop/kde/install-kde.jsonc"
  source "$BATS_TEST_DIRNAME/../../lib/jsonc.sh"
  local names
  names="$(jsonc_strip "$real" | jq -r '
    [(.apps_list // {}), (.apps_extra // {}), (.plugins // {})]
    | .[] | to_entries[].value | keys[]')"
  local p
  # Old non-applications (relocated / redundant) plus this round's prunes:
  # karbon (⊂ calligra), kclock (mobile), skanlite (⊂ skanpage), arianna
  # (Okular covers EPUB), kgpg (kleopatra kept), kompare (→ kdiff3),
  # keditbookmarks (unrequested).
  for p in sddm-kcm xdg-desktop-portal-kde kimageformats5 pacmanlogviewer \
           octopi karbon kclock skanlite arianna kgpg kompare keditbookmarks; do
    ! grep -qx "$p" <<<"$names" || { echo "still declared: $p"; return 1; }
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
