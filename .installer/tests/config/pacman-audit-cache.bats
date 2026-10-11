#!/usr/bin/env bats
# The Audit Cache's installer seam (ADR 0152, test-only env): the Feature
# Audit harness points a variant's pacman at the base variant's packages,
# and the installed system's pacman.conf ends up as shipped.

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
  [ "$(awk 'NR == 2 { print; exit }' "$C")" = 'HoldPkg = pacman' ]
  [ "$(awk 'previous == "[core]" { print; exit } { previous = $0 }' "$C")" = 'CacheServer = http://gw/c' ]
}

@test "the AUR cache becomes an [audit-aur] repo" {
  INSTALL_AUDIT_AUR_URL=http://gw/a pacman_config_apply_audit_cache "$C"
  grep -A2 -x '\[audit-aur\]' "$C" | grep -qx 'Server = http://gw/a'
  grep -A2 -x '\[audit-aur\]' "$C" | grep -qx 'SigLevel = Optional TrustAll'
}

@test "strip restores the shipped pacman.conf" {
  INSTALL_PKG_CACHE_SERVER=http://gw/c INSTALL_AUDIT_AUR_URL=http://gw/a \
    pacman_config_apply_audit_cache "$C"
  pacman_config_strip_audit_cache "$C"
  cmp -s "$C" "$T/orig"
}
