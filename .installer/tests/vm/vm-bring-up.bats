#!/usr/bin/env bats
# Tests for _core_vm_bring_up in vm/lib/core.sh — both flows' VM lifecycle.
# Each flow runs the installer from the live ISO right after, so a domain
# left with no install medium (verify-boot ejects it) or a stale one must be
# recreated, never booted: it would boot its old installed disk and the
# installer would never start (guided-user rerun, 2026-11-13).

setup() {
  info() { :; }
  section() { :; }
  export -f info section
  # shellcheck source=../../vm/lib/core.sh
  source "$BATS_TEST_DIRNAME/../../vm/lib/core.sh"
  CALLS="$(mktemp)"
  RECREATE=false
  EXISTS=1
  CURRENT_ISO=""
  _core_vm_exists() { ((EXISTS)); }
  _core_vm_install_iso_path() { printf '%s\n' "$CURRENT_ISO"; }
  _core_vm_destroy_undefine() { echo destroy >> "$CALLS"; EXISTS=0; }
  _core_vm_create() { echo "create $1 $2" >> "$CALLS"; EXISTS=1; }
  _core_vm_boot() { echo boot >> "$CALLS"; }
  _core_refresh_pool_for_path() { :; }
}

teardown() { rm -f "$CALLS"; }

@test "a VM with no install medium (ejected) is recreated" {
  CURRENT_ISO=""
  _core_vm_bring_up /iso/new.iso /seed.iso
  [ "$(cat "$CALLS")" = $'destroy\ncreate /iso/new.iso /seed.iso\nboot' ]
}

@test "a VM pointing at another ISO is recreated" {
  CURRENT_ISO=/iso/old.iso
  _core_vm_bring_up /iso/new.iso /seed.iso
  [ "$(cat "$CALLS")" = $'destroy\ncreate /iso/new.iso /seed.iso\nboot' ]
}

@test "a VM already holding this ISO is reused" {
  CURRENT_ISO=/iso/new.iso
  _core_vm_bring_up /iso/new.iso /seed.iso
  [ "$(cat "$CALLS")" = boot ]
}

@test "no VM yet: created, then booted" {
  EXISTS=0
  _core_vm_bring_up /iso/new.iso /seed.iso
  [ "$(cat "$CALLS")" = $'create /iso/new.iso /seed.iso\nboot' ]
}

@test "--recreate always destroys first" {
  RECREATE=true
  CURRENT_ISO=/iso/new.iso
  _core_vm_bring_up /iso/new.iso /seed.iso
  [ "$(cat "$CALLS")" = $'destroy\ncreate /iso/new.iso /seed.iso\nboot' ]
}

@test "persistent flow: an installed VM (no install medium) is kept, not destroyed" {
  # A persistent VM holds the operator's state: rebuilding it takes --recreate.
  error() { echo "$*" >&2; return 1; }
  CURRENT_ISO=""
  run _core_vm_bring_up /iso/new.iso /seed.iso keep-installed
  [ "$status" -ne 0 ]
  [[ "$output" == *"--recreate"* ]]
  [ ! -s "$CALLS" ]
}

@test "persistent flow: a stale ISO is still recreated" {
  CURRENT_ISO=/iso/old.iso
  _core_vm_bring_up /iso/new.iso /seed.iso keep-installed
  [ "$(cat "$CALLS")" = $'destroy\ncreate /iso/new.iso /seed.iso\nboot' ]
}
