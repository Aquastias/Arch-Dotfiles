#!/usr/bin/env bats
# Tests for .installer/lib/config/locale-source.sh — the Locale option-source
# boundary
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

# ── compose / decompose (ADR 0076) ─────────────────────────────────────────

@test "locale_language / locale_encoding: split a plain locale" {
  [ "$(locale_language en_US.UTF-8)" == "en_US" ]
  [ "$(locale_encoding en_US.UTF-8)" == "UTF-8" ]
}

@test "locale_language / locale_encoding: keep the @modifier on the language" {
  [ "$(locale_language sr_RS.UTF-8@latin)" == "sr_RS@latin" ]
  [ "$(locale_encoding sr_RS.UTF-8@latin)" == "UTF-8" ]
}

@test "locale_encoding: empty when the locale carries no codeset" {
  [ "$(locale_language en_US)" == "en_US" ]
  [ -z "$(locale_encoding en_US)" ]
}

@test "locale_compose: splices the encoding in, exactly once (no doubling)" {
  [ "$(locale_compose en_US UTF-8)" == "en_US.UTF-8" ]
  [ "$(locale_compose sr_RS@latin UTF-8)" == "sr_RS.UTF-8@latin" ]
  [ "$(locale_compose en_US "")" == "en_US" ]
  # round-trip: recomposing a decomposed locale is identity
  local l="de_DE.ISO-8859-1"
  [ "$(locale_compose "$(locale_language "$l")" "$(locale_encoding "$l")")" == "$l" ]
}

# ── languages / encodings from a fixture SUPPORTED (ADR 0076) ───────────────

@test "locale_list_languages: codeset-stripped, sorted-unique" {
  mkdir -p "$FIXROOT/usr/share/i18n"
  printf '%s\n' 'en_US.UTF-8 UTF-8' 'en_US ISO-8859-1' 'de_DE.UTF-8 UTF-8' \
    'ja_JP.EUC-JP EUC-JP' > "$FIXROOT/usr/share/i18n/SUPPORTED"
  run locale_list_languages
  [ "$status" -eq 0 ]
  [ "$output" == "$(printf '%s\n' de_DE en_US ja_JP)" ]
}

@test "locale_list_encodings: only the charsets paired with the language" {
  mkdir -p "$FIXROOT/usr/share/i18n"
  printf '%s\n' 'en_US.UTF-8 UTF-8' 'en_US ISO-8859-1' 'ja_JP.EUC-JP EUC-JP' \
    > "$FIXROOT/usr/share/i18n/SUPPORTED"
  run locale_list_encodings en_US
  [ "$status" -eq 0 ]
  [ "$output" == "$(printf '%s\n' ISO-8859-1 UTF-8)" ]
  run locale_list_encodings ja_JP
  [ "$output" == "EUC-JP" ]
}

# ── console fonts (ADR 0076) ───────────────────────────────────────────────

@test "locale_list_console_fonts: names before the first dot, unique" {
  mkdir -p "$FIXROOT/usr/share/kbd/consolefonts"
  : > "$FIXROOT/usr/share/kbd/consolefonts/default8x16.psfu.gz"
  : > "$FIXROOT/usr/share/kbd/consolefonts/ter-116n.psf.gz"
  : > "$FIXROOT/usr/share/kbd/consolefonts/Lat2-Terminus16.psfu.gz"
  run locale_list_console_fonts
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | wc -l)" -eq 3 ]
  echo "$output" | grep -qx "default8x16"
  echo "$output" | grep -qx "ter-116n"
  echo "$output" | grep -qx "Lat2-Terminus16"
}

@test "locale_list_console_fonts: empty medium yields no output, rc 0" {
  run locale_list_console_fonts
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
