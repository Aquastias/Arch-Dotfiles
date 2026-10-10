#!/usr/bin/env bats
# Tests for .installer/lib/boot/loader-entries.sh — pure per-loader boot-entry
# renderers (ADR 0078). Each takes the resolved per-kernel inputs (kbase, title,
# microcode initrd lines, the initramfs image, the options/cmdline) and prints
# the loader's entry text. No disk, no state — the adapters loop KERNELS and
# feed each kernel through these, so multi-kernel entry text is unit-tested here
# while the chroot copy/register glue stays in the adapter.

setup() {
  source "$BATS_TEST_DIRNAME/../../lib/boot/loader-entries.sh"
}

# ── systemd-boot ─────────────────────────────────────────────────────────────

@test "loader_entries_systemd_boot: renders title/linux/initrd/options in order" {
  run loader_entries_systemd_boot "Arch Linux (linux-lts)" linux-lts \
    "initrd  /amd-ucode.img" initramfs-linux-lts.img "root=ZFS=rpool/ROOT rw"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '%s\n' \
    'title   Arch Linux (linux-lts)' \
    'linux   /vmlinuz-linux-lts' \
    'initrd  /amd-ucode.img' \
    'initrd  /initramfs-linux-lts.img' \
    'options root=ZFS=rpool/ROOT rw')" ]
}

@test "loader_entries_systemd_boot: per-kbase image path (multi-kernel names never collide)" {
  run loader_entries_systemd_boot "Arch Linux (linux-zen)" linux-zen \
    "" initramfs-linux-zen.img "root=ZFS=rpool/ROOT rw"
  [ "$status" -eq 0 ]
  [[ "$output" == *'linux   /vmlinuz-linux-zen'* ]]
  [[ "$output" == *'initrd  /initramfs-linux-zen.img'* ]]
}

@test "loader_entries_systemd_boot: empty microcode omits the microcode initrd line" {
  run loader_entries_systemd_boot "t" linux "" initramfs-linux.img "root=x rw"
  [ "$status" -eq 0 ]
  # exactly one initrd line (the initramfs), no blank microcode line
  [ "$(grep -c '^initrd' <<<"$output")" -eq 1 ]
  [[ "$output" != *$'\n\n'* ]]
}

# ── limine ───────────────────────────────────────────────────────────────────

@test "loader_entries_limine: label, protocol, kernel, microcode+initramfs, cmdline" {
  run loader_entries_limine "Arch Linux (linux-lts)" linux-lts \
    "initrd  /amd-ucode.img" initramfs-linux-lts.img "root=ZFS=rpool rw"
  [ "$status" -eq 0 ]
  [[ "$output" == *'/Arch Linux (linux-lts)'* ]]
  [[ "$output" == *'protocol: linux'* ]]
  [[ "$output" == *'kernel_path: boot():/vmlinuz-linux-lts'* ]]
  # microcode module loads BEFORE the main initramfs
  local ucode='module_path: boot():/amd-ucode.img'
  local initrd='module_path: boot():/initramfs-linux-lts.img'
  [[ "$output" == *"$ucode"*"$initrd"* ]]
  [[ "$output" == *'cmdline: root=ZFS=rpool rw'* ]]
}

@test "loader_entries_limine: empty microcode omits the module line" {
  run loader_entries_limine "t" linux "" initramfs-linux.img "root=x rw"
  [ "$status" -eq 0 ]
  [ "$(grep -c 'module_path' <<<"$output")" -eq 1 ]
}

# ── grub ─────────────────────────────────────────────────────────────────────

@test "loader_entries_grub: menuentry with ESP-root kernel, microcode first, cmdline" {
  run loader_entries_grub "Arch Linux (linux-lts)" linux-lts "amd-ucode.img" \
    initramfs-linux-lts.img "root=ZFS=rpool rw"
  [ "$status" -eq 0 ]
  [[ "$output" == *"menuentry 'Arch Linux (linux-lts)' {"* ]]
  [[ "$output" == *'linux /vmlinuz-linux-lts root=ZFS=rpool rw'* ]]
  [[ "$output" == *'initrd /amd-ucode.img /initramfs-linux-lts.img'* ]]
}

@test "loader_entries_grub: empty microcode loads just the initramfs" {
  run loader_entries_grub "t" linux "" initramfs-linux.img "root=x rw"
  [[ "$output" == *$'\n    initrd /initramfs-linux.img\n'* ]]
}


# ── refind ───────────────────────────────────────────────────────────────────

@test "loader_entries_refind_linux_config: one quoted sub-entry carrying the cmdline" {
  run loader_entries_refind_linux_config "root=ZFS=rpool/ROOT rw"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"Boot with standard options"'* ]]
  [[ "$output" == *'"root=ZFS=rpool/ROOT rw"'* ]]
}

# ── efistub ──────────────────────────────────────────────────────────────────

@test "loader_entries_efistub_options: microcode initrd(s) then initramfs then cmdline" {
  run loader_entries_efistub_options initramfs-linux-lts.img "amd-ucode.img" \
    "root=ZFS=rpool rw"
  [ "$status" -eq 0 ]
  local want='initrd=\amd-ucode.img initrd=\initramfs-linux-lts.img'
  want+=' root=ZFS=rpool rw'
  [ "$output" = "$want" ]
}

@test "loader_entries_efistub_options: no microcode → just initramfs + cmdline" {
  run loader_entries_efistub_options initramfs-linux.img "" "root=x rw"
  [ "$status" -eq 0 ]
  [ "$output" = 'initrd=\initramfs-linux.img root=x rw' ]
}

@test "loader_entries_efistub_options: multiple microcode images each get an initrd=" {
  run loader_entries_efistub_options initramfs-linux.img "intel-ucode.img amd-ucode.img" \
    "root=x rw"
  [ "$status" -eq 0 ]
  local want='initrd=\intel-ucode.img initrd=\amd-ucode.img'
  want+=' initrd=\initramfs-linux.img root=x rw'
  [ "$output" = "$want" ]
}
