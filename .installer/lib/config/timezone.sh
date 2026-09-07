#!/usr/bin/env bash
# =============================================================================
# lib/config/timezone.sh — Timezone resolver (ADR 0118)
# =============================================================================
# Pure resolver turning a config's `system.timezone` into the effective zone:
# an explicit/guided value wins; otherwise the zone is autodetected by geo-IP;
# otherwise it falls back to Europe/Bucharest. Mirrors the Printing Service
# resolver (printing.sh): JSON in, decision out, no TTY, no disk writes.
#
# The network fetch is behind an injectable seam so the resolver is testable
# offline: TIMEZONE_FETCH_CMD overrides the geo-IP call and TIMEZONE_ZONEINFO_DIR
# overrides the zoneinfo root the validity check reads.
#
# Public API:
#   timezone_resolve <config-json> → the effective IANA zone (one line)
# =============================================================================

# timezone_fetch — print the geo-IP IANA zone, or nothing on any failure. A
# bounded curl mirroring the guided-controller idiom so an offline install
# never hangs. Injectable via TIMEZONE_FETCH_CMD (tests set it, no network).
timezone_fetch() {
  if [[ -n "${TIMEZONE_FETCH_CMD:-}" ]]; then
    eval "$TIMEZONE_FETCH_CMD"
    return
  fi
  curl -fsSL --connect-timeout 2 --max-time 8 \
    https://ipapi.co/timezone 2>/dev/null
}

# timezone_valid <zone> — true when <zone> names a real zoneinfo entry. Rejects
# empty and any path-traversal so a hostile/garbled geo-IP reply cannot point
# /etc/localtime outside the zoneinfo tree. Root overridable for tests.
timezone_valid() {
  local z="$1" dir="${TIMEZONE_ZONEINFO_DIR:-/usr/share/zoneinfo}"
  [[ -n "$z" && "$z" != *..* && -f "$dir/$z" ]]
}

# timezone_resolve <config-json> — the effective zone (ADR 0118). An explicit
# `.system.timezone` wins verbatim (guided/profile already own it); otherwise a
# validated geo-IP autodetect; otherwise Europe/Bucharest. The fallback keeps an
# offline install functional.
timezone_resolve() {
  local cfg="${1:-{\}}" explicit detected
  explicit="$(jq -r '.system.timezone // empty' <<<"$cfg" 2>/dev/null)"
  if [[ -n "$explicit" ]]; then
    printf '%s\n' "$explicit"
    return 0
  fi
  detected="$(timezone_fetch | head -n1 | tr -d '[:space:]')"
  if timezone_valid "$detected"; then
    printf '%s\n' "$detected"
    return 0
  fi
  printf '%s\n' "Europe/Bucharest"
}
