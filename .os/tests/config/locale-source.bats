#!/usr/bin/env bats
# Tests for .os/lib/config/locale-source.sh — the Locale option-source boundary
# (ADR 0076). Enumerates the Locales leaves' options from the medium; rooted at
# LOCALE_SRC_ROOT so a fixture tree stands in for the live ISO. Pure: no TTY.

setup() {
  source "$BATS_TEST_DIRNAME/../../lib/config/locale-source.sh"
  FIXROOT="$(mktemp -d)"
  export LOCALE_SRC_ROOT="$FIXROOT"
}

teardown() { rm -rf "$FIXROOT"; }

# ── keymaps ────────────────────────────────────────────────────────────────

@test "locale_list_keymaps: enumerates the medium's kbd keymaps, sorted+unique" {
  mkdir -p "$FIXROOT/usr/share/kbd/keymaps/i386/qwerty"
  mkdir -p "$FIXROOT/usr/share/kbd/keymaps/i386/qwertz"
  : > "$FIXROOT/usr/share/kbd/keymaps/i386/qwerty/us.map.gz"
  : > "$FIXROOT/usr/share/kbd/keymaps/i386/qwertz/de.map.gz"
  : > "$FIXROOT/usr/share/kbd/keymaps/i386/qwerty/uk.map.gz"
  run locale_list_keymaps
  [ "$status" -eq 0 ]
  [ "$output" == "$(printf '%s\n' de uk us)" ]
}

@test "locale_list_keymaps: strips the .map.gz suffix" {
  mkdir -p "$FIXROOT/usr/share/kbd/keymaps/i386/qwerty"
  : > "$FIXROOT/usr/share/kbd/keymaps/i386/qwerty/fr-latin1.map.gz"
  run locale_list_keymaps
  [ "$status" -eq 0 ]
  [ "$output" == "fr-latin1" ]
}

@test "locale_list_keymaps: empty medium yields no output, rc 0" {
  run locale_list_keymaps
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
