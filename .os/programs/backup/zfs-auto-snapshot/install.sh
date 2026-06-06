#!/usr/bin/env bash
# =============================================================================
# programs/backup/zfs-auto-snapshot/install.sh
# =============================================================================
# Invoked by .os/lib/profiles/runner.sh inside arch-chroot, as the owning user, with
# OS_DIR, PROGRAMS, SHELL_COMMONS pre-exported and temp NOPASSWD sudo granted.
#
# Installs zfs-auto-snapshot from AUR via paru, enables snapshot timers for
# all frequencies, and installs a oneshot service that tags rpool datasets on
# first boot (zfs set cannot run inside the chroot).
# =============================================================================

set -Eeuo pipefail
trap 'echo "[zfs-auto-snapshot] error on line $LINENO" >&2' ERR

print_status info "Installing zfs-auto-snapshot..."
paru -S --noconfirm --needed zfs-auto-snapshot

print_status info "Enabling snapshot timers..."
for unit in \
  zfs-auto-snapshot-frequent.timer \
  zfs-auto-snapshot-hourly.timer \
  zfs-auto-snapshot-daily.timer \
  zfs-auto-snapshot-weekly.timer \
  zfs-auto-snapshot-monthly.timer; do
  sudo systemctl enable "$unit"
  print_status info "Enabled: $unit"
done

print_status info "Installing dataset-tagging oneshot service..."
sudo tee /usr/lib/systemd/system/zfs-snapshot-tag.service >/dev/null <<'SVC'
[Unit]
Description=Tag ZFS datasets for auto-snapshot
After=zfs-mount.service
Wants=zfs-mount.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -c '\
    zfs set com.sun:auto-snapshot=true rpool/ROOT/arch 2>/dev/null || true; \
    zfs set com.sun:auto-snapshot=true rpool/home 2>/dev/null || true'

[Install]
WantedBy=multi-user.target
SVC

sudo systemctl enable zfs-snapshot-tag.service

print_status success "zfs-auto-snapshot staged."
