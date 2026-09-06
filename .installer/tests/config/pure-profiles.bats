#!/usr/bin/env bats
# Tests for the committed stock (pure) Host Profiles hosts/{kde,hyprland,niri}
# -pure (ADR 0112): each is a single-desktop, stock, bare-userland machine that
# loads and validates clean against the closed schema. Behaviour under test: the
# effective config the loader produces + validate_profile's verdict — never the
# file layout. Prior art: personal-profiles.bats.

setup() {
  export INSTALLER_DIR="$BATS_TEST_DIRNAME/../.."
  info()    { :; }
  warn()    { :; }
  error()   { echo "[error] $*" >&2; return 1; }
  section() { :; }
  export -f info warn error section

  # shellcheck source=../../lib/config/profile.sh
  source "$INSTALLER_DIR/lib/config/profile.sh"
}

# <profile> <desktop> — the profile resolves to a single-desktop, stock config
# with no inherited packages. `inherit: false` is a Layer Resolver control key,
# stripped from the output (ADR 0057), so the observable of "no inherited
# packages" is a null .packages, not a surviving inherit flag.
stock_single() {
  load_profile "$1" | jq -e --arg de "$2" '
    (.environment.desktop == [$de])
    and (.environment.stock == true)
    and (.packages == null)'
}

@test "kde-pure: single stock kde desktop, no inherited packages" {
  stock_single kde-pure kde
}

@test "hyprland-pure: single stock hyprland desktop, no inherited packages" {
  stock_single hyprland-pure hyprland
}

@test "niri-pure: single stock niri desktop, no inherited packages" {
  stock_single niri-pure niri
}

@test "kde-pure: validate_profile passes" {
  run validate_profile kde-pure
  [ "$status" -eq 0 ]
}

@test "hyprland-pure: validate_profile passes" {
  run validate_profile hyprland-pure
  [ "$status" -eq 0 ]
}

@test "niri-pure: validate_profile passes" {
  run validate_profile niri-pure
  [ "$status" -eq 0 ]
}
