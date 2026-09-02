#!/usr/bin/env bats
# Tests for the Runner AUR merge — _profiles_resolve_aur in lib/profiles/runner.sh.
#
# Pure resolver: unions host packages.aur (categorized string mode) with each
# desktop adapter's `aur` field (categorized bool mode), read from
# ${INSTALLER_DIR}/extras/desktop/<de>/install-<de>.jsonc. Sorted-unique on
# stdout;
# missing host field / adapter file / adapter field contribute nothing.
# Asserts on the resolved set — paru never runs.

setup() {
  TEST_DIR="$(mktemp -d)"
  export INSTALLER_DIR="$TEST_DIR/os"

  # shellcheck source=../../lib/common.sh
  source "$BATS_TEST_DIRNAME/../../lib/common.sh"
  # shellcheck source=../../lib/config/categorized-list.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/categorized-list.sh"
  # shellcheck source=../../lib/profiles/runner.sh
  source "$BATS_TEST_DIRNAME/../../lib/profiles/runner.sh"
}

teardown() { rm -rf "$TEST_DIR"; }

# Write an adapter install-<de>.jsonc with the given JSON body.
_adapter() {
  local de="$1" body="$2"
  mkdir -p "$INSTALLER_DIR/extras/desktop/${de}"
  printf '%s\n' "$body" > "$INSTALLER_DIR/extras/desktop/${de}/install-${de}.jsonc"
}

@test "adapter-declared AUR package appears in the resolved set" {
  _adapter kde '{"aur":{"qt-theming":{"qt6ct-kde":true}}}'

  run _profiles_resolve_aur '{}' kde
  [ "$status" -eq 0 ]
  grep -qx "qt6ct-kde" <<< "$output"
}

@test "empty adapter aur resolves to exactly the host AUR set" {
  _adapter kde '{"aur":{}}'
  local host='{"packages":{"aur":{"misc":["brave-bin","ani-cli-git"]}}}'

  run _profiles_resolve_aur "$host" kde
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'ani-cli-git\nbrave-bin')" ]
}

@test "host + multiple adapters union and dedupe overlaps" {
  _adapter kde     '{"aur":{"kde":{"kde-pkg":true}}}'
  _adapter stub-de '{"aur":{"qt-theming":{"qt6ct-kde":true}}}'
  local host='{"packages":{"aur":{"misc":["brave-bin","qt6ct-kde"]}}}'

  run _profiles_resolve_aur "$host" kde stub-de
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'brave-bin\nkde-pkg\nqt6ct-kde')" ]
}

@test "adapter without an aur field contributes nothing, no error" {
  _adapter kde '{"shell":true,"apps":true}'

  run _profiles_resolve_aur '{}' kde
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "missing adapter file contributes nothing, no error" {
  run _profiles_resolve_aur '{}' nonexistent-de
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "malformed adapter aur aborts with parser error" {
  _adapter kde '{"aur":{"x":{"p":"yes"}}}'

  run _profiles_resolve_aur '{}' kde
  [ "$status" -ne 0 ]
  [[ "$output" == *"aur.x.p"* ]]
  [[ "$output" == *"expected boolean leaf"* ]]
}

# ── shipped adapter aur fields ──────────────────────────────────────────────

@test "shipped install-kde.jsonc has an aur field" {
  local f="$BATS_TEST_DIRNAME/../../extras/desktop/kde/install-kde.jsonc"
  jsonc_strip "$f" | jq -e 'has("aur")' >/dev/null
}

# ── the adapter's aur list is DE-tied: qt6ct-kde AND octopi (ADR 0094) ──
# Both are KDE-tied and must not install on a non-KDE host, so they live in the
# adapter aur, off the host profiles. octopi (a Qt pacman GUI) moved here from
# Host Core by operator decision; qt6ct-kde moved here off the host profiles.

@test "qt6ct-kde resolves under kde via the real adapter" {
  INSTALLER_DIR="$BATS_TEST_DIRNAME/../.."   # resolve against the shipped adapters
  run _profiles_resolve_aur '{}' kde
  [ "$status" -eq 0 ]
  grep -qx "qt6ct-kde" <<< "$output"
}

@test "qt6ct-kde does not resolve under a non-kde DE" {
  INSTALLER_DIR="$BATS_TEST_DIRNAME/../.."
  run _profiles_resolve_aur '{}' nonexistent-de
  [ "$status" -eq 0 ]
  ! grep -qx "qt6ct-kde" <<< "$output"
}

@test "qt6ct-kde is no longer declared in any host packages.aur" {
  local h
  for h in core desktop laptop; do
    ! grep -q '"qt6ct-kde"' "$BATS_TEST_DIRNAME/../../hosts/$h/profile.jsonc"
  done
}

@test "octopi resolves under kde via the real adapter" {
  INSTALLER_DIR="$BATS_TEST_DIRNAME/../.."   # resolve against the shipped adapters
  run _profiles_resolve_aur '{}' kde
  [ "$status" -eq 0 ]
  grep -qx "octopi" <<< "$output"
}

@test "octopi is no longer declared in any host packages.aur" {
  local h
  for h in core desktop laptop; do
    ! grep -q '"octopi"' "$BATS_TEST_DIRNAME/../../hosts/$h/profile.jsonc"
  done
}

# ── Bibata Modern Ice: the fleet cursor, per-adapter AUR on all three (0098) ──
# One AUR package (bibata-cursor-git) ships both hyprcursor + Xcursor; each DE
# adapter declares it so it installs whenever that desktop is selected, and never
# on a headless/minimal host.

@test "bibata-cursor-git resolves under kde, niri and hyprland (ADR 0098)" {
  INSTALLER_DIR="$BATS_TEST_DIRNAME/../.."   # the shipped adapters
  local de
  for de in kde niri hyprland; do
    run _profiles_resolve_aur '{}' "$de"
    [ "$status" -eq 0 ]
    grep -qx "bibata-cursor-git" <<< "$output" \
      || { echo "bibata missing under $de"; return 1; }
  done
}

@test "bibata-cursor-git does not resolve on a desktop-less host (ADR 0098)" {
  INSTALLER_DIR="$BATS_TEST_DIRNAME/../.."
  run _profiles_resolve_aur '{}'          # no desktops
  [ "$status" -eq 0 ]
  ! grep -qx "bibata-cursor-git" <<< "$output"
}

# ── steam: repo package, not AUR steam-native-runtime (libjpeg6 conflict) ────
# steam-native-runtime pulls the virtual libjpeg6 dep, whose default provider
# jpegli-git conflicts with libjxl — fatal under paru --noconfirm. Repo `steam`
# already covers gaming, so the AUR runtime is dropped from every host.

@test "steam-native-runtime is not declared in any host packages.aur" {
  local h
  for h in core desktop laptop; do
    ! grep -q '"steam-native-runtime"' \
      "$BATS_TEST_DIRNAME/../../hosts/$h/profile.jsonc"
  done
}

# steam is shared by both machines, so it lives in Host Core now (ADR 0056);
# the hosts inherit it rather than each declaring it.
@test "repo steam is declared once, in Host Core" {
  grep -q '"steam"' "$BATS_TEST_DIRNAME/../../hosts/core/profile.jsonc"
  local h
  for h in desktop laptop; do
    ! grep -q '"steam"' "$BATS_TEST_DIRNAME/../../hosts/$h/profile.jsonc"
  done
}
