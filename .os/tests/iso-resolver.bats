#!/usr/bin/env bats
# Tests for .os/lib/iso-resolver.sh — latest-Arch-ISO resolver.
#
# Test strategy: override the two internal seams
# (_iso_resolver_resolve_url, _iso_resolver_download) to simulate HEAD
# responses and downloads without hitting the network.

setup() {
  TEST_DIR="$(mktemp -d)"
  DOWNLOADS_DIR="$TEST_DIR/dl"
  mkdir -p "$DOWNLOADS_DIR"

  # shellcheck source=../lib/iso-resolver.sh
  source "$BATS_TEST_DIRNAME/../lib/iso-resolver.sh"

  FAKE_FILENAME="archlinux-2099.01.01-x86_64.iso"
  FAKE_URL="https://mirror.example.com/iso/2099.01.01/${FAKE_FILENAME}"

  # Track whether the downloader was invoked, so we can assert cache-hit
  # short-circuits before reaching it.
  DOWNLOAD_CALLS=0
}

teardown() {
  rm -rf "$TEST_DIR"
}

# ── cache hit: file already present, no download ─────────────────────────────

@test "cache-hit: returns existing path and does not download" {
  _iso_resolver_resolve_url() { echo "$FAKE_URL"; }
  _iso_resolver_download() {
    DOWNLOAD_CALLS=$((DOWNLOAD_CALLS + 1))
    return 0
  }
  : > "$DOWNLOADS_DIR/$FAKE_FILENAME"

  run iso_resolver_get "$DOWNLOADS_DIR"
  [ "$status" -eq 0 ]
  [ "$output" = "$DOWNLOADS_DIR/$FAKE_FILENAME" ]

  # Re-source-and-call pattern means we can't read DOWNLOAD_CALLS from `run`'s
  # subshell. Instead, assert by side-effect: if the download had run, the
  # file would have been replaced. Use a separate invocation that observes
  # the call count directly.
  DOWNLOAD_CALLS=0
  iso_resolver_get "$DOWNLOADS_DIR" >/dev/null
  [ "$DOWNLOAD_CALLS" -eq 0 ]
}

# ── cache miss: file absent, downloader is invoked ───────────────────────────

@test "cache-miss: downloads via the latest URL and returns the new path" {
  _iso_resolver_resolve_url() { echo "$FAKE_URL"; }
  _iso_resolver_download() {
    DOWNLOAD_CALLS=$((DOWNLOAD_CALLS + 1))
    : > "$2" # simulate a fetched file at DEST
    return 0
  }

  run iso_resolver_get "$DOWNLOADS_DIR"
  [ "$status" -eq 0 ]
  [ "$output" = "$DOWNLOADS_DIR/$FAKE_FILENAME" ]
  [ -f "$DOWNLOADS_DIR/$FAKE_FILENAME" ]

  DOWNLOAD_CALLS=0
  rm -f "$DOWNLOADS_DIR/$FAKE_FILENAME"
  iso_resolver_get "$DOWNLOADS_DIR" >/dev/null
  [ "$DOWNLOAD_CALLS" -eq 1 ]
}

# ── HEAD failure: non-zero exit, no silent fallback ──────────────────────────

@test "lookup failure: returns non-zero and does not download" {
  _iso_resolver_resolve_url() { return 1; }
  _iso_resolver_download() {
    DOWNLOAD_CALLS=$((DOWNLOAD_CALLS + 1))
    return 0
  }

  run iso_resolver_get "$DOWNLOADS_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "lookup failed" ]]

  DOWNLOAD_CALLS=0
  iso_resolver_get "$DOWNLOADS_DIR" >/dev/null 2>&1 || true
  [ "$DOWNLOAD_CALLS" -eq 0 ]
}

# ── HEAD returns empty body ──────────────────────────────────────────────────

@test "lookup empty: returns non-zero with a clear message" {
  _iso_resolver_resolve_url() { echo ""; }
  _iso_resolver_download() { return 0; }

  run iso_resolver_get "$DOWNLOADS_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "empty result" ]]
}

# ── HEAD returns non-iso URL ─────────────────────────────────────────────────

@test "non-iso URL: returns non-zero with a clear message" {
  _iso_resolver_resolve_url() { echo "https://mirror.example.com/index.html"; }
  _iso_resolver_download() { return 0; }

  run iso_resolver_get "$DOWNLOADS_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "no .iso filename" ]]
}

# ── missing downloads dir is hard error (not auto-created) ───────────────────

@test "missing downloads dir: returns non-zero" {
  _iso_resolver_resolve_url() { echo "$FAKE_URL"; }
  _iso_resolver_download() { return 0; }

  run iso_resolver_get "$TEST_DIR/does-not-exist"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "does not exist" ]]
}

# ── download failure surfaces, target file is not left behind ────────────────

@test "download failure: returns non-zero and no stale file" {
  _iso_resolver_resolve_url() { echo "$FAKE_URL"; }
  _iso_resolver_download() { return 1; }

  run iso_resolver_get "$DOWNLOADS_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "download failed" ]]
  [ ! -f "$DOWNLOADS_DIR/$FAKE_FILENAME" ]
}


# ── ZFS-compatible resolver: picks newest matching ISO ───────────────────────

# Stable releases JSON used across compat tests. Newest-first; mix of
# available/unavailable to verify both filters apply.
COMPAT_RELEASES_JSON='{
  "releases": [
    {"version": "2099.05.01", "kernel_version": "7.0.3",
     "iso_url": "/iso/2099.05.01/archlinux-2099.05.01-x86_64.iso",
     "available": true},
    {"version": "2099.04.01", "kernel_version": "6.19.10",
     "iso_url": "/iso/2099.04.01/archlinux-2099.04.01-x86_64.iso",
     "available": true},
    {"version": "2099.03.01", "kernel_version": "6.19.5",
     "iso_url": "/iso/2099.03.01/archlinux-2099.03.01-x86_64.iso",
     "available": false},
    {"version": "2099.02.01", "kernel_version": "6.18.13",
     "iso_url": "/iso/2099.02.01/archlinux-2099.02.01-x86_64.iso",
     "available": true}
  ]
}'

@test "compat: picks newest available ISO matching archzfs major.minor" {
  _iso_resolver_fetch_archzfs_kernels() { printf '6.19\n'; }
  _iso_resolver_fetch_arch_releases() { echo "$COMPAT_RELEASES_JSON"; }
  _iso_resolver_download() {
    : > "$2"
    return 0
  }

  run iso_resolver_get_zfs_compatible "$DOWNLOADS_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"/archlinux-2099.04.01-x86_64.iso" ]]
  [ -f "$DOWNLOADS_DIR/archlinux-2099.04.01-x86_64.iso" ]
}

@test "compat: skips unavailable releases even if kernel matches" {
  # archzfs supports 6.19 — newest available 6.19.x is .04.01; .03.01 is
  # available=false and must be skipped despite same major.minor.
  _iso_resolver_fetch_archzfs_kernels() { printf '6.19\n'; }
  _iso_resolver_fetch_arch_releases() { echo "$COMPAT_RELEASES_JSON"; }
  _iso_resolver_download() {
    : > "$2"
    return 0
  }

  run iso_resolver_get_zfs_compatible "$DOWNLOADS_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"/archlinux-2099.04.01-x86_64.iso" ]]
}

@test "compat: falls back to older major.minor when newer unsupported" {
  # archzfs only knows 6.18 → newest matching ISO is .02.01 (6.18.13).
  _iso_resolver_fetch_archzfs_kernels() { printf '6.18\n'; }
  _iso_resolver_fetch_arch_releases() { echo "$COMPAT_RELEASES_JSON"; }
  _iso_resolver_download() {
    : > "$2"
    return 0
  }

  run iso_resolver_get_zfs_compatible "$DOWNLOADS_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"/archlinux-2099.02.01-x86_64.iso" ]]
}

@test "compat: cache hit short-circuits download" {
  _iso_resolver_fetch_archzfs_kernels() { printf '6.19\n'; }
  _iso_resolver_fetch_arch_releases() { echo "$COMPAT_RELEASES_JSON"; }
  CALLS=0
  _iso_resolver_download() {
    CALLS=$((CALLS + 1))
    return 0
  }
  : > "$DOWNLOADS_DIR/archlinux-2099.04.01-x86_64.iso"

  iso_resolver_get_zfs_compatible "$DOWNLOADS_DIR" >/dev/null
  [ "$CALLS" -eq 0 ]
}

@test "compat: archzfs lookup failure returns non-zero with clear message" {
  _iso_resolver_fetch_archzfs_kernels() { return 1; }
  _iso_resolver_fetch_arch_releases() { echo "$COMPAT_RELEASES_JSON"; }
  _iso_resolver_download() { return 0; }

  run iso_resolver_get_zfs_compatible "$DOWNLOADS_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "archzfs supported-kernel lookup failed" ]]
}

@test "compat: archzfs returns empty kernel list — refuses to guess" {
  _iso_resolver_fetch_archzfs_kernels() { :; }
  _iso_resolver_fetch_arch_releases() { echo "$COMPAT_RELEASES_JSON"; }
  _iso_resolver_download() { return 0; }

  run iso_resolver_get_zfs_compatible "$DOWNLOADS_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "no archzfs prebuilt kernels detected" ]]
}

@test "compat: arch releases lookup failure returns non-zero" {
  _iso_resolver_fetch_archzfs_kernels() { printf '6.19\n'; }
  _iso_resolver_fetch_arch_releases() { return 1; }
  _iso_resolver_download() { return 0; }

  run iso_resolver_get_zfs_compatible "$DOWNLOADS_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "archlinux.org releases lookup failed" ]]
}

@test "compat: no available release matches — clear error names the kernels" {
  # archzfs claims to support 5.10, none of the test releases are 5.10.x.
  _iso_resolver_fetch_archzfs_kernels() { printf '5.10\n'; }
  _iso_resolver_fetch_arch_releases() { echo "$COMPAT_RELEASES_JSON"; }
  _iso_resolver_download() { return 0; }

  run iso_resolver_get_zfs_compatible "$DOWNLOADS_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "no available archived ISO matches archzfs kernels" ]]
  [[ "$output" =~ "5.10" ]]
}

@test "compat: 6.19 must NOT match 6.190.x — anchored major.minor" {
  # Regression guard: a naive substring match would let archzfs 6.19 pick
  # an ISO with kernel 6.190.x. The pick must require a literal `.` after
  # the major.minor.
  _iso_resolver_fetch_archzfs_kernels() { printf '6.19\n'; }
  _iso_resolver_fetch_arch_releases() { cat <<'JSON'
{"releases": [
  {"version":"2099.06.01","kernel_version":"6.190.5",
   "iso_url":"/iso/2099.06.01/archlinux-2099.06.01-x86_64.iso",
   "available":true}
]}
JSON
  }
  _iso_resolver_download() { return 0; }

  run iso_resolver_get_zfs_compatible "$DOWNLOADS_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "no available archived ISO matches" ]]
}

@test "compat: missing downloads dir returns non-zero" {
  _iso_resolver_fetch_archzfs_kernels() { printf '6.19\n'; }
  _iso_resolver_fetch_arch_releases() { echo "$COMPAT_RELEASES_JSON"; }
  _iso_resolver_download() { return 0; }

  run iso_resolver_get_zfs_compatible "$TEST_DIR/does-not-exist"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "does not exist" ]]
}
