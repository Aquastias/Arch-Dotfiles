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

@test "HEAD failure: returns non-zero and does not download" {
  _iso_resolver_resolve_url() { return 1; }
  _iso_resolver_download() {
    DOWNLOAD_CALLS=$((DOWNLOAD_CALLS + 1))
    return 0
  }

  run iso_resolver_get "$DOWNLOADS_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "HEAD failed" ]]

  DOWNLOAD_CALLS=0
  iso_resolver_get "$DOWNLOADS_DIR" >/dev/null 2>&1 || true
  [ "$DOWNLOAD_CALLS" -eq 0 ]
}

# ── HEAD returns empty body ──────────────────────────────────────────────────

@test "HEAD empty: returns non-zero with a clear message" {
  _iso_resolver_resolve_url() { echo ""; }
  _iso_resolver_download() { return 0; }

  run iso_resolver_get "$DOWNLOADS_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "empty redirect" ]]
}

# ── HEAD returns non-iso URL ─────────────────────────────────────────────────

@test "HEAD non-iso URL: returns non-zero with a clear message" {
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
