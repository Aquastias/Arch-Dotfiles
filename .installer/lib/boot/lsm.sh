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
  jq -r 'if .apparmor == true
    then "lsm=landlock,lockdown,yama,integrity,apparmor,bpf" else "" end' \
    <<<"$1"
}
