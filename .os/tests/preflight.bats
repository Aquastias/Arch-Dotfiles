#!/usr/bin/env bats
# Tests for lib/preflight.sh — ensure host tools exist before the front-ends.

setup() {
  source "$BATS_TEST_DIRNAME/../lib/preflight.sh"
  BIN="$(mktemp -d)"
  # Isolated PATH: only tools each test stubs count as "installed", so jq/fzf/
  # pacman/… are absent unless a test creates them. Symlink the handful of
  # coreutils the module + assertions still need into the sandbox first.
  ORIG_PATH="$PATH"
  local u
  for u in chmod cat tr rm; do ln -s "$(command -v "$u")" "$BIN/$u"; done
  PATH="$BIN"
  # Record what the pacman seam was asked to install, then materialise those
  # packages' commands so the post-install verify passes (a real pacman would).
  PACMAN_LOG="$BIN/.pacman-args"
  _preflight_pacman() {
    printf '%s\n' "$@" >"$PACMAN_LOG"
    local p
    for p in "$@"; do _install_pkg "$p"; done
  }
}

teardown() {
  PATH="$ORIG_PATH"
  rm -rf "$BIN"
}

# Put a fake executable named $1 on the isolated PATH.
_make_tool() { printf '#!/bin/sh\n' >"$BIN/$1"; chmod +x "$BIN/$1"; }

# Map a package name back to the command(s) it delivers, for the pacman stub.
_install_pkg() {
  case "$1" in
    gptfdisk)             _make_tool sgdisk ;;
    dosfstools)           _make_tool mkfs.fat ;;
    parted)               _make_tool partprobe ;;
    arch-install-scripts) _make_tool pacstrap ;;
    btrfs-progs)          _make_tool mkfs.btrfs ;;
    e2fsprogs)            _make_tool mkfs.ext4 ;;
    lvm2)                 _make_tool pvs ;;
    *)                    _make_tool "$1" ;;   # 1:1 (jq, fzf, git, …)
  esac
}

@test "all tools present: no install, returns 0" {
  _make_tool jq
  _make_tool fzf
  run preflight_ensure_host_tools jq fzf
  [ "$status" -eq 0 ]
  [ ! -f "$PACMAN_LOG" ]
}

@test "missing fzf: installs exactly the missing package" {
  _make_tool jq
  _make_tool pacman
  run preflight_ensure_host_tools jq fzf
  [ "$status" -eq 0 ]
  [ "$(cat "$PACMAN_LOG")" = "fzf" ]
}

@test "cmd:pkg — installs the package name, not the command name" {
  _make_tool pacman
  run preflight_ensure_host_tools sgdisk:gptfdisk mkfs.fat:dosfstools
  [ "$status" -eq 0 ]
  [ "$(tr '\n' ' ' <"$PACMAN_LOG")" = "gptfdisk dosfstools " ]
}

@test "only the missing subset is installed" {
  _make_tool pacman
  _make_tool sgdisk               # gptfdisk already present
  run preflight_ensure_host_tools jq sgdisk:gptfdisk cryptsetup
  [ "$status" -eq 0 ]
  [ "$(tr '\n' ' ' <"$PACMAN_LOG")" = "jq cryptsetup " ]
}

@test "no pacman (not a live medium): hard error names packages, no install" {
  _make_tool jq
  run preflight_ensure_host_tools jq sgdisk:gptfdisk fzf
  [ "$status" -ne 0 ]
  [ ! -f "$PACMAN_LOG" ]
  [[ "$output" == *"not an Arch live medium"* ]]
  [[ "$output" == *"gptfdisk"* ]]
  [[ "$output" == *"fzf"* ]]
}

@test "pacman succeeds but command still absent: hard error" {
  _make_tool pacman
  _preflight_pacman() { printf '%s\n' "$@" >"$PACMAN_LOG"; return 0; }
  run preflight_ensure_host_tools fzf
  [ "$status" -ne 0 ]
  [[ "$output" == *"still missing after install"* ]]
}

@test "pacman itself fails: hard error surfaces guidance" {
  _make_tool pacman
  _preflight_pacman() { return 1; }
  run preflight_ensure_host_tools fzf
  [ "$status" -ne 0 ]
  [[ "$output" == *"pacman failed"* ]]
}

@test "preflight_installer_tools: base list excludes fzf and zfs/age/sops" {
  run preflight_installer_tools
  [ "$status" -eq 0 ]
  [[ "$output" == *"jq"* ]]
  [[ "$output" == *"sgdisk:gptfdisk"* ]]
  [[ "$output" != *"fzf"* ]]
  [[ "$output" != *"zfs"* ]]
  [[ "$output" != *"sops"* ]]
  [[ "$output" != *"age"* ]]
}

@test "preflight_installer_tools --interactive: adds fzf" {
  run preflight_installer_tools --interactive
  [ "$status" -eq 0 ]
  [[ "$output" == *"jq"* ]]
  [[ "$output" == *"fzf"* ]]
}
