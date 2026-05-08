#!/usr/bin/env bash
# lib/chroot/initcpio.sh — Chroot Configuration Module: initramfs
# Runs inside arch-chroot. Reads install-state.json; no positional args.
set -Eeuo pipefail
trap 'echo "[chroot:initcpio] failed at line $LINENO" >&2' ERR

STATE=/root/lib-chroot/install-state.json
KERNEL="$(jq -r .kernel "$STATE")"

if [[ "$KERNEL" == "lts" ]]; then
    PRESET_NAME="linux-lts"
    INITRAMFS_FB="initramfs-linux-lts-fallback.img"
else
    PRESET_NAME="linux"
    INITRAMFS_FB="initramfs-linux-fallback.img"
fi
PRESET_FILE="/etc/mkinitcpio.d/${PRESET_NAME}.preset"

# ── ZFS hook ──────────────────────────────────────────────────────────────────
# Hook order: block devices visible → zfs imports pool → filesystems mount.
# mkinitcpio >= 0.16 (Arch 2023+) renamed 'modconf' → 'kmod'.
if [[ -e /usr/lib/initcpio/hooks/kmod ]]; then
    MODCONF_HOOK="kmod"
else
    MODCONF_HOOK="modconf"
fi
sed -i "s/^HOOKS=.*/HOOKS=(base udev autodetect ${MODCONF_HOOK} block keyboard zfs filesystems)/" \
    /etc/mkinitcpio.conf

# ── Fallback preset ───────────────────────────────────────────────────────────
# Minimal installs may only define the 'default' preset — ensure 'fallback'
# also exists so there is a recovery boot option with all modules included.
if [[ -f "$PRESET_FILE" ]]; then
    if ! grep -q "^PRESETS=.*fallback" "$PRESET_FILE"; then
        echo "Adding fallback preset to ${PRESET_FILE} ..."
        sed -i "s/^PRESETS=('default')/PRESETS=('default' 'fallback')/" "$PRESET_FILE"
        cat >> "$PRESET_FILE" << EOF

# Fallback preset — builds without autodetect (all modules included)
fallback_config="/etc/mkinitcpio.conf"
fallback_image="/boot/${INITRAMFS_FB}"
fallback_options="-S autodetect"
EOF
    fi
else
    echo "Warning: preset file not found at ${PRESET_FILE} — mkinitcpio -P will use defaults."
fi

mkinitcpio -P
