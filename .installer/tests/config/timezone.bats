#!/usr/bin/env bats
# Tests for .installer/lib/config/timezone.sh — the Timezone resolver (ADR
# 0118): a pure helper turning system.timezone into the effective IANA zone —
# an explicit value wins, otherwise a validated geo-IP autodetect, otherwise
# UTC (neutral, ADR 0157). The network fetch (timezone_fetch, overridden) and
# the zoneinfo root are injectable, so the resolver runs entirely offline.
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
  timezone_fetch() { echo SHOULD_NOT_RUN; }
  local config='{"system":{"timezone":"America/New_York"}}'
  [ "$(timezone_resolve "$config")" = "America/New_York" ]
}

@test "explicit value is returned even if the fetch would differ" {
  timezone_fetch() { echo Europe/Berlin; }
  [ "$(timezone_resolve '{"system":{"timezone":"America/New_York"}}')" \
    = "America/New_York" ]
}

# ── autodetect when absent ──────────────────────────────────────────────────

@test "absent timezone: a valid geo-IP zone is used" {
  timezone_fetch() { echo Europe/Berlin; }
  [ "$(timezone_resolve '{"system":{}}')" = "Europe/Berlin" ]
  [ "$(timezone_resolve '{}')" = "Europe/Berlin" ]
}

@test "geo-IP reply is trimmed of surrounding whitespace" {
  timezone_fetch() { printf "  Europe/Berlin \n"; }
  [ "$(timezone_resolve '{}')" = "Europe/Berlin" ]
}

# ── fallback ────────────────────────────────────────────────────────────────

@test "invalid geo-IP zone falls back to UTC" {
  timezone_fetch() { echo Not/AZone; }
  [ "$(timezone_resolve '{}')" = "UTC" ]
}

@test "empty geo-IP reply (offline) falls back to UTC" {
  timezone_fetch() { true; }
  [ "$(timezone_resolve '{}')" = "UTC" ]
}

@test "path-traversal geo-IP reply is rejected, falls back" {
  timezone_fetch() { echo ../../etc/shadow; }
  [ "$(timezone_resolve '{}')" = "UTC" ]
}
