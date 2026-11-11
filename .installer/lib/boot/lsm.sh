#!/usr/bin/env bash
# =============================================================================
# lib/boot/lsm.sh — kernel LSM cmdline fragment (deep, pure)
# =============================================================================
# AppArmor needs the kernel's LSM order set on the cmdline. The installer owns
# it — every Bootloader Adapter appends this fragment — so all five loaders
# get it; the apparmor program only installs + enables the service. Value per
# the Arch Wiki AppArmor page (Installation): `lsm=` alone, apparmor first of
# the major modules. Staged into the chroot lib dir like zswap.sh.
#
# Public API:
#   lsm_cmdline_params <state-json>  → the fragment, or empty when off
# =============================================================================

lsm_cmdline_params() {
  local apparmor
  # Whether the state turns AppArmor on.
  apparmor="$(printf '%s\n' "$1" | jq -r '.apparmor == true')" || return 1
  if [[ "$apparmor" == true ]]; then
    printf '%s\n' "lsm=landlock,lockdown,yama,integrity,apparmor,bpf"
  else
    printf '\n'
  fi
}
