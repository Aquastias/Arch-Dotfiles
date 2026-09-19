#!/usr/bin/env bats
# Tests for .installer/lib/packages/archzfs-kernel.sh — the archzfs LTS Ceiling
# (ADR 0137). Pure decision + seamed ceiling lookup + orchestration. No network
# or real pacman: _archzfs_fetch_lts_assets / _mirror_lts_pkgver are overridden.

setup() {
  source "$BATS_TEST_DIRNAME/../../lib/common.sh"
  source "$BATS_TEST_DIRNAME/../../lib/packages/archzfs-kernel.sh"

  # Default seams — a real-shaped archzfs asset set and a mirror version.
  _archzfs_fetch_lts_assets() {
    printf '%s\n' \
      "zfs-linux-2.4.4_7.2.6.arch2.1-1-x86_64.pkg.tar.zst" \
      "zfs-linux-2.4.4_7.2.6.arch2.1-1-x86_64.pkg.tar.zst.sig" \
      "zfs-linux-lts-2.4.4_6.18.52.1-1-x86_64.pkg.tar.zst" \
      "zfs-linux-lts-2.4.4_6.18.52.1-1-x86_64.pkg.tar.zst.sig"
  }
  _mirror_lts_pkgver() { printf '6.18.52-1\n'; }
  export -f _archzfs_fetch_lts_assets _mirror_lts_pkgver
}

# ── archzfs_lts_pkgver: parse zfs-linux-lts, not zfs-linux ────────────────────

@test "archzfs_lts_pkgver: extracts the lts pkgver, restoring the pkgrel dash" {
  run archzfs_lts_pkgver
  [ "$status" -eq 0 ]
  [ "$output" = "6.18.52-1" ]
}

@test "archzfs_lts_pkgver: ignores the default-kernel zfs-linux asset" {
  # Only zfs-linux (7.x, default) assets present → no lts ceiling.
  _archzfs_fetch_lts_assets() {
    printf '%s\n' "zfs-linux-2.4.4_7.2.6.arch2.1-1-x86_64.pkg.tar.zst"
  }
  export -f _archzfs_fetch_lts_assets
  run archzfs_lts_pkgver
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "archzfs_lts_pkgver: picks the newest when several lts assets exist" {
  _archzfs_fetch_lts_assets() {
    printf '%s\n' \
      "zfs-linux-lts-2.4.3_6.12.48.1-1-x86_64.pkg.tar.zst" \
      "zfs-linux-lts-2.4.4_6.18.52.1-1-x86_64.pkg.tar.zst"
  }
  export -f _archzfs_fetch_lts_assets
  run archzfs_lts_pkgver
  [ "$output" = "6.18.52-1" ]
}

@test "archzfs_lts_pkgver: forced-skew override wins over the lookup" {
  ARCHZFS_LTS_CEILING_OVERRIDE="6.12.48-1" run archzfs_lts_pkgver
  [ "$output" = "6.12.48-1" ]
}

@test "archzfs_lts_pkgver: empty on lookup failure" {
  _archzfs_fetch_lts_assets() { return 0; }   # no assets
  export -f _archzfs_fetch_lts_assets
  run archzfs_lts_pkgver
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ── archzfs_pick_lts_version (pure) ──────────────────────────────────────────

@test "pick: mirror minor newer than supported → pin to supported" {
  run archzfs_pick_lts_version "6.18.52-1" "6.19.3-1"
  [ "$output" = "6.18.52-1" ]
}

@test "pick: mirror equal minor (newer patch) → no pin (patch-tolerant)" {
  run archzfs_pick_lts_version "6.18.52-1" "6.18.60-1"
  [ -z "$output" ]
}

@test "pick: mirror equal version → no pin" {
  run archzfs_pick_lts_version "6.18.52-1" "6.18.52-1"
  [ -z "$output" ]
}

@test "pick: mirror older minor → no pin" {
  run archzfs_pick_lts_version "6.18.52-1" "6.17.9-1"
  [ -z "$output" ]
}

@test "pick: numeric compare so 6.9 < 6.18 (not lexical)" {
  # supported 6.18, mirror 6.9 → mirror is OLDER, no pin.
  run archzfs_pick_lts_version "6.18.52-1" "6.9.20-1"
  [ -z "$output" ]
}

@test "pick: major bump is a pin" {
  run archzfs_pick_lts_version "6.18.52-1" "7.0.1-1"
  [ "$output" = "6.18.52-1" ]
}

# ── archzfs_resolve_lts_pin: orchestration ───────────────────────────────────

@test "resolve: mirror outran archzfs → pinned pacstrap specs" {
  _mirror_lts_pkgver() { printf '6.19.3-1\n'; }
  export -f _mirror_lts_pkgver
  run archzfs_resolve_lts_pin
  [ "$status" -eq 0 ]
  [ "$output" = "linux-lts=6.18.52-1 linux-lts-headers=6.18.52-1" ]
}

@test "resolve: mirror at ceiling → nothing (happy path no-op)" {
  run archzfs_resolve_lts_pin
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "resolve: ceiling lookup unreachable → nothing (degrade)" {
  _archzfs_fetch_lts_assets() { return 1; }
  export -f _archzfs_fetch_lts_assets
  run archzfs_resolve_lts_pin
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "resolve: mirror lookup unreachable → nothing (degrade)" {
  _mirror_lts_pkgver() { return 1; }
  export -f _mirror_lts_pkgver
  run archzfs_resolve_lts_pin
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
