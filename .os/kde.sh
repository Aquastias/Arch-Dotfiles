#!/usr/bin/env bash
# =============================================================================
# extras/kde.sh — KDE Plasma Desktop
# =============================================================================
# PURPOSE:
#   Installs a full KDE Plasma 6 desktop environment with SDDM display manager,
#   common KDE applications, and proper audio/Bluetooth/printing support.
#
# WHEN IT RUNS:
#   Called from inside the arch-chroot during 03-install.sh when
#   post_install.kde = true in install.json.
#
# CAN ALSO RUN STANDALONE after installation:
#   arch-chroot /mnt /root/extras/kde.sh
#   — or on the installed system —
#   sudo /root/extras/kde.sh
# =============================================================================

set -Eeuo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()    { echo -e "${GREEN}[KDE]${NC}  $*"; }
section() { echo -e "\n${CYAN}${BOLD}━━━  $*  ━━━${NC}"; }

section "Installing KDE Plasma Desktop"

# ── Core Plasma & SDDM ────────────────────────────────────────────────────────
# plasma-meta pulls in the full Plasma 6 desktop
# sddm is the recommended display manager for KDE
# plasma-meta — full KDE Plasma 6 desktop (recommended)
# kde-applications-meta — all KDE apps (~3 GB extra, optional, commented out below)
pacman -S --noconfirm --needed \
    plasma-meta \
    sddm \
    sddm-kcm \
    xdg-user-dirs \
    xdg-utils \
    dolphin \
    konsole \
    kate \
    ark \
    gwenview \
    spectacle \
    okular
# Uncomment to install ALL KDE applications (~3 GB additional download):
# pacman -S --noconfirm --needed kde-applications-meta

# ── Wayland support ───────────────────────────────────────────────────────────
# In KDE Plasma 6, Wayland is the default session — no separate package needed.
# plasma-meta already includes everything required for Wayland.
# qt6-wayland and xorg-xwayland provide compatibility for X11 apps under Wayland.
pacman -S --noconfirm --needed \
    qt6-wayland \
    xorg-xwayland

# ── Audio (PipeWire replaces PulseAudio, works natively with KDE) ─────────────
pacman -S --noconfirm --needed \
    pipewire \
    pipewire-alsa \
    pipewire-pulse \
    pipewire-jack \
    wireplumber \
    pavucontrol

# ── Bluetooth ─────────────────────────────────────────────────────────────────
pacman -S --noconfirm --needed \
    bluez \
    bluez-utils \
    bluedevil

# ── Printing ──────────────────────────────────────────────────────────────────
pacman -S --noconfirm --needed \
    cups \
    print-manager

# ── Fonts ─────────────────────────────────────────────────────────────────────
pacman -S --noconfirm --needed \
    noto-fonts \
    noto-fonts-cjk \
    noto-fonts-emoji \
    ttf-liberation \
    ttf-dejavu

# ── System services ───────────────────────────────────────────────────────────
systemctl enable sddm           # Display manager — graphical login screen
systemctl enable bluetooth      # Bluetooth daemon
systemctl enable cups           # Printing (CUPS) daemon

# ── PipeWire audio — user services ────────────────────────────────────────────
# PipeWire, WirePlumber and pipewire-pulse run as user services, not system ones.
# `systemctl --global enable` writes to /etc/systemd/user/ so they activate
# for every user's session automatically (no per-user `systemctl --user enable`).
systemctl --global enable pipewire.socket
systemctl --global enable pipewire-pulse.socket
systemctl --global enable wireplumber.service

# ── Avahi mDNS daemon ─────────────────────────────────────────────────────────
# Required for .local hostname resolution (KDE Connect, network printers, etc.)
# Also satisfies the mDNS UFW rule in security.sh.
pacman -S --noconfirm --needed avahi nss-mdns
systemctl enable avahi-daemon

# ── Configure nss-mdns for .local resolution ──────────────────────────────────
# Insert 'mdns_minimal' into /etc/nsswitch.conf before 'resolve' or 'dns'.
# This lets getaddrinfo() resolve .local names via Avahi without going to DNS.
if ! grep -q 'mdns_minimal' /etc/nsswitch.conf; then
    sed -i 's/^hosts:.*/hosts: mymachines mdns_minimal [NOTFOUND=return] resolve [!UNAVAIL=return] files myhostname dns/'         /etc/nsswitch.conf
fi

# ── XDG user dirs ─────────────────────────────────────────────────────────────
# Creates ~/Desktop, ~/Downloads, ~/Documents etc. on first login.
# xdg-user-dirs-update is triggered automatically by PAM on login via
# /etc/xdg/autostart/xdg-user-dirs-update.desktop — no manual enable needed.
# Ensure it runs for new users by adding to /etc/skel:
mkdir -p /etc/skel/.config
xdg-user-dirs-update --force 2>/dev/null || true

info "KDE Plasma installation complete."
info "SDDM will start on next boot. Login at the graphical prompt."
