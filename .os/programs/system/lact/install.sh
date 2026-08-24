#!/usr/bin/env bash
# =============================================================================
# programs/system/lact/install.sh
# =============================================================================
# Invoked by .os/lib/profiles/runner.sh inside arch-chroot, as root.
# Env vars provided by the runner: OS_DIR, PROGRAMS, SHELL_COMMONS.
#
# Installs lact; the runner enables lactd.service (declared in config.jsonc
# system_services) so the LACT GPU configuration/monitoring daemon is up on
# first boot — the GUI applies nothing without it (upstream LACT).
# =============================================================================

set -Eeuo pipefail
trap 'echo "[lact] error on line $LINENO" >&2' ERR

print_status info "Installing lact..."
pacman -S --noconfirm --needed lact

print_status success "lact staged." \
  "lactd.service drives GPU tuning/monitoring at boot."
