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
# =============================================================================

# shellcheck source=./locale-parts.sh
[[ "$(type -t locale_encoding)" == "function" ]] \
  || source "${BASH_SOURCE[0]%/*}/locale-parts.sh"

# locale_list_keymaps — every console keymap the medium offers, one per line.
# Prefers `localectl list-keymaps`; falls back to the kbd keymaps tree (also the
# only source under a fixture root, where localectl is deliberately skipped).
locale_list_keymaps() {
  local root="${LOCALE_SRC_ROOT:-}" out=""
  [[ -z "$root" ]] && out="$(localectl list-keymaps 2>/dev/null)"
  [[ -n "$out" ]] || out="$(find "${root}/usr/share/kbd/keymaps" \
    -name '*.map.gz' -printf '%f\n' 2>/dev/null | sed 's/\.map\.gz$//' | sort -u)"
  [[ -n "$out" ]] && printf '%s\n' "$out"
  return 0
}

# The pure compose/decompose helpers (locale_language / locale_encoding /
# locale_compose) live in locale-parts.sh, sourced above — the same rule the
# in-chroot identity module uses to derive the locale.gen charset.

# locale_list_languages — every language identity the medium's SUPPORTED locales
# offer (codeset stripped), sorted-unique. Falls back to `localectl list-locales`.
locale_list_languages() {
  local root="${LOCALE_SRC_ROOT:-}" f out
  f="${root}/usr/share/i18n/SUPPORTED"
  out="$(awk '{print $1}' "$f" 2>/dev/null | sed 's/\.[^.@]*//' | sort -u)"
  [[ -z "$out" && -z "$root" ]] \
    && out="$(localectl list-locales 2>/dev/null | sed 's/\.[^.@]*//' | sort -u)"
  [[ -n "$out" ]] && printf '%s\n' "$out"
  return 0
}

# locale_list_encodings <language> — the CODESETs SUPPORTED pairs with <language>
# (the charset column of every entry whose codeset-stripped name is <language>),
# sorted-unique. So the encoding leaf can only offer a charset that yields a
# generatable locale for the chosen language.
locale_list_encodings() {
  local lang="$1" root="${LOCALE_SRC_ROOT:-}" f
  f="${root}/usr/share/i18n/SUPPORTED"
  awk -v lang="$lang" '
    { name = $1; enc = $2; sub(/\.[^.@]*/, "", name)
      if (name == lang && enc != "") print enc }' "$f" 2>/dev/null | sort -u
  return 0
}

# locale_list_console_fonts — every virtual-console font installed on the medium
# (the kbd consolefonts, named as `setfont` wants — the basename before the first
# '.'), sorted-unique. The ISO and target font sets are identical (kbd ∈ base),
# so this is also the valid set for a committed system.console_font.
locale_list_console_fonts() {
  local root="${LOCALE_SRC_ROOT:-}" out
  out="$(find "${root}/usr/share/kbd/consolefonts" -maxdepth 1 -name '*.gz' \
    -printf '%f\n' 2>/dev/null | sed 's/\..*//' | sort -u)"
  [[ -n "$out" ]] && printf '%s\n' "$out"
  return 0
}
