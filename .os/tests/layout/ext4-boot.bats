#!/usr/bin/env bats
# Tests for the ext4 Root Adapter's boot emitters (ADR 0043) — the pure string
# functions that produce the `ROOT_CMDLINE` fragment and the initramfs `HOOKS`
# list for a plaintext ext4 root. The FS-agnostic bootloader appends ` rw` +
# the zswap fragment to ROOT_CMDLINE; initcpio.sh writes whatever HOOKS the
# adapter declares. An `encrypted` flag switches both emitters to the LUKS
# variant (ADR 0043, issue 04). Pure: no disk access.

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

# ── ROOT_CMDLINE: encrypted ext4 boots via the LUKS mapper ──────────────────

@test "ext4_root_cmdline: encrypted emits cryptdevice + mapper root" {
  # The uuid is the LUKS container partition UUID; initramfs opens it as
  # 'cryptroot', then the root is /dev/mapper/cryptroot.
  run ext4_root_cmdline "1234-ABCD" encrypted
  [ "$status" -eq 0 ]
  [ "$output" = "cryptdevice=UUID=1234-ABCD:cryptroot root=/dev/mapper/cryptroot" ]
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

# ── HOOKS: an encrypted ext4 root adds `encrypt` before `filesystems` ────────

@test "ext4_hooks: encrypted inserts encrypt between block and filesystems" {
  run ext4_hooks encrypted
  [ "$status" -eq 0 ]
  [[ "$output" =~ "encrypt" ]]
  # encrypt must open the container after block exposes it, before the mount.
  [[ "$output" =~ ^(.*)block(.*)encrypt(.*)filesystems(.*)$ ]]
}
