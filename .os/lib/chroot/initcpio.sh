#!/usr/bin/env bash
# lib/chroot/initcpio.sh — Chroot Configuration Module: initramfs
# Runs inside arch-chroot. Reads install-state.json via install-state.sh.
set -Eeuo pipefail
trap 'echo "[chroot:initcpio] failed at line $LINENO" >&2' ERR

# shellcheck source=./install-state.sh
STATE="${STATE:-/root/lib-chroot/install-state.json}"
_LIB_DIR="$(dirname "${BASH_SOURCE[0]}")"
_INSTALL_STATE_SH="$_LIB_DIR/install-state.sh"
[[ -f "$_INSTALL_STATE_SH" ]] || _INSTALL_STATE_SH="$_LIB_DIR/../install-state.sh"
# shellcheck disable=SC1090
source "$_INSTALL_STATE_SH"
install_state_load "$STATE"

# Kernel Selection token table — maps the Primary Kernel token to its package
# base (= initramfs preset name). Staged next to install-state.sh.
_KERNEL_SH="$_LIB_DIR/kernel.sh"
[[ -f "$_KERNEL_SH" ]] || _KERNEL_SH="$_LIB_DIR/../packages/kernel.sh"
# shellcheck disable=SC1090
source "$_KERNEL_SH"

# Pure helper: emit the HOOKS=(...) line. When impermanence is enabled the
# zfs-rollback hook is inserted between zfs and filesystems so rollback runs
# after the pool import and before any dataset is mounted.
_initcpio_hooks_line() {
  local modconf="$1" imp_enabled="$2"
  local tail="zfs filesystems"
  [[ "$imp_enabled" == "true" ]] && tail="zfs zfs-rollback filesystems"
  printf 'HOOKS=(base udev autodetect %s block keyboard %s)\n' \
    "$modconf" "$tail"
}

# Pure helper: emit the override for the initramfs `udev` runtime hook. It
# shadows /usr/lib/initcpio/hooks/udev so the settle is bounded (a slow device
# can't stall boot past the cap) while keeping the stock trigger pair. The
# bound is a fixed value, not a config field (ADR 0030).
_initcpio_udev_override() {
  cat <<'HOOK'
#!/usr/bin/ash
run_hook() {
    msg ":: Triggering uevents..."
    udevd_running=1
    /usr/lib/systemd/systemd-udevd --daemon --resolve-names=never
    udevadm trigger --action=add --type=subsystems
    udevadm trigger --action=add --type=devices
    udevadm settle --timeout=30
}
HOOK
}

# Thin I/O: install the override at <root>/etc/initcpio/hooks/udev. <root>
# defaults to "" (i.e. /) for the chroot; tests pass a temp root. Must run
# before mkinitcpio builds the image.
_initcpio_write_udev_override() {
  local root="${1:-}"
  local dir="${root}/etc/initcpio/hooks"
  mkdir -p "$dir"
  _initcpio_udev_override > "${dir}/udev"
}

# Lib-only sourcing for tests: skip all side effects below.
[[ "${INITCPIO_LIB_ONLY:-0}" == "1" ]] && return 0

# Preset name = the Primary Kernel's package base (linux-lts/linux/linux-zen/
# linux-hardened). mkinitcpio -P still builds every installed kernel's preset;
# the custom fallback injection below stays Primary-Kernel-only (interim).
PRESET_NAME="$(kernel_pkg "$KERNEL")"
INITRAMFS_FB="initramfs-${PRESET_NAME}-fallback.img"
PRESET_FILE="/etc/mkinitcpio.d/${PRESET_NAME}.preset"

# ── ZFS hook ──────────────────────────────────────────────────────────────────
# Hook order: block devices visible → zfs imports pool → filesystems mount.
# mkinitcpio >= 0.16 (Arch 2023+) renamed 'modconf' → 'kmod'.
if [[ -e /usr/lib/initcpio/hooks/kmod ]]; then
    MODCONF_HOOK="kmod"
else
    MODCONF_HOOK="modconf"
fi
_hooks_line="$(_initcpio_hooks_line "$MODCONF_HOOK" \
  "$IMPERMANENCE_ENABLED")"
sed -i "s|^HOOKS=.*|${_hooks_line}|" /etc/mkinitcpio.conf
unset _hooks_line

# Install the zfs-rollback hook files before mkinitcpio runs, otherwise
# mkinitcpio errors with "Hook 'zfs-rollback' cannot be found". The full
# impermanence_apply runs later in configure.sh — this just stages the
# initcpio hook files it needs at build time.
if [[ "$IMPERMANENCE_ENABLED" == "true" ]]; then
    # shellcheck source=./impermanence.sh
    source "$_LIB_DIR/impermanence.sh"
    _impermanence_write_rollback_hook
fi

# ── Fallback preset ───────────────────────────────────────────────────────────
# Minimal installs may only define the 'default' preset — ensure 'fallback'
# also exists so there is a recovery boot option with all modules included.
if [[ -f "$PRESET_FILE" ]]; then
    if ! grep -q "^PRESETS=.*fallback" "$PRESET_FILE"; then
        echo "Adding fallback preset to ${PRESET_FILE} ..."
        sed -i "s/^PRESETS=('default')/PRESETS=('default' 'fallback')/" \
          "$PRESET_FILE"
        cat >> "$PRESET_FILE" << EOF

# Fallback preset — builds without autodetect (all modules included)
fallback_config="/etc/mkinitcpio.conf"
fallback_image="/boot/${INITRAMFS_FB}"
fallback_options="-S autodetect"
EOF
    fi
else
    echo "Warning: preset file not found at ${PRESET_FILE} —" \
         "mkinitcpio -P will use defaults."
fi

# Bound the initramfs udev settle so a slow device can't stall boot past the
# cap. Written before the image is built so mkinitcpio bakes in the override
# (ADR 0030).
_initcpio_write_udev_override ""

mkinitcpio -P
