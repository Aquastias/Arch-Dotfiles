#!/usr/bin/env bats
# Tests for vm_resolve_iso in vm/lib/core.sh: an empty resolve (a transient
# releases-lookup failure) must abort before any VM is created, naming the
# cause and the ISO_URL_OVERRIDE escape hatch, instead of booting a VM with
# no medium and waiting out the install timeout (90 min lost, 2026-10-16).

bats_require_minimum_version 1.5.0

setup() {
  info() { :; }
  # The real error() exits; inside `$(…)` that ends the resolve's subshell.
  error() { echo "$*" >&2; exit 1; }
  export -f info error
  # shellcheck source=../../vm/lib/core.sh
  source "$BATS_TEST_DIRNAME/../../vm/lib/core.sh"
  ISO_URL_OVERRIDE=""
  ISO_DIRECTORY="$(mktemp -d)"
}

teardown() { rm -rf "$ISO_DIRECTORY"; }

@test "an empty resolve fails and names ISO_URL_OVERRIDE" {
  iso_resolver_get_zfs_compatible() { printf '\n'; }
  run --separate-stderr vm_resolve_iso "$ISO_DIRECTORY"
  [ "$status" -ne 0 ]
  [ -z "$output" ]
  [[ "$stderr" == *"No Arch ISO resolved"* ]]
  [[ "$stderr" == *"ISO_URL_OVERRIDE"* ]]
}

@test "a resolved path that is not a file fails too" {
  iso_resolver_get_zfs_compatible() { echo "$ISO_DIRECTORY/missing.iso"; }
  run --separate-stderr vm_resolve_iso "$ISO_DIRECTORY"
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"No Arch ISO resolved"* ]]
}

@test "a resolved ISO file is printed" {
  touch "$ISO_DIRECTORY/archlinux.iso"
  iso_resolver_get_zfs_compatible() { echo "$ISO_DIRECTORY/archlinux.iso"; }
  run --separate-stderr vm_resolve_iso "$ISO_DIRECTORY"
  [ "$status" -eq 0 ]
  [ "$output" = "$ISO_DIRECTORY/archlinux.iso" ]
}

@test "every flow aborts on a failed resolve, before the seed and the VM" {
  # A failed `iso="$(vm_resolve_iso …)"` must stop the flow on its own line.
  local flow
  for flow in flow-test.sh flow-persistent-run.sh; do
    run grep -c 'iso="$(vm_resolve_iso "$ISO_DIR")" || exit 1' \
      "$BATS_TEST_DIRNAME/../../vm/lib/$flow"
    [ "$output" -ge 1 ]
  done
  run grep -c 'iso="$(vm_resolve_iso "$ISO_DIR")"$' \
    "$BATS_TEST_DIRNAME/../../vm/lib/flow-test.sh" \
    "$BATS_TEST_DIRNAME/../../vm/lib/flow-persistent-run.sh"
  [[ "$output" != *":"[1-9]* ]]
}
