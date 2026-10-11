#!/usr/bin/env bash
# =============================================================================
# lib/config/locale-parts.sh — locale compose / decompose (ADR 0076)
# =============================================================================
# The canonical `system.locale` is one locale.gen name (e.g. en_US.UTF-8); the
# `language` and `encoding` leaves are two views of it. These three pure helpers
# are the SOLE owner of the split. Dependency-free by design so both sides of
# the install can share one rule: the host Menu model / Guided controller (via
# locale-source.sh) AND the in-chroot identity module (staged into lib-chroot,
# where it derives the locale.gen charset column). A doubled charset
# (en_US.UTF-8.UTF-8) is therefore impossible from either side.
#
# Used by: lib/config/locale-source.sh, lib/chroot/identity.sh (staged by
# lib/chroot.sh).
# =============================================================================

[[ -n "${_LOCALE_PARTS_SH_SOURCED:-}" ]] && return 0
_LOCALE_PARTS_SH_SOURCED=1

# locale_parts_language <locale> → the language identity: the name with its
# .CODESET dropped, any @modifier kept. en_US.UTF-8→en_US,
# sr_RS.UTF-8@latin→sr_RS@latin.
locale_parts_language() {
  awk '{ sub(/\.[^.@]*/, ""); print }' <<<"$1"
}

# locale_parts_encoding <locale> → the CODESET (between . and any @), empty if
# none.
locale_parts_encoding() {
  awk 'match($0, /\.[^.@]*/) { print substr($0, RSTART + 1, RLENGTH - 1) }' \
    <<<"$1"
}

# locale_parts_compose <language> <encoding> → the locale.gen name: <encoding>
# spliced in before any @modifier. Empty <encoding> yields the bare language.
# Exactly one codeset is ever present, so recomposing an already-composed value
# is a no-op.
locale_parts_compose() {
  local language="$1" encoding="$2"
  [[ -n "$encoding" ]] || { printf '%s\n' "$language"; return; }
  if [[ "$language" == *@* ]]; then
    printf '%s.%s@%s\n' "${language%%@*}" "$encoding" "${language#*@}"
  else
    printf '%s.%s\n' "$language" "$encoding"
  fi
}
