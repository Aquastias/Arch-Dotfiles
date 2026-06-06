#!/usr/bin/env bats
# Tests for the Runner AUR merge — _profiles_resolve_aur in lib/profiles/runner.sh.
#
# Pure resolver: unions host packages.aur (categorized string mode) with each
# desktop adapter's `aur` field (categorized bool mode), read from
# ${OS_DIR}/extras/desktop/<de>/install-<de>.jsonc. Sorted-unique on stdout;
# missing host field / adapter file / adapter field contribute nothing.
# Asserts on the resolved set — paru never runs.

setup() {
  TEST_DIR="$(mktemp -d)"
  export OS_DIR="$TEST_DIR/os"

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
  mkdir -p "$OS_DIR/extras/desktop/${de}"
  printf '%s\n' "$body" > "$OS_DIR/extras/desktop/${de}/install-${de}.jsonc"
}

@test "adapter-declared AUR package appears in the resolved set" {
  _adapter hyprland '{"aur":{"qt-theming":{"qt6ct-kde":true}}}'

  run _profiles_resolve_aur '{}' hyprland
  [ "$status" -eq 0 ]
  grep -qx "qt6ct-kde" <<< "$output"
}

@test "empty adapter aur resolves to exactly the host AUR set" {
  _adapter kde '{"aur":{}}'
  local host='{"packages":{"aur":{"misc":["brave-bin","octopi"]}}}'

  run _profiles_resolve_aur "$host" kde
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'brave-bin\noctopi')" ]
}

@test "host + multiple adapters union and dedupe overlaps" {
  _adapter kde      '{"aur":{"kde":{"kde-pkg":true}}}'
  _adapter hyprland '{"aur":{"qt-theming":{"qt6ct-kde":true}}}'
  local host='{"packages":{"aur":{"misc":["brave-bin","qt6ct-kde"]}}}'

  run _profiles_resolve_aur "$host" kde hyprland
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

@test "shipped install-hyprland.jsonc declares qt6ct-kde under aur" {
  local f="$BATS_TEST_DIRNAME/../../extras/desktop/hyprland/install-hyprland.jsonc"
  local aur_json
  aur_json="$(jsonc_strip "$f" | jq -c '.aur // empty')"
  [ -n "$aur_json" ]
  run categorized_list_parse "$aur_json" bool aur
  [ "$status" -eq 0 ]
  grep -qx "qt6ct-kde" <<< "$output"
}

@test "shipped install-kde.jsonc has an aur field" {
  local f="$BATS_TEST_DIRNAME/../../extras/desktop/kde/install-kde.jsonc"
  jsonc_strip "$f" | jq -e 'has("aur")' >/dev/null
}

# ── octopi is KDE-adapter-owned, not host-declared (PRD story 21) ───────────

@test "octopi resolves under kde via the real adapter" {
  OS_DIR="$BATS_TEST_DIRNAME/../.."   # resolve against the shipped adapters
  run _profiles_resolve_aur '{}' kde
  [ "$status" -eq 0 ]
  grep -qx "octopi" <<< "$output"
}

@test "octopi is no longer declared in any host packages.aur" {
  local h
  for h in desktop laptop; do
    ! grep -q '"octopi"' "$BATS_TEST_DIRNAME/../../hosts/$h/config.jsonc"
  done
}

@test "octopi does not resolve under hyprland-only" {
  OS_DIR="$BATS_TEST_DIRNAME/../.."
  run _profiles_resolve_aur '{}' hyprland
  [ "$status" -eq 0 ]
  ! grep -qx "octopi" <<< "$output"
}

# ── steam: repo package, not AUR steam-native-runtime (libjpeg6 conflict) ────
# steam-native-runtime pulls the virtual libjpeg6 dep, whose default provider
# jpegli-git conflicts with libjxl — fatal under paru --noconfirm. Repo `steam`
# already covers gaming, so the AUR runtime is dropped from every host.

@test "steam-native-runtime is not declared in any host packages.aur" {
  local h
  for h in desktop laptop; do
    ! grep -q '"steam-native-runtime"' \
      "$BATS_TEST_DIRNAME/../../hosts/$h/config.jsonc"
  done
}

@test "each host still declares repo steam in packages.repo" {
  local h
  for h in desktop laptop; do
    grep -q '"steam"' "$BATS_TEST_DIRNAME/../../hosts/$h/config.jsonc"
  done
}
