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
