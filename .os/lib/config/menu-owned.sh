#!/usr/bin/env bash
# =============================================================================
# lib/config/menu-owned.sh — the Menu-Owned Program set (ADR 0086)
# =============================================================================
# A [[Menu-Owned Program]] is a registry Program whose install is governed by a
# dedicated menu control, so the control is its sole home: it is never listed in
# a Guided Installer program picker. This module unions every control-owned set
# into one `menu_owned_programs`, the single filter both program pickers
# subtract (_ctl_host_program_names / _ctl_user_program_names).
#
# Generalises the printing/bluetooth/power owned-sets (ADR 0079/0080) to every
# control: the Bootloader enum owns `grub`, the Security & Backup toggles own the
# post_install set, and secrets activation owns `sops`. Where a control already
# ships an owned-set function it is reused; the two with none — the
# bootloader-owned `grub` and the secrets-owned `sops` — are declared here.
#
# Pure: names on stdout, no state, no TTY.
#
# Public API:
#   menu_owned_programs → every Menu-Owned Program name, sorted-unique, one/line
# =============================================================================

# shellcheck source=./printing.sh
declare -F printing_owned_programs >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/printing.sh"
# shellcheck source=./bluetooth.sh
declare -F bluetooth_owned_programs >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/bluetooth.sh"
# shellcheck source=./power.sh
declare -F power_owned_programs >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/power.sh"
# shellcheck source=./post-install.sh
declare -F post_install_owned_programs >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/post-install.sh"

# bootloader_owned_programs — the one bootloader that is also a registry Program
# (`grub`); the Bootloader enum is its home. State-independent, like
# power_owned_programs — grub is never a free-standing pickable program.
bootloader_owned_programs() { printf '%s\n' grub; }

# secrets_owned_programs — the secrets-activated `sops` Program; the Runner
# selects it when install-state records secrets (ADR 0025), so it is never
# picker-chosen.
secrets_owned_programs() { printf '%s\n' sops; }

# menu_owned_programs — the union across every control, sorted-unique. The single
# set both guided program pickers subtract, so a new control-owned program is
# filtered from one place.
menu_owned_programs() {
  { printing_owned_programs
    bluetooth_owned_programs
    power_owned_programs
    post_install_owned_programs
    bootloader_owned_programs
    secrets_owned_programs
  } | sort -u
}
