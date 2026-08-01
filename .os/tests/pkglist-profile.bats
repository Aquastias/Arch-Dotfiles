#!/usr/bin/env bats
# tools/save-pkglist.sh + install-pkglist.sh take a PROFILE name, not a
# hostname. ADR 0020 decoupled the two, which left save-pkglist.sh exiting
# "No host dir" on every real machine (hostname `eterniox` vs profile
# `desktop`). The saved files are drift snapshots and say so.

setup() {
  T="$(mktemp -d)"
  mkdir -p "$T/os/tools" "$T/os/lib" \
           "$T/os/hosts/desktop" "$T/os/hosts/laptop" "$T/os/hosts/core" \
           "$T/os/hosts/vm/arch-kde"
  cp "$BATS_TEST_DIRNAME/../tools/save-pkglist.sh" "$T/os/tools/"
  cp "$BATS_TEST_DIRNAME/../tools/install-pkglist.sh" "$T/os/tools/"
  cp "$BATS_TEST_DIRNAME/../lib/aur-helper.sh" "$T/os/lib/"
  for h in desktop laptop core; do
    printf '{}\n' > "$T/os/hosts/$h/profile.jsonc"
  done
  printf '{}\n' > "$T/os/hosts/vm/arch-kde/profile.jsonc"

  # Fake pacman so the save path never touches the real system.
  BIN="$T/bin"; mkdir -p "$BIN"
  printf '#!/bin/sh\ncase "$1" in -Qqen) echo ripgrep; echo fd;; -Qqem) echo brave-bin;; esac\n' \
    > "$BIN/pacman"
  chmod +x "$BIN/pacman"
  export PATH="$BIN:$PATH"
  # A hostname that is deliberately NOT a profile name — the ADR 0020 split.
  printf '#!/bin/sh\necho eterniox\n' > "$BIN/hostname"; chmod +x "$BIN/hostname"
}

teardown() { rm -rf "$T"; }

_save()    { run bash "$T/os/tools/save-pkglist.sh" "$@"; }
_install() { run bash "$T/os/tools/install-pkglist.sh" "$@"; }

# ── save-pkglist takes a profile name ───────────────────────────────────────

@test "save-pkglist: writes into the named profile's directory" {
  _save desktop
  [ "$status" -eq 0 ]
  [ -f "$T/os/hosts/desktop/pkglist-repo.txt" ]
  [ -f "$T/os/hosts/desktop/pkglist-aur.txt" ]
}

@test "save-pkglist: succeeds for both real profiles" {
  _save desktop; [ "$status" -eq 0 ]
  _save laptop;  [ "$status" -eq 0 ]
}

@test "save-pkglist: resolves a VM fixture profile too" {
  _save arch-kde
  [ "$status" -eq 0 ]
  [ -f "$T/os/hosts/vm/arch-kde/pkglist-repo.txt" ]
}

@test "save-pkglist: an unknown profile fails with an actionable message" {
  _save nope
  [ "$status" -ne 0 ]
  [[ "$output" == *"no profile 'nope'"* ]]
  [[ "$output" == *"PROFILE name"* ]]
  [[ "$output" == *"desktop"* ]]     # lists what IS available
}

# The bug this fixes: the tool used to derive its directory from $(hostname),
# so on a machine named `eterniox` running profile `desktop` it always failed.
@test "save-pkglist: a hostname that is not a profile name fails, not silently" {
  _save
  [ "$status" -ne 0 ]
  [[ "$output" == *"no profile 'eterniox'"* ]]
}

# ── the output is stamped a drift snapshot ──────────────────────────────────

@test "save-pkglist: each file carries a drift-snapshot header" {
  _save desktop
  [ "$status" -eq 0 ]
  local repo="$T/os/hosts/desktop/pkglist-repo.txt"
  local aur="$T/os/hosts/desktop/pkglist-aur.txt"
  grep -q "DRIFT SNAPSHOT" "$repo"
  grep -q "DRIFT SNAPSHOT" "$aur"
  grep -q "Do NOT replay into a profile" "$repo"
  grep -q "profile: desktop" "$repo"
  # the packages themselves are still there, uncommented
  grep -qx "ripgrep" "$repo"
  grep -qx "brave-bin" "$aur"
}

# ── install-pkglist reads the same location, header-tolerant ────────────────

@test "install-pkglist: reads what save-pkglist wrote, skipping the header" {
  _save desktop
  [ "$status" -eq 0 ]
  printf '#!/bin/sh\ncat >> "$CALLED"\n' > "$BIN/paru"; chmod +x "$BIN/paru"
  export CALLED="$T/called"; : > "$CALLED"

  _install desktop
  [ "$status" -eq 0 ]
  grep -qx "ripgrep" "$CALLED"
  grep -qx "brave-bin" "$CALLED"
  ! grep -q "DRIFT SNAPSHOT" "$CALLED"
  ! grep -q "^#" "$CALLED"
}

@test "install-pkglist: an unknown profile fails with an actionable message" {
  _install nope
  [ "$status" -ne 0 ]
  [[ "$output" == *"no profile 'nope'"* ]]
}
