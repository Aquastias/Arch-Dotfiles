#!/usr/bin/env bats
# Tests for .os/lib/boot/loader-entries.sh — pure per-loader boot-entry
# renderers (ADR 0078). Each takes the resolved per-kernel inputs (kbase, title,
# microcode initrd lines, the initramfs image, the options/cmdline) and prints
# the loader's entry text. No disk, no state — the adapters loop KERNELS and
# feed each kernel through these, so multi-kernel entry text is unit-tested here
# while the chroot copy/register glue stays in the adapter.

setup() {
  source "$BATS_TEST_DIRNAME/../../lib/boot/loader-entries.sh"
}

# ── systemd-boot ─────────────────────────────────────────────────────────────

@test "sdboot_entry: renders title/linux/initrd/options in order" {
  run sdboot_entry "Arch Linux (linux-lts)" linux-lts \
    "initrd  /amd-ucode.img" initramfs-linux-lts.img "root=ZFS=rpool/ROOT rw"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '%s\n' \
    'title   Arch Linux (linux-lts)' \
    'linux   /vmlinuz-linux-lts' \
    'initrd  /amd-ucode.img' \
    'initrd  /initramfs-linux-lts.img' \
    'options root=ZFS=rpool/ROOT rw')" ]
}

@test "sdboot_entry: per-kbase image path (multi-kernel names never collide)" {
  run sdboot_entry "Arch Linux (linux-zen)" linux-zen \
    "" initramfs-linux-zen.img "root=ZFS=rpool/ROOT rw"
  [ "$status" -eq 0 ]
  [[ "$output" == *'linux   /vmlinuz-linux-zen'* ]]
  [[ "$output" == *'initrd  /initramfs-linux-zen.img'* ]]
}

@test "sdboot_entry: empty microcode omits the microcode initrd line" {
  run sdboot_entry "t" linux "" initramfs-linux.img "root=x rw"
  [ "$status" -eq 0 ]
  # exactly one initrd line (the initramfs), no blank microcode line
  [ "$(grep -c '^initrd' <<<"$output")" -eq 1 ]
  [[ "$output" != *$'\n\n'* ]]
}

# ── limine ───────────────────────────────────────────────────────────────────

@test "limine_entry: label, protocol, kernel, microcode+initramfs, cmdline" {
  run limine_entry "Arch Linux (linux-lts)" linux-lts \
    "initrd  /amd-ucode.img" initramfs-linux-lts.img "root=ZFS=rpool rw"
  [ "$status" -eq 0 ]
  [[ "$output" == *'/Arch Linux (linux-lts)'* ]]
  [[ "$output" == *'protocol: linux'* ]]
  [[ "$output" == *'kernel_path: boot():/vmlinuz-linux-lts'* ]]
  # microcode module loads BEFORE the main initramfs
  [[ "$output" == *'module_path: boot():/amd-ucode.img'*'module_path: boot():/initramfs-linux-lts.img'* ]]
  [[ "$output" == *'cmdline: root=ZFS=rpool rw'* ]]
}

@test "limine_entry: empty microcode omits the module line" {
  run limine_entry "t" linux "" initramfs-linux.img "root=x rw"
  [ "$status" -eq 0 ]
  [ "$(grep -c 'module_path' <<<"$output")" -eq 1 ]
}

# ── refind ───────────────────────────────────────────────────────────────────

@test "refind_linux_conf: one quoted sub-entry carrying the cmdline" {
  run refind_linux_conf "root=ZFS=rpool/ROOT rw"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"Boot with standard options"'* ]]
  [[ "$output" == *'"root=ZFS=rpool/ROOT rw"'* ]]
}

# ── efistub ──────────────────────────────────────────────────────────────────

@test "efistub_load_options: microcode initrd(s) then initramfs then cmdline" {
  run efistub_load_options initramfs-linux-lts.img "amd-ucode.img" \
    "root=ZFS=rpool rw"
  [ "$status" -eq 0 ]
  [ "$output" = 'initrd=\amd-ucode.img initrd=\initramfs-linux-lts.img root=ZFS=rpool rw' ]
}

@test "efistub_load_options: no microcode → just initramfs + cmdline" {
  run efistub_load_options initramfs-linux.img "" "root=x rw"
  [ "$status" -eq 0 ]
  [ "$output" = 'initrd=\initramfs-linux.img root=x rw' ]
}
