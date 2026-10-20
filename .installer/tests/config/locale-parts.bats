#!/usr/bin/env bats
# Tests for lib/config/locale-parts.sh — locale + keymap naming helpers.

setup() {
  # shellcheck source=../../lib/config/locale-parts.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/locale-parts.sh"
  MAP="$BATS_TEST_TMPDIR/kbd-model-map"
  printf '%s\n' \
    '# console  x11-layout  model  variant  options' \
    'uk			gb	pc105		-		terminate:ctrl_alt_bksp' \
    'de-latin1-nodeadkeys	de	pc105		nodeadkeys	terminate:ctrl_alt_bksp' \
    'us			us	pc105+inet	-		terminate:ctrl_alt_bksp' >"$MAP"
}

@test "locale_parts_xkb: maps a console keymap to its X11 layout" {
  # Console names are not XKB layouts (uk ≠ gb): X fell back to us.
  run locale_parts_xkb uk "$MAP"
  [ "$output" = "gb " ]
}

@test "locale_parts_xkb: carries the X11 variant" {
  run locale_parts_xkb de-latin1-nodeadkeys "$MAP"
  [ "$output" = "de nodeadkeys" ]
}

@test "locale_parts_xkb: an unmapped keymap passes through unchanged" {
  run locale_parts_xkb dvorak "$MAP"
  [ "$output" = "dvorak " ]
}
