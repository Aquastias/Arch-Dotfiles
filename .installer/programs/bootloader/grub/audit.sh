# shellcheck shell=bash
# Feature Audit probe for the grub program (ADR 0152; contract:
# PROGRAM_SPEC.md). Only the grub variant selects it.
fa_require_pkg grub grub || return 0
fa_as_root || return 0
fa_check grub-cfg "grub.cfg rendered on the ESP" test -s /boot/efi/grub/grub.cfg
fa_check grub-entries "an entry per staged kernel" \
  sh -c 'for k in /boot/efi/vmlinuz-*; do
    grep -q "linux /${k##*/} " /boot/efi/grub/grub.cfg || exit 1; done'
fa_check grub-efi "GRUB EFI binary installed" \
  test -s /boot/efi/EFI/BOOT/BOOTX64.EFI
