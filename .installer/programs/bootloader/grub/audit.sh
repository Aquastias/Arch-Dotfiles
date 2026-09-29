# shellcheck shell=bash
# Feature Audit probe for the grub program (ADR 0152; contract:
# PROGRAM_SPEC.md). Only the grub variant selects it.
fa_require_pkg grub grub || return 0
fa_as_root || return 0
fa_check grub-cfg "grub.cfg generated" test -s /boot/grub/grub.cfg
fa_check grub-os-prober "os-prober enabled" \
  grep -q '^GRUB_DISABLE_OS_PROBER=false' /etc/default/grub
fa_check grub-efi "GRUB EFI binary installed" \
  sh -c 'ls /efi/EFI/*/grubx64.efi /boot/EFI/*/grubx64.efi 2>/dev/null \
    | grep -q .'
