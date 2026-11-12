#!/usr/bin/env bats
# The Audit Cache's installer seam (ADR 0152, test-only env): the Feature
# Audit harness points a variant's pacman at the base variant's packages,
# and the installed system's pacman.conf ends up as shipped.

load ../lib/text-helpers

setup() {
  T="$(mktemp -d)"
  info() { :; }; warn() { :; }
  # shellcheck source=../../lib/packages/pacman-config.sh
  source "$BATS_TEST_DIRNAME/../../lib/packages/pacman-config.sh"
  C="$T/pacman.conf"
  printf '%s\n' '[options]' 'HoldPkg = pacman' '' '[core]' \
    'Include = /etc/pacman.d/mirrorlist' '' '[extra]' \
    'Include = /etc/pacman.d/mirrorlist' > "$C"
  cp "$C" "$T/orig"
}

teardown() { rm -rf "$T"; }

@test "no cache env: pacman.conf untouched" {
  pacman_config_apply_audit_cache "$C"
  cmp -s "$C" "$T/orig"
}

@test "cache server lands in every repo section, never [options]" {
  INSTALL_PKG_CACHE_SERVER=http://gw/c pacman_config_apply_audit_cache "$C"
  [ "$(grep -c '^CacheServer = http://gw/c$' "$C")" -eq 2 ]
  local core
  # Line 2, and the line right after [core].
  [ "$(head -n 2 "$C" | tail -n 1)" = 'HoldPkg = pacman' ]
  core="$(first_line_matching "$C" '^\[core\]$')"
  [ "$(head -n "$((core + 1))" "$C" | tail -n 1)" = 'CacheServer = http://gw/c' ]
}

@test "the AUR cache becomes an [audit-aur] repo" {
  INSTALL_AUDIT_AUR_URL=http://gw/a pacman_config_apply_audit_cache "$C"
  local section block
  section="$(first_line_matching "$C" '^\[audit-aur\]$')"
  # The two lines after the [audit-aur] header.
  block="$(head -n "$((section + 2))" "$C" | tail -n 2)"
  text_has_line "$block" 'Server = http://gw/a'
  text_has_line "$block" 'SigLevel = Optional TrustAll'
}

@test "strip restores the shipped pacman.conf" {
  INSTALL_PKG_CACHE_SERVER=http://gw/c INSTALL_AUDIT_AUR_URL=http://gw/a \
    pacman_config_apply_audit_cache "$C"
  pacman_config_strip_audit_cache "$C"
  cmp -s "$C" "$T/orig"
}
