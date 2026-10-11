# shellcheck shell=bash
# Feature Audit probe for the grub program (ADR 0152; contract:
# PROGRAM_SPEC.md). Only the grub variant selects it.
feature_audit_require_package grub grub || return 0
feature_audit_as_root || return 0
feature_audit_check grub-cfg "grub.cfg rendered on the ESP" test -s /boot/efi/grub/grub.cfg
feature_audit_check grub-entries "an entry per staged kernel" \
  sh -c 'for k in /boot/efi/vmlinuz-*; do
    grep -q "linux /${k##*/} " /boot/efi/grub/grub.cfg || exit 1; done'
feature_audit_check grub-efi "GRUB EFI binary installed" \
  test -s /boot/efi/EFI/BOOT/BOOTX64.EFI
