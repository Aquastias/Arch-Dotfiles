#!/usr/bin/env bats
# Tests for the ext4 Root Adapter's boot emitters (ADR 0043) — the pure string
# functions that produce the `ROOT_CMDLINE` fragment and the initramfs `HOOKS`
# list for a plaintext ext4 root. The FS-agnostic bootloader appends ` rw` +
# the zswap fragment to ROOT_CMDLINE; initcpio.sh writes whatever HOOKS the
# adapter declares. LUKS variants land in a later slice. Pure: no disk access.

setup() {
  # shellcheck source=../../lib/layout/ext4/boot.sh
  source "$BATS_TEST_DIRNAME/../../lib/layout/ext4/boot.sh"
}

# ── ROOT_CMDLINE: plaintext ext4 boots by root UUID ─────────────────────────

@test "ext4_root_cmdline: emits root=UUID for the given root uuid" {
  run ext4_root_cmdline "1234-ABCD"
  [ "$status" -eq 0 ]
  [ "$output" = "root=UUID=1234-ABCD" ]
}

# ── HOOKS: a plaintext ext4 root needs no zfs / no encrypt hook ──────────────

@test "ext4_hooks: includes block + filesystems, excludes zfs and encrypt" {
  run ext4_hooks
  [ "$status" -eq 0 ]
  [[ "$output" =~ "block" ]]
  [[ "$output" =~ "filesystems" ]]
  [[ ! "$output" =~ "zfs" ]]
  [[ ! "$output" =~ "encrypt" ]]
}

@test "ext4_hooks: block precedes filesystems (device nodes before mount)" {
  run ext4_hooks
  local hooks="$output"
  # crude ordering check: index of 'block' < index of 'filesystems'
  [[ "$hooks" =~ ^(.*)block(.*)filesystems(.*)$ ]]
}
