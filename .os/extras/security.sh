#!/usr/bin/env bash
# =============================================================================
# extras/security.sh — Firewall (UFW/nftables) + Antivirus (ClamAV)
# =============================================================================
# PURPOSE:
#   Hardens the installed system with two security layers:
#
#   1. UFW FIREWALL (backed by nftables)
#      UFW (Uncomplicated Firewall) provides a simple interface over nftables.
#      Default policy: deny all incoming, allow all outgoing.
#      Rules added: allow SSH (rate-limited), DHCP client, mDNS/Avahi.
#      KDE-specific rules are added if SDDM/KDE is detected.
#
#   2. CLAMAV ANTIVIRUS
#      Open-source antivirus for on-demand and scheduled scans.
#      clamd    — background scanning daemon
#      freshclam — virus definition updater (runs daily via systemd timer)
#      On-access scanning is configured but left disabled by default
#      (it has a significant I/O overhead; enable manually if needed).
#
# WHEN IT RUNS:
#   Called inside arch-chroot during 03-install.sh when post_install.security=true.
#   Can also run standalone on an installed system.
# =============================================================================

set -Eeuo pipefail

# ── Source common.sh for shared helpers ──────────────────────────────────────
COMMON="/root/lib/common.sh"
if [[ -f "$COMMON" ]]; then
  # shellcheck source=/dev/null
  source "$COMMON"
else
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  CYAN='\033[0;36m'
  BOLD='\033[1m'
  NC='\033[0m'
  info() { echo -e "${GREEN}[SEC]${NC}   $*"; }
  warn() { echo -e "${YELLOW}[SEC]${NC}   $*"; }
  section() { echo -e "\n${CYAN}${BOLD}━━━  $*  ━━━${NC}"; }
fi
# Script-specific prefix overrides
info() { echo -e "${GREEN}[SEC]${NC}   $*"; }
warn() { echo -e "${YELLOW}[SEC]${NC}   $*"; }
section() { echo -e "\n${CYAN}${BOLD}━━━  $*  ━━━${NC}"; }

# =============================================================================
# UFW FIREWALL
# =============================================================================

section "Installing UFW Firewall (nftables backend)"

pacman -S --noconfirm --needed ufw

# ── Default policies ──────────────────────────────────────────────────────────
ufw --force reset          # Clear any previous rules
ufw default deny incoming  # Block all unsolicited inbound traffic
ufw default allow outgoing # Allow all outbound traffic
ufw default deny forward   # No forwarding (desktop, not a router)

# ── Essential rules ───────────────────────────────────────────────────────────
# SSH — rate-limited (max 6 connections per 30 seconds) to resist brute-force
ufw limit ssh comment "SSH (rate-limited)"

# mDNS — needed for .local hostname resolution (Avahi/zeroconf)
ufw allow in to any port 5353 proto udp comment "mDNS/Avahi"

# DHCP client — allow incoming DHCP offers on UDP 68
ufw allow in to any port 68 proto udp comment "DHCP client"

# ── KDE Connect (if KDE is installed) ────────────────────────────────────────
if pacman -Qi sddm &>/dev/null 2>&1 || pacman -Qi plasma-desktop &>/dev/null 2>&1; then
  # KDE Connect uses ports 1714–1764 for device pairing and sync
  ufw allow 1714:1764/tcp comment "KDE Connect"
  ufw allow 1714:1764/udp comment "KDE Connect"
  info "KDE Connect rules added."
fi

# ── Enable UFW ────────────────────────────────────────────────────────────────
ufw --force enable
systemctl enable ufw

info "UFW enabled. Current rules:"
ufw status verbose

# =============================================================================
# CLAMAV ANTIVIRUS
# =============================================================================

section "Installing ClamAV Antivirus"

pacman -S --noconfirm --needed \
  clamav \
  clamtk # GTK GUI for ClamAV (optional, works fine without KDE)

# ── freshclam — virus definition updater ─────────────────────────────────────
# freshclam.service is enabled at the end of this script after all config is done.
# clamav-freshclam-once runs a single update on first boot if definitions are missing.
systemctl enable clamav-freshclam-once.service 2>/dev/null || true

# Attempt an immediate update now (inside chroot, requires internet).
# This downloads ~200 MB of signatures and can take 5–30 minutes.
# If it fails (no internet in chroot, timeout, etc.) that is OK —
# freshclam will retry automatically on first boot.
info "Attempting initial ClamAV definition update (may take several minutes)..."
info "This downloads ~200 MB — safe to Ctrl+C if you want to defer to first boot."
freshclam 2>/dev/null && info "Definitions updated." || warn "freshclam deferred — will run automatically on first boot."

# ── clamd — background scanning daemon ───────────────────────────────────────
# Edit /etc/clamav/clamd.conf to tune; notable options:
#   MaxFileSize        — max file size to scan (default 25M, increase for large archives)
#   OnAccessPrevention — set to yes to block detected files (off by default)
#   ExcludePath        — directories to skip (e.g. /proc, /sys, /dev, /run)

# Patch clamd.conf: remove the default "Example" line that prevents daemon start
sed -i 's/^Example/#Example/' /etc/clamav/clamd.conf
sed -i 's/^Example/#Example/' /etc/clamav/freshclam.conf

# Add sensible exclusions to avoid scanning virtual filesystems
cat >>/etc/clamav/clamd.conf <<'CLAMCONF'

# Exclude virtual/kernel filesystems — scanning these causes errors and hangs
ExcludePath ^/proc
ExcludePath ^/sys
ExcludePath ^/dev
ExcludePath ^/run

# On-access scanning (real-time, watches filesystem events via inotify).
# DISABLED by default — significant I/O overhead. Enable with:
#   systemctl enable clamav-daemon && systemctl start clamav-daemon
# ScanOnAccess no
CLAMCONF

# clamav-daemon (clamd) is a persistent background daemon that uses ~700 MB RAM.
# It is NOT enabled by default. The weekly scan timer uses the standalone
# clamscan binary which does not require clamd to be running.
# To enable always-on scanning: systemctl enable --now clamav-daemon
# systemctl enable clamav-daemon.service  ← uncomment if you want always-on

# ── Scheduled weekly full scan via systemd timer ─────────────────────────────
# Uses standalone clamscan (no daemon needed). Requires freshclam to have
# run at least once so virus definitions exist.
cat >/etc/systemd/system/clamav-scan.service <<'CLAMSVC'
[Unit]
Description=ClamAV weekly full system scan
# Wants freshclam to have updated definitions before scanning.
# Using Wants (not Requires) so scan still runs even if freshclam is already done.
Wants=clamav-freshclam.service
After=clamav-freshclam.service network-online.target
Requires=network-online.target

[Service]
Type=oneshot
# Scans /home and /tmp; adjust paths as needed.
# --infected  — only report infected files (quiet output)
# --move=/var/quarantine to quarantine instead of leaving in place
ExecStart=/usr/bin/clamscan --recursive --infected --suppress-ok-results /home /tmp \
    --exclude-dir=^/proc --exclude-dir=^/sys --exclude-dir=^/dev \
    --log=/var/log/clamav/weekly-scan.log
CLAMSVC

cat >/etc/systemd/system/clamav-scan.timer <<'CLAMTIMER'
[Unit]
Description=Run ClamAV weekly scan every Sunday at 02:30

[Timer]
OnCalendar=Sun *-*-* 02:30:00
RandomizedDelaySec=10min
# Persistent: if the system was off at scan time, run on next boot
Persistent=true

[Install]
WantedBy=timers.target
CLAMTIMER

mkdir -p /var/log/clamav
# Ensure clamav user owns the log directory (clamav-daemon runs as clamav user)
chown clamav:clamav /var/log/clamav 2>/dev/null || true
systemctl enable clamav-scan.timer
systemctl enable clamav-freshclam.service

paccache -rk0 --noconfirm 2>/dev/null || true

info "ClamAV installed and configured."
info "Weekly scan scheduled: Sundays at 02:30, results in /var/log/clamav/weekly-scan.log"
info "To run a manual scan: clamscan --recursive --infected /home"
info "To enable real-time on-access scanning: systemctl enable --now clamav-daemon"
