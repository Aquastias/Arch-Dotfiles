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
}
