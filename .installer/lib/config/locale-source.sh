#!/usr/bin/env bash
# =============================================================================
# lib/config/locale-source.sh — Locale option-source boundary (ADR 0076)
# =============================================================================
# The single, tested seam that enumerates the Locales Category leaves' option
# sets from the installer medium: console keymaps, locale languages, per-language
# encodings, and console fonts. Both Guided front-ends (the persistent-fzf
# controller's big-list picker and the headless replay editors) read these, so
# neither hardcodes a keymap/language/font list and the two can never drift.
#
# Testable in isolation: every filesystem source is rooted at ${LOCALE_SRC_ROOT}
# (empty ⇒ the live system). Tests point LOCALE_SRC_ROOT at a fixture tree so no
# real ISO — and no `localectl` — is required. On the live medium the systemd
# tools are preferred where they exist, with a filesystem fallback (a dev box
# where `localectl` returns nothing still enumerates).
#
# Pure w.r.t. its inputs: reads the medium only, no TTY, no Config State.
#
# Used by: lib/config/menu.sh.
# =============================================================================

# shellcheck source=./locale-parts.sh
declare -F locale_parts_encoding >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/locale-parts.sh"
# The name rules, beside locale-parts.sh.
_LOCALE_PARTS_AWK="${BASH_SOURCE[0]%/*}/locale-parts.awk"

# locale_source_keymaps — every console keymap the medium offers, one per line.
# Prefers `localectl list-keymaps`; falls back to the kbd keymaps tree (also the
# only source under a fixture root, where localectl is deliberately skipped).
locale_source_keymaps() {
  local root="${LOCALE_SRC_ROOT:-}" out="" files
  [[ -z "$root" ]] && out="$(localectl list-keymaps 2>/dev/null)"
  if [[ -z "$out" ]]; then
    files="$(find "${root}/usr/share/kbd/keymaps" -name '*.map.gz' \
      -printf '%f\n' 2>/dev/null)"
    # The keymap names (the file names without .map.gz), each once.
    out="$(printf '%s\n' "$files" | awk -v part=keymap -f "$_LOCALE_PARTS_AWK" \
      | sort -u)"
  fi
  [[ -n "$out" ]] && printf '%s\n' "$out"
  return 0
}

# The pure compose/decompose helpers (locale_parts_language /
# locale_parts_encoding / locale_parts_compose) live in locale-parts.sh, sourced
# above — the same rule the in-chroot identity module uses to derive the
# locale.gen charset.

# locale_source_languages — every language identity the medium's SUPPORTED
# locales offer (codeset stripped), sorted-unique. Falls back to `localectl
# list-locales`.
locale_source_languages() {
  local root="${LOCALE_SRC_ROOT:-}" supported_file out locales
  supported_file="${root}/usr/share/i18n/SUPPORTED"
  # The language of each SUPPORTED locale, each once.
  out="$(awk -v part=language -f "$_LOCALE_PARTS_AWK" "$supported_file" \
    2>/dev/null | sort -u)"
  if [[ -z "$out" && -z "$root" ]]; then
    locales="$(localectl list-locales 2>/dev/null)"
    # The language of each listed locale, each once.
    out="$(printf '%s\n' "$locales" \
      | awk -v part=language -f "$_LOCALE_PARTS_AWK" | sort -u)"
  fi
  [[ -n "$out" ]] && printf '%s\n' "$out"
  return 0
}

# locale_source_encodings <language> — the CODESETs SUPPORTED pairs with
# <language> (the charset column of every entry whose codeset-stripped name is
# <language>), sorted-unique. So the encoding leaf can only offer a charset that
# yields a generatable locale for the chosen language.
locale_source_encodings() {
  local language="$1" root="${LOCALE_SRC_ROOT:-}" supported_file
  supported_file="${root}/usr/share/i18n/SUPPORTED"
  # The charsets of that language's SUPPORTED lines, each once.
  awk -v part=charsets -v wanted="$language" -f "$_LOCALE_PARTS_AWK" \
    "$supported_file" 2>/dev/null | sort -u
  return 0
}

# locale_source_console_fonts — every virtual-console font installed on the
# medium (the kbd consolefonts, named as `setfont` wants — the basename before
# the first '.'), sorted-unique. The ISO and target font sets are identical (kbd
# ∈ base), so this is also the valid set for a committed system.console_font.
locale_source_console_fonts() {
  local root="${LOCALE_SRC_ROOT:-}" out files
  files="$(find "${root}/usr/share/kbd/consolefonts" -maxdepth 1 -name '*.gz' \
    -printf '%f\n' 2>/dev/null)"
  # The font names (each file name before its first .), each once.
  out="$(printf '%s\n' "$files" | awk -v part=font -f "$_LOCALE_PARTS_AWK" \
    | sort -u)"
  [[ -n "$out" ]] && printf '%s\n' "$out"
  return 0
}
