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

# ── archzfs_lts_pin_cleanup: the pin repo must never leak into the target ──────

_write_conf_with_pin() {
  cat > "$1" <<'CONF'
[core]
Include = /etc/pacman.d/mirrorlist

# archzfs LTS ceiling pin (ADR 0137) — the exact linux-lts the mirror no longer
# carries, so the version-pinned pacstrap spec resolves. Local, unsigned.
[archzfs-lts-pin]
SigLevel = Never
Server = file:///var/cache/archzfs-lts-pin

[extra]
Include = /etc/pacman.d/mirrorlist
CONF
}

@test "cleanup removes the pin repo block, keeps other repos" {
  local conf; conf="$(mktemp)"
  _write_conf_with_pin "$conf"
  run archzfs_lts_pin_cleanup "$conf"
  [ "$status" -eq 0 ]
  ! grep -q 'archzfs-lts-pin' "$conf"     # block + comments gone
  grep -q '^\[core\]' "$conf"             # untouched
  grep -q '^\[extra\]' "$conf"            # untouched
  rm -f "$conf"
}

@test "cleanup is idempotent / no-op when the block is absent" {
  local conf; conf="$(mktemp)"
  printf '[core]\nInclude = /x\n' > "$conf"
  run archzfs_lts_pin_cleanup "$conf"
  [ "$status" -eq 0 ]
  grep -q '^\[core\]' "$conf"
  rm -f "$conf"
}

# ── archzfs_pin_candidates: newest-first, at/below the ceiling (ADR 0139) ─────

@test "pin_candidates: only versions <= ceiling major.minor, newest first" {
  _archzfs_fetch_archive_lts_versions() {
    printf '%s\n' 6.12.74-1 6.12.75-1 6.17.9-1 6.18.51-1 6.18.52-1 6.19.1-1
  }
  export -f _archzfs_fetch_archive_lts_versions
  run archzfs_pin_candidates "6.18.52-1"
  [ "$status" -eq 0 ]
  # 6.19.1 excluded (minor > 6.18); rest newest-first
  [ "${lines[0]}" = "6.18.52-1" ]
  [ "${lines[1]}" = "6.18.51-1" ]
  ! printf '%s\n' "${lines[@]}" | grep -qx "6.19.1-1"
  printf '%s\n' "${lines[@]}" | grep -qx "6.12.75-1"
}

# ── build_repo: fall back to the closest available compatible version ─────────

@test "build_repo: exact version fetches → pins to it" {
  local dir; dir="$(mktemp -d)"; local conf; conf="$(mktemp)"
  printf '[options]\n' > "$conf"
  _archzfs_fetch_archive_lts_versions() { printf '6.18.52-1\n'; }
  pkg_fetch_from_archive() { : > "$3"; return 0; }   # every fetch succeeds
  repo-add() { return 0; }
  pacman() { return 0; }
  export -f _archzfs_fetch_archive_lts_versions pkg_fetch_from_archive repo-add pacman
  PACMAN_CONF="$conf" run _archzfs_lts_pin_build_repo "6.18.52-1" "$dir"
  [ "$status" -eq 0 ]
  [ "$output" = "6.18.52-1" ]
  rm -rf "$dir" "$conf"
}

@test "build_repo: exact missing → uses closest available compatible" {
  local dir; dir="$(mktemp -d)"; local conf; conf="$(mktemp)"
  printf '[options]\n' > "$conf"
  _archzfs_fetch_archive_lts_versions() { printf '%s\n' 6.18.50-1 6.18.52-1; }
  # The requested 6.18.52 fails; 6.18.50 (next candidate) succeeds.
  pkg_fetch_from_archive() {
    case "$2" in 6.18.52-1) return 1;; *) : > "$3"; return 0;; esac
  }
  repo-add() { return 0; }
  pacman() { return 0; }
  export -f _archzfs_fetch_archive_lts_versions pkg_fetch_from_archive repo-add pacman
  PACMAN_CONF="$conf" run _archzfs_lts_pin_build_repo "6.18.52-1" "$dir"
  [ "$status" -eq 0 ]
  [ "$output" = "6.18.50-1" ]         # fell back to the closest available
  grep -q '^\[archzfs-lts-pin\]' "$conf"
  rm -rf "$dir" "$conf"
}

@test "build_repo: nothing fetchable → non-zero (caller degrades)" {
  local dir; dir="$(mktemp -d)"; local conf; conf="$(mktemp)"
  printf '[options]\n' > "$conf"
  _archzfs_fetch_archive_lts_versions() { printf '6.18.52-1\n'; }
  pkg_fetch_from_archive() { return 1; }   # all fetches fail
  repo-add() { return 0; }; pacman() { return 0; }
  export -f _archzfs_fetch_archive_lts_versions pkg_fetch_from_archive repo-add pacman
  PACMAN_CONF="$conf" run _archzfs_lts_pin_build_repo "6.18.52-1" "$dir"
  [ "$status" -ne 0 ]
  [ -z "$output" ]
  rm -rf "$dir" "$conf"
}
