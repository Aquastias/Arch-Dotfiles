#!/usr/bin/env bash
# =============================================================================
# programs/backup/zfs-auto-snapshot/install.sh
# =============================================================================
# Invoked by .installer/lib/profiles/runner.sh inside arch-chroot, as the owning user, with
# INSTALLER_DIR, PROGRAMS, SHELL_COMMONS pre-exported and temp NOPASSWD sudo
# granted.
#
# Installs zfs-auto-snapshot from AUR via paru, enables snapshot timers for
# all frequencies, and installs a oneshot service that tags rpool datasets on
# first boot (zfs set cannot run inside the chroot).
# =============================================================================

set -Eeuo pipefail
trap 'echo "[zfs-auto-snapshot] error on line $LINENO" >&2' ERR

print_status info "Installing zfs-auto-snapshot..."
${AUR_HELPER} -S --noconfirm --needed zfs-auto-snapshot

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
# The OS pool is configurable (os_pool_name / os_pool.pool_name), so tag the
# OS datasets on whichever pool holds them; $$ escapes systemd's own $.
ExecStart=/bin/bash -c 'for pool in $$(zpool list -H -o name); do \
    zfs set com.sun:auto-snapshot=true "$$pool/ROOT/arch" 2>/dev/null; \
    zfs set com.sun:auto-snapshot=true "$$pool/home" 2>/dev/null; \
  done; true'

[Install]
WantedBy=multi-user.target
SVC

sudo systemctl enable zfs-snapshot-tag.service

print_status success "zfs-auto-snapshot staged."
