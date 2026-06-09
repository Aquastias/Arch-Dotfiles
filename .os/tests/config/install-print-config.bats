#!/usr/bin/env bats
# Integration tests for `install.sh --profile <name> --print-config`
# (unified-host-profile/01): validate + assemble + emit the effective config
# to stdout, with NO libvirt and NO disk-touching phase (01/02/03 never run).

setup() {
  INSTALL_SH="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)/install.sh"
  OSDIR="$(mktemp -d)"
  mkdir -p "$OSDIR/hosts/core" "$OSDIR/hosts/desktop"
}

teardown() { rm -rf "$OSDIR"; }

@test "--profile X --print-config emits the effective config to stdout" {
  printf '%s\n' '{"users":[],"system_programs":[]}' \
    > "$OSDIR/hosts/core/profile.jsonc"
  printf '%s\n' \
    '{"system":{"hostname":"eterniox"},"options":{"bootloader":"grub"}}' \
    > "$OSDIR/hosts/desktop/profile.jsonc"

  run env OS_DIR="$OSDIR" bash "$INSTALL_SH" --profile desktop --print-config
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.system.hostname == "eterniox"'
  echo "$output" | jq -e '.options.bootloader == "grub"'
}

@test "--profile X --print-config aborts on a typo'd key before any phase" {
  printf '%s\n' '{"users":[]}' > "$OSDIR/hosts/core/profile.jsonc"
  printf '%s\n' '{"options":{"encrytion":true}}' \
    > "$OSDIR/hosts/desktop/profile.jsonc"

  run env OS_DIR="$OSDIR" bash "$INSTALL_SH" --profile desktop --print-config
  [ "$status" -ne 0 ]
  [[ "$output" == *"options.encrytion"* ]]
}

@test "--print-config without --profile is rejected" {
  run env OS_DIR="$OSDIR" bash "$INSTALL_SH" --print-config
  [ "$status" -ne 0 ]
  [[ "$output" == *"--profile"* ]]
}
