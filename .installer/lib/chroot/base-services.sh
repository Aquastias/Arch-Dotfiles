#!/usr/bin/env bash
# lib/chroot/base-services.sh — always-on base daemons
#
# Sourced by lib/chroot/configure.sh inside the chroot. Holds the systemctl
# enables for daemons every host receives regardless of config — network,
# time, and cron (ADR 0026: cron is universal infrastructure, not a System
# Program). Extracted into a function so the set is testable: stub systemctl,
# call enable_base_services, assert each enable.

enable_base_services() {
  systemctl enable NetworkManager
  systemctl enable systemd-resolved
  systemctl enable systemd-timesyncd
  systemctl enable cronie

  # Kill the network-online boot stall. On a NetworkManager laptop/desktop with
  # no link up at boot (Wi-Fi not yet associated), the wait-online units block
  # network-online.target for up to ~2 min; anything that pulls that target into
  # the boot transaction (e.g. clamav-freshclam) then stalls the whole boot. That
  # churn is what pushes pam_systemd's graphical-login session setup past its
  # timeout on impermanence → no XDG_RUNTIME_DIR → black/failed Wayland session.
  # systemd-networkd-wait-online is doubly wrong here (we use NetworkManager, not
  # networkd). Masking both is the standard fix; NetworkManager still brings the
  # link up asynchronously after boot.
  systemctl mask systemd-networkd-wait-online.service
  systemctl mask NetworkManager-wait-online.service
}

# Optional daemons toggled by config. sshd is enabled only when
# options.ssh.enabled=true (SSH_ENABLED in install-state); openssh is already
# pacstrapped via the Base Package List, so this only flips the service.
enable_optional_services() {
  if [[ "${SSH_ENABLED:-false}" == "true" ]]; then
    systemctl enable sshd.service
  fi
}
