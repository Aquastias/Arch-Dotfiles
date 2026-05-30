#!/usr/bin/env bats
# Tests for .os/tools/fetch-iso.sh — the human-facing fetcher for the
# archzfs-Compatible ISO.
#
# Test strategy: the tool is sourceable (its main is guarded by
# BASH_SOURCE == $0), so we source it and exercise its functions with the
# resolver/verify seams stubbed. HOME is redirected so the ~/Downloads
# default lands in a temp dir.

setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR/home"

  # shellcheck source=../tools/fetch-iso.sh
  source "$BATS_TEST_DIRNAME/../tools/fetch-iso.sh"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# ── output directory resolution ──────────────────────────────────────────────

@test "out-dir: no arg defaults to ~/Downloads and creates it" {
  run fetch_iso_out_dir
  [ "$status" -eq 0 ]
  [ "$output" = "$HOME/Downloads" ]
  [ -d "$HOME/Downloads" ]
}

@test "out-dir: positional arg is used and created" {
  out="$TEST_DIR/custom/iso-out"
  run fetch_iso_out_dir "$out"
  [ "$status" -eq 0 ]
  [ "$output" = "$out" ]
  [ -d "$out" ]
}

# ── orchestration: resolve → verify → print / cleanup ────────────────────────

@test "run: resolve+verify ok prints path and flash hint, keeps file" {
  out="$TEST_DIR/dl"
  mkdir -p "$out"
  # NB: avoid the name `iso` here — it collides (dynamic scope) with the
  # local `iso` inside fetch_iso_run, blanking it when the stub runs.
  iso_path="$out/archlinux-2099.04.01-x86_64.iso"
  iso_resolver_get_zfs_compatible() {
    : > "$iso_path"
    printf '%s\n' "$iso_path"
  }
  iso_resolver_verify_sha256() { return 0; }

  run fetch_iso_run "$out"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$iso_path"* ]]
  [[ "$output" == *"dd if="* ]]
  [ -f "$iso_path" ]
}

@test "run: checksum mismatch removes the file and returns non-zero" {
  out="$TEST_DIR/dl"
  mkdir -p "$out"
  iso_path="$out/archlinux-2099.04.01-x86_64.iso"
  iso_resolver_get_zfs_compatible() {
    : > "$iso_path"
    printf '%s\n' "$iso_path"
  }
  iso_resolver_verify_sha256() { return 1; }

  run fetch_iso_run "$out"
  [ "$status" -ne 0 ]
  [ ! -f "$iso_path" ]
}
