#!/usr/bin/env bats
# The Fleet Golden gate (ADR 0157): `desktop` and `laptop` must install exactly
# what they did before the Fleet Layer split. The fixtures were captured from
# the pre-split tree; a diff here is a regression on the operator's machines,
# never a fixture to regenerate.
#
# Regenerate ONLY for a deliberate change to the fleet: source
# fleet-golden-helpers.bash with BATS_TEST_DIRNAME set to this directory and
# redirect fleet_golden_snapshot <profile> into the fixture.

load fleet-golden-helpers

GOLDEN_DIR="$BATS_TEST_DIRNAME/../fixtures/golden"

@test "desktop resolves exactly as its golden snapshot" {
  diff <(fleet_golden_snapshot desktop) "$GOLDEN_DIR/desktop.txt"
}

@test "laptop resolves exactly as its golden snapshot" {
  diff <(fleet_golden_snapshot laptop) "$GOLDEN_DIR/laptop.txt"
}

# ADR 0114: one software image, two machines.
@test "desktop and laptop install the same package set" {
  diff <(fleet_golden_packages desktop) <(fleet_golden_packages laptop)
}

# The VM fixtures modelling the operator's machines fold the Fleet Layer too
# (`"fleet": true`, ADR 0157); captured after restoring them, and checked then
# to match their pre-split package sets exactly.
@test "the fleet VM fixtures resolve exactly as their golden snapshots" {
  local profile
  for profile in arch-audit arch-combined arch-combined-sops-impermanence \
                 arch-hyprland arch-niri; do
    diff <(fleet_golden_snapshot "$profile") "$GOLDEN_DIR/$profile.txt" \
      || { echo "drift: $profile"; return 1; }
  done
}
