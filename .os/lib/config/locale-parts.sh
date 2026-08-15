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
# =============================================================================

[[ -n "${_LOCALE_PARTS_SH_SOURCED:-}" ]] && return 0
_LOCALE_PARTS_SH_SOURCED=1

# locale_language <locale> → the language identity: the name with its .CODESET
# dropped, any @modifier kept. en_US.UTF-8→en_US, sr_RS.UTF-8@latin→sr_RS@latin.
locale_language() { sed 's/\.[^.@]*//' <<<"$1"; }

# locale_encoding <locale> → the CODESET (between . and any @), empty if none.
locale_encoding() { sed -n 's/[^.]*\.\([^.@]*\).*/\1/p' <<<"$1"; }

# locale_compose <language> <encoding> → the locale.gen name: <encoding> spliced
# in before any @modifier. Empty <encoding> yields the bare language. Exactly one
# codeset is ever present, so recomposing an already-composed value is a no-op.
locale_compose() {
  local lang="$1" enc="$2"
  [[ -n "$enc" ]] || { printf '%s\n' "$lang"; return; }
  if [[ "$lang" == *@* ]]; then
    printf '%s.%s@%s\n' "${lang%%@*}" "$enc" "${lang#*@}"
  else
    printf '%s.%s\n' "$lang" "$enc"
  fi
}
