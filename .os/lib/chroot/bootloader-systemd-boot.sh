#!/usr/bin/env bash
# lib/chroot/bootloader-systemd.sh — Bootloader Adapter: systemd-boot
# Runs inside arch-chroot. Reads install-state.json via install-state.sh.
set -Eeuo pipefail
_LIB_DIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=./chroot-common.sh
source "$_LIB_DIR/chroot-common.sh"
chroot_err_trap "bootloader-systemd"

# shellcheck source=./install-state.sh
STATE="${STATE:-/root/lib-chroot/install-state.json}"
_INSTALL_STATE_SH="$_LIB_DIR/install-state.sh"
[[ -f "$_INSTALL_STATE_SH" ]] || _INSTALL_STATE_SH="$_LIB_DIR/../install-state.sh"
# shellcheck disable=SC1090
source "$_INSTALL_STATE_SH"
install_state_load "$STATE"

# Kernel Selection token table — staged next to install-state.sh.
_KERNEL_SH="$_LIB_DIR/kernel.sh"
[[ -f "$_KERNEL_SH" ]] || _KERNEL_SH="$_LIB_DIR/../packages/kernel.sh"
# shellcheck disable=SC1090
source "$_KERNEL_SH"

# Microcode resolution — staged next to kernel.sh; renders entry initrd lines
# from the *-ucode.img actually present in /boot (ADR 0038).
_MICROCODE_SH="$_LIB_DIR/microcode.sh"
[[ -f "$_MICROCODE_SH" ]] || _MICROCODE_SH="$_LIB_DIR/../packages/microcode.sh"
# shellcheck disable=SC1090
source "$_MICROCODE_SH"

# zswap cmdline fragment (empty unless swap + zswap are both enabled).
_ZSWAP_SH="$_LIB_DIR/zswap.sh"
[[ -f "$_ZSWAP_SH" ]] || _ZSWAP_SH="$_LIB_DIR/../boot/zswap.sh"
# shellcheck disable=SC1090
source "$_ZSWAP_SH"
ZSWAP_CMDLINE="$(zswap_cmdline_params "$(cat "$STATE")")"

# Pure per-kernel entry renderer (staged flat into lib-chroot).
_LE_SH="$_LIB_DIR/loader-entries.sh"
[[ -f "$_LE_SH" ]] || _LE_SH="$_LIB_DIR/../boot/loader-entries.sh"
# shellcheck disable=SC1090
source "$_LE_SH"

# Every selected kernel gets a default + fallback entry (ADR 0078); the Primary
# Kernel (KERNELS[0] == KERNEL) is the loader default. The root= cmdline + HOOKS
# come from install-state's filesystem-blind boot record (ROOT_CMDLINE/HOOKS,
# ADR 0043), so this adapter never names a filesystem.
PRIMARY_KBASE="$(kernel_pkg "$KERNEL")"

# systemd-boot cannot read ZFS — kernel and initramfs must live
# on the FAT32 ESP.
# bootctl warns about "world accessible" and "running in a container" in chroot;
# both are harmless — filter them to keep output clean.
bootctl --esp-path=/boot/efi install 2>&1 \
    | grep -v "world accessible\|security hole" \
    | grep -v "running in a container\|skipping EFI" \
    || true

mkdir -p /boot/efi/loader/entries

# loader.conf. editor=yes keeps the boot-time cmdline editor available (press
# 'e' in the menu) so a broken graphical target is always recoverable — e.g.
# append `systemd.unit=multi-user.target` to reach a text login without external
# media. Trade-off: it is a physical-access root path (init=/bin/bash), but
# systemd-boot force-disables the editor under Secure Boot regardless, so the
# risk is bounded on an SB-enrolled machine.
cat > /boot/efi/loader/loader.conf << EOF
default arch-${PRIMARY_KBASE}.conf
timeout 4
console-mode max
editor yes
EOF

# zfs_import_dir=/dev/disk/by-id makes the initramfs ZFS hook import by scanning
# stable by-id paths instead of /etc/zfs/zpool.cache. A stale/corrupt cache then
# cannot brick boot (the hook ignores it when zfs_import_dir is set).
# Render microcode initrd lines from the *-ucode.img present in /boot, so an
# entry never references a missing initrd (ADR 0038).
MICROCODE_INITRDS="$(microcode_present_initrds /boot)"

# On a desktop install the greeter (tuigreet/sddm) runs on the boot VT, so
# unquenched kernel + systemd status lines scribble over it ("A start job is
# running for …" bleeding across the login screen). Quiet the primary entry; the
# fallback entry below stays verbose so a broken boot is still diagnosable.
QUIET_CMDLINE=""
[[ -n "${ENVIRONMENT_DESKTOP:-}" ]] \
  && QUIET_CMDLINE="quiet loglevel=3 systemd.show_status=false"

DEFAULT_OPTS="${ROOT_CMDLINE} rw${ZSWAP_CMDLINE:+ ${ZSWAP_CMDLINE}}"

# One default + fallback entry per selected kernel, per-kbase filenames so the
# images never collide on the ESP (ADR 0078). ESP Kernel Sync mirrors exactly
# the files these entries reference.
for _tok in "${KERNELS[@]}"; do
  kbase="$(kernel_pkg "$_tok")"
  initramfs="initramfs-${kbase}.img"
  initramfs_fb="initramfs-${kbase}-fallback.img"

  # Default entry — quiet on a desktop so the greeter VT stays clean.
  sdboot_entry "Arch Linux (${kbase})" "$kbase" "$MICROCODE_INITRDS" \
    "$initramfs" "${DEFAULT_OPTS}${QUIET_CMDLINE:+ ${QUIET_CMDLINE}}" \
    > "/boot/efi/loader/entries/arch-${kbase}.conf"

  cp "/boot/vmlinuz-${kbase}" /boot/efi/
  cp "/boot/${initramfs}"     /boot/efi/

  # Fallback entry stays verbose so a broken boot is diagnosable. Generate the
  # fallback initramfs if the preset did not.
  if [[ ! -f "/boot/${initramfs_fb}" ]]; then
    echo "Fallback initramfs for ${kbase} missing — generating ..."
    mkinitcpio -p "$kbase" -S autodetect 2>/dev/null \
      || mkinitcpio -g "/boot/${initramfs_fb}" 2>/dev/null \
      || true
  fi
  if [[ -f "/boot/${initramfs_fb}" ]]; then
    sdboot_entry "Arch Linux (${kbase} — fallback)" "$kbase" \
      "$MICROCODE_INITRDS" "$initramfs_fb" "$DEFAULT_OPTS" \
      > "/boot/efi/loader/entries/arch-${kbase}-fallback.conf"
    cp "/boot/${initramfs_fb}" /boot/efi/
  else
    echo "Note: no fallback for ${kbase} — fallback entry skipped."
  fi
done

# CPU microcode (one vendor, ADR 0038) onto the ESP.
[[ -f /boot/intel-ucode.img ]] && cp /boot/intel-ucode.img /boot/efi/ || true
[[ -f /boot/amd-ucode.img   ]] && cp /boot/amd-ucode.img   /boot/efi/ || true

# Pacman hook: keep ESP copies in sync on every kernel transaction. Exec= in a
# pacman hook goes straight to execv (no shell), so it calls a helper script —
# the shared ESP Kernel Sync (lib/boot/esp-kernel-sync.sh), staged into the
# chroot. It mirrors only what the loader entries reference, so a Stray Kernel
# is never copied (ADR 0038).
mkdir -p /etc/pacman.d/hooks
install -Dm755 "$_LIB_DIR/esp-kernel-sync.sh" \
  /usr/local/lib/archzfs/esp-kernel-sync.sh

# Numbered 94 so the ESP Kernel Sync runs BEFORE the ESP Mirror Hook
# (95-esp-mirror), which then rsyncs the freshly-synced primary ESP onto any
# secondary ESPs (ADR 0038).

# 93 (PreTransaction): preflight that aborts the upgrade BEFORE it applies when
# an ESP lacks room for the new boot images, so the system never half-applies
# into a degraded state. AbortOnFail propagates the non-zero exit to pacman.
cat > /etc/pacman.d/hooks/93-esp-kernel-sync-preflight.hook << 'HOOK'
[Trigger]
Type = Path
Operation = Install
Operation = Upgrade
Target = usr/lib/modules/*/vmlinuz

[Action]
Description = Checking ESP free space for new boot images...
When = PreTransaction
Exec = /usr/local/lib/archzfs/esp-kernel-sync.sh preflight
AbortOnFail
HOOK

cat > /etc/pacman.d/hooks/94-esp-kernel-sync.hook << 'HOOK'
[Trigger]
Type = Path
Operation = Install
Operation = Upgrade
Target = usr/lib/modules/*/vmlinuz

[Action]
Description = Syncing kernel and initramfs to ESP...
When = PostTransaction
Exec = /usr/local/lib/archzfs/esp-kernel-sync.sh
HOOK

echo "systemd-boot installed."
