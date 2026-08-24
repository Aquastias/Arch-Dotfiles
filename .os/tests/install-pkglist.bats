#!/usr/bin/env bats
# tools/install-pkglist.sh must resolve the AUR Helper (paru preferred, yay
# fallback) rather than hardcode paru, and die clearly when neither exists
# (ADR 0052). Runs the real script under an isolated PATH with fake helpers.

setup() {
  T="$(mktemp -d)"
  # Minimal OS tree the script walks: tools/<script>, hosts/<h>/pkglist-repo.txt
  mkdir -p "$T/os/tools" "$T/os/lib" "$T/os/hosts/h"
  cp "$BATS_TEST_DIRNAME/../tools/install-pkglist.sh" "$T/os/tools/"
  cp "$BATS_TEST_DIRNAME/../lib/aur-helper.sh" "$T/os/lib/"   # sourced by the tool
  printf 'ripgrep\n' > "$T/os/hosts/h/pkglist-repo.txt"
  printf 'brave-bin\n' > "$T/os/hosts/h/pkglist-aur.txt"

  # Isolated bin: only the externals the script needs, plus opt-in fake helpers.
  BIN="$T/bin"; mkdir -p "$BIN"
  ln -s "$(command -v bash)" "$BIN/bash"
  ln -s "$(command -v dirname)" "$BIN/dirname"
  export CALLED="$T/called"; : > "$CALLED"
}

teardown() { rm -rf "$T"; }

# Drop a fake helper that records its name and exits 0. It drains stdin first
# (like the real `paru/yay -S -`): the script pipes the package list in, so a
# helper that exits without reading it races the producer to SIGPIPE under load
# (set -o pipefail then fails the script).
_fake_helper() {
  local name="$1"
  printf '#!/bin/sh\ncat >/dev/null 2>&1\necho %s >> "$CALLED"\n' "$name" \
    > "$BIN/$name"
  chmod +x "$BIN/$name"
}

_run_pkglist() { PATH="$BIN" run bash "$T/os/tools/install-pkglist.sh" h; }

@test "install-pkglist: uses paru when present" {
  _fake_helper paru
  _run_pkglist
  [ "$status" -eq 0 ]
  # repo + aur pass both routed through paru.
  [ "$(sort -u "$CALLED")" = "paru" ]
}

@test "install-pkglist: uses paru when both present (preferred)" {
  _fake_helper paru
  _fake_helper yay
  _run_pkglist
  [ "$status" -eq 0 ]
  [ "$(sort -u "$CALLED")" = "paru" ]
}

@test "install-pkglist: falls back to yay when only yay present" {
  _fake_helper yay
  _run_pkglist
  [ "$status" -eq 0 ]
  [ "$(sort -u "$CALLED")" = "yay" ]
}

@test "install-pkglist: dies clearly when no AUR helper is present" {
  _run_pkglist
  [ "$status" -ne 0 ]
  [[ "$output" == *"no AUR helper"* ]]
}
