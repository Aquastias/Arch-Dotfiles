#!/usr/bin/env bats
# Tests for .installer/lib/config/timezone.sh — the Timezone resolver (ADR
# 0118): a pure helper turning system.timezone into the effective IANA zone —
# an explicit value wins, otherwise a validated geo-IP autodetect, otherwise
# Europe/Bucharest. The network fetch and the zoneinfo root are injectable so
# the resolver is exercised entirely offline.
#
# Behaviour under test (external only — the zone the helper produces), never
# internal structure. Prior art: tests/config/printing.bats.

setup() {
  # A fake zoneinfo tree so timezone_valid needs no real /usr/share/zoneinfo.
  ZI="$(mktemp -d)"
  mkdir -p "$ZI/Europe" "$ZI/America"
  : > "$ZI/Europe/Bucharest"
  : > "$ZI/Europe/Berlin"
  : > "$ZI/America/New_York"
  export TIMEZONE_ZONEINFO_DIR="$ZI"
  # shellcheck source=../../lib/config/timezone.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/timezone.sh"
}

teardown() { rm -rf "$ZI"; }

# ── explicit value wins ─────────────────────────────────────────────────────

@test "explicit system.timezone wins verbatim, no fetch" {
  export TIMEZONE_FETCH_CMD='echo SHOULD_NOT_RUN'
  local cfg='{"system":{"timezone":"America/New_York"}}'
  [ "$(timezone_resolve "$cfg")" = "America/New_York" ]
}

@test "explicit value is returned even if the fetch would differ" {
  export TIMEZONE_FETCH_CMD='echo Europe/Berlin'
  [ "$(timezone_resolve '{"system":{"timezone":"America/New_York"}}')" \
    = "America/New_York" ]
}

# ── autodetect when absent ──────────────────────────────────────────────────

@test "absent timezone: a valid geo-IP zone is used" {
  export TIMEZONE_FETCH_CMD='echo Europe/Berlin'
  [ "$(timezone_resolve '{"system":{}}')" = "Europe/Berlin" ]
  [ "$(timezone_resolve '{}')" = "Europe/Berlin" ]
}

@test "geo-IP reply is trimmed of surrounding whitespace" {
  export TIMEZONE_FETCH_CMD='printf "  Europe/Berlin \n"'
  [ "$(timezone_resolve '{}')" = "Europe/Berlin" ]
}

# ── fallback ────────────────────────────────────────────────────────────────

@test "invalid geo-IP zone falls back to Europe/Bucharest" {
  export TIMEZONE_FETCH_CMD='echo Not/AZone'
  [ "$(timezone_resolve '{}')" = "Europe/Bucharest" ]
}

@test "empty geo-IP reply (offline) falls back to Europe/Bucharest" {
  export TIMEZONE_FETCH_CMD='true'
  [ "$(timezone_resolve '{}')" = "Europe/Bucharest" ]
}

@test "path-traversal geo-IP reply is rejected, falls back" {
  export TIMEZONE_FETCH_CMD='echo ../../etc/shadow'
  [ "$(timezone_resolve '{}')" = "Europe/Bucharest" ]
}
