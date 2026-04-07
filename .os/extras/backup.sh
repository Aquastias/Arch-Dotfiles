#!/usr/bin/env bash
# =============================================================================
# extras/backup.sh — Disk Backup: Timeshift (ZFS snapshots) + Borg/Vorta
# =============================================================================
# PURPOSE:
#   Sets up two complementary backup strategies:
#
#   1. TIMESHIFT via zfs-auto-snapshot
#      Automatic scheduled ZFS snapshots of the OS pool (rpool).
#      Snapshots are instant, space-efficient (copy-on-write), and can be
#      browsed as read-only directories under each dataset's .zfs/snapshot/.
#      Schedules: hourly (24 kept), daily (31 kept), weekly (8 kept),
#                 monthly (12 kept).
#
#   2. BORG BACKUP + VORTA (GUI)
#      Encrypted, compressed, deduplicated backups to any local or remote
#      destination (external drive, NAS, SSH server, Hetzner Storage Box, etc).
#      Borg is the CLI backend; Vorta is a KDE/Qt GUI for managing Borg repos.
#      BorgBase and other providers also offer managed remote repositories.
#
# WHEN IT RUNS:
#   Called inside arch-chroot during 03-install.sh when post_install.backup=true.
#   Can also run standalone on an installed system.
# =============================================================================

set -Eeuo pipefail

# ── Source common.sh for shared helpers ──────────────────────────────────────
# When running inside chroot, common.sh is at /root/lib/common.sh
COMMON="/root/lib/common.sh"
if [[ -f "$COMMON" ]]; then
  # shellcheck source=/dev/null
  source "$COMMON"
else
  # Fallback inline definitions
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  CYAN='\033[0;36m'
  BOLD='\033[1m'
  NC='\033[0m'
  info() { echo -e "${GREEN}[BACKUP]${NC}  $*"; }
  warn() { echo -e "${YELLOW}[BACKUP]${NC}  $*"; }
  section() { echo -e "\n${CYAN}${BOLD}━━━  $*  ━━━${NC}"; }
fi
# Script-specific prefix overrides (applied whether or not common.sh was sourced)
info() { echo -e "${GREEN}[BACKUP]${NC}  $*"; }
section() { echo -e "\n${CYAN}${BOLD}━━━  $*  ━━━${NC}"; }

# =============================================================================
# TIMESHIFT — ZFS AUTO-SNAPSHOT
# =============================================================================

section "Installing zfs-auto-snapshot (Timeshift-style ZFS snapshots)"

# zfs-auto-snapshot is in AUR; install via the pre-built AUR package if available,
# otherwise clone and build. On a fresh install inside chroot we use the AUR method.
# zfs-auto-snapshot is an AUR package — not in official repos or archzfs.
# Try pacman first (in case a custom repo has it), then fall back to AUR build.
if pacman -S --noconfirm --needed zfs-auto-snapshot 2>/dev/null; then
  info "zfs-auto-snapshot installed from repo."
else
  info "Building zfs-auto-snapshot from AUR (git clone + makepkg)..."
  pacman -S --noconfirm --needed git base-devel
  _build="/tmp/zfs-auto-snapshot-build"
  git clone https://aur.archlinux.org/zfs-auto-snapshot.git "$_build"
  pushd "$_build"
  # Must build as non-root; use a temp user if running inside chroot as root
  if [[ $EUID -eq 0 ]]; then
    # makepkg refuses to run as root — create a temporary build user
    useradd -m -r _aurbuild 2>/dev/null || true
    chown -R _aurbuild: "$_build"
    # Grant _aurbuild passwordless sudo for pacman (needed by makepkg -si)
    echo "_aurbuild ALL=(ALL) NOPASSWD: /usr/bin/pacman" >/etc/sudoers.d/aurbuild
    su -l _aurbuild -c "cd $_build && makepkg -si --noconfirm"
    rm -f /etc/sudoers.d/aurbuild
    userdel -r _aurbuild 2>/dev/null || true
  else
    makepkg -si --noconfirm
  fi
  popd
  rm -rf "$_build"
fi

# Enable systemd timer units for each snapshot frequency
# These timers call 'zfs-auto-snapshot' with the appropriate label and keep-count.
for unit in \
  zfs-auto-snapshot-frequent.timer \
  zfs-auto-snapshot-hourly.timer \
  zfs-auto-snapshot-daily.timer \
  zfs-auto-snapshot-weekly.timer \
  zfs-auto-snapshot-monthly.timer; do
  systemctl enable "$unit" 2>/dev/null && info "Enabled: $unit" || true
done

# Tag the datasets you want snapshotted with the ZFS property.
# com.sun:auto-snapshot=true is the property zfs-auto-snapshot checks.
# We apply it to rpool/ROOT and rpool/home by default.
# This runs at boot via a oneshot service written below.
cat >/etc/systemd/system/zfs-snapshot-tag.service <<'SVC'
[Unit]
Description=Tag ZFS datasets for auto-snapshot
After=zfs-mount.service
Wants=zfs-mount.service

[Service]
Type=oneshot
RemainAfterExit=yes
# Tag root and home datasets — edit to match your pool name if not 'rpool'
ExecStart=/bin/bash -c '\
    zfs set com.sun:auto-snapshot=true rpool/ROOT/arch 2>/dev/null || true; \
    zfs set com.sun:auto-snapshot=true rpool/home 2>/dev/null || true'

[Install]
WantedBy=multi-user.target
SVC
systemctl enable zfs-snapshot-tag.service
info "ZFS auto-snapshot configured."

# =============================================================================
# BORG BACKUP + VORTA GUI
# =============================================================================

section "Installing Borg Backup + Vorta"

# borgbackup — the core backup engine
# vorta      — Qt/KDE GUI for managing Borg repositories and schedules
# python-borgmatic — optional CLI wrapper for automated Borg jobs (cron/systemd)
pacman -S --noconfirm --needed \
  borgbackup \
  vorta \
  python-borgmatic

# Write a starter borgmatic config for the first user
# (Actual setup — init repo, set passphrase, configure sources — must be done
# by the user after install. This config is just a documented starting point.)
FIRST_USER
FIRST_USER="$(awk -F: '$3>=1000 && $3<65534{print $1; exit}' /etc/passwd || echo '')"
if [[ -n "$FIRST_USER" ]]; then
  cfg_dir="/home/${FIRST_USER}/.config/borgmatic"
  mkdir -p "$cfg_dir"
  cat >"${cfg_dir}/config.yaml" <<'BORGCFG'
# Borgmatic configuration — edit before first use.
# Documentation: https://torsion.org/borgmatic/

location:
    # Directories to back up
    source_directories:
        - /home
        - /etc
        - /var/log

    # Borg repository location. Examples:
    #   Local:          /mnt/backup/borg
    #   SSH/remote:     user@server.example.com:/backup/borg
    #   Hetzner:        user@storagebox.de:/./borg
    repositories:
        - path: /mnt/backup/borg
          label: local

storage:
    # Encryption mode. 'repokey-blake2' stores the key in the repo (with passphrase).
    # Run 'borg init --encryption=repokey-blake2 <repo>' to initialise.
    encryption_passcommand: cat /etc/borg-passphrase
    compression: lz4

retention:
    keep_hourly: 24
    keep_daily: 7
    keep_weekly: 4
    keep_monthly: 6

consistency:
    checks:
        - name: repository
        - name: archives
          frequency: 2 weeks
BORGCFG
  chown -R "${FIRST_USER}:" "$cfg_dir"
  info "Borgmatic starter config written to ${cfg_dir}/config.yaml"
fi

# Enable borgmatic daily timer (runs at 01:00 by default)
systemctl enable borgmatic.timer 2>/dev/null || true

info "Borg + Vorta installed."
info "NEXT STEPS:"
info "  1. Initialise a Borg repository: borg init --encryption=repokey-blake2 <repo-path>"
info "  2. Edit ~/.config/borgmatic/config.yaml to set your repo and source dirs."
info "  3. Run your first backup: sudo borgmatic --verbosity 1"
info "  4. Or open Vorta (GUI) to set up repositories interactively."
