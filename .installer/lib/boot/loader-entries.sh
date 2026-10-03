#!/usr/bin/env bash
# =============================================================================
# lib/boot/loader-entries.sh — pure boot-entry renderers (ADR 0078)
# =============================================================================
# One pure function per loader that needs explicit per-kernel entries
# (systemd-boot, limine, efistub, grub). Each takes the resolved inputs for ONE
# kernel — the package base (kbase), a title, the microcode initrd line(s), the
# initramfs image, and the options/cmdline — and prints that loader's entry
# text. The Bootloader Adapter loops the ordered KERNELS array and feeds each
# kernel through here, so multi-kernel entry text is unit-tested in isolation
# while the impure chroot copy/register glue stays in the adapter.
#
# Pure: string-in / string-out, no disk or state access. refind is absent: it
# autodetects the kernels and needs no per-kernel entry rendered here.
# =============================================================================

# sdboot_entry <title> <kbase> <microcode_initrds> <initrd_img> <options>
# A systemd-boot loader entry. <microcode_initrds> is the (possibly empty,
# possibly multi-line) block of `initrd  /<vendor>-ucode.img` lines from
# microcode_present_initrds; it is emitted between the kernel and the initramfs,
# and skipped entirely when empty so an entry never carries a blank line.
sdboot_entry() {
  local title="$1" kbase="$2" microcode="$3" initrd="$4" options="$5"
  printf 'title   %s\n'   "$title"
  printf 'linux   /vmlinuz-%s\n' "$kbase"
  [[ -n "$microcode" ]] && printf '%s\n' "$microcode"
  printf 'initrd  /%s\n'  "$initrd"
  printf 'options %s\n'   "$options"
}

# limine_entry <label> <kbase> <microcode_initrds> <initrd_img> <cmdline>
# A limine.conf entry (modern format). The microcode module(s) load BEFORE the
# main initramfs. <microcode_initrds> is reused verbatim from
# microcode_present_initrds (systemd-boot's "initrd  /<img>" block); each line's
# image is rewritten to a limine module_path, so the adapter computes microcode
# once for every loader.
limine_entry() {
  local label="$1" kbase="$2" microcode="$3" initrd="$4" cmdline="$5" mc
  printf '/%s\n' "$label"
  printf '    protocol: linux\n'
  printf '    kernel_path: boot():/vmlinuz-%s\n' "$kbase"
  while IFS= read -r mc; do
    [[ -n "$mc" ]] || continue
    printf '    module_path: boot():%s\n' "${mc##* }"
  done <<< "$microcode"
  printf '    module_path: boot():/%s\n' "$initrd"
  printf '    cmdline: %s\n' "$cmdline"
}

# grub_entry <label> <kbase> <microcode_imgs> <initrd_img> <cmdline>
# A grub.cfg menuentry. The kernels sit at the ESP root, which is GRUB's root
# (its prefix lives on the ESP), so paths are bare. <microcode_imgs> is the
# space-separated image list (MICROCODE_IMGS), loaded before the initramfs.
grub_entry() {
  local label="$1" kbase="$2" microcode="$3" initrd="$4" cmdline="$5" m
  local imgs=""
  for m in $microcode; do imgs+="/$m "; done
  printf "menuentry '%s' {\n" "$label"
  printf '    linux /vmlinuz-%s %s\n' "$kbase" "$cmdline"
  printf '    initrd %s/%s\n' "$imgs" "$initrd"
  printf '}\n'
}

# refind_linux_conf <cmdline> — the refind_linux.conf placed beside the kernels
# on the ESP. refind auto-detects each vmlinuz-*, its matching initramfs, and
# any *-ucode.img; this file supplies the boot options as one quoted sub-entry.
refind_linux_conf() {
  printf '"Boot with standard options"  "%s"\n' "$1"
}

# efistub_load_options <initrd_img> <microcode_imgs> <cmdline> — the efibootmgr
# load-options (-u) for a direct-UEFI boot: microcode initrd(s) first, then the
# main initramfs, then the kernel cmdline. <microcode_imgs> is a space-separated
# list of image names (may be empty). Paths use the EFI backslash form.
efistub_load_options() {
  local initrd="$1" microcode="$2" cmdline="$3" out="" img
  for img in $microcode; do out+="initrd=\\${img} "; done
  out+="initrd=\\${initrd} ${cmdline}"
  printf '%s\n' "$out"
}
