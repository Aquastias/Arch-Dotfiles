#!/usr/bin/env bash
# =============================================================================
# programs/gaming/gamemode/install.sh
# =============================================================================
# Invoked by .installer/lib/profiles/runner.sh inside arch-chroot, as root.
# Env vars provided by the runner: INSTALLER_DIR, PROGRAMS, SHELL_COMMONS.
#
# Installs `gamemode` (and `lib32-gamemode` for 32-bit games when multilib is
# enabled). That is the whole install: no service enable — gamemoded is a
# D-Bus-activated systemd USER service that starts on demand — and no group,
# since the CPU-governor escalation goes through polkit (a hard dependency of
# the package), not the deprecated `gamemode` group. Games opt in at runtime
# with `gamemoderun`.
# =============================================================================

set -Eeuo pipefail
trap 'echo "[gamemode] error on line $LINENO" >&2' ERR

print_status info "Installing gamemode..."
pacman -S --noconfirm --needed gamemode

# lib32-gamemode lives in [multilib]; only install it where that repo is on, so
# a non-multilib host does not abort the whole run on a missing 32-bit package.
if pacman -Sl multilib &>/dev/null; then
  pacman -S --noconfirm --needed lib32-gamemode
else
  print_status warning "multilib disabled — skipping lib32-gamemode" \
    "(no GameMode for 32-bit games)."
fi

print_status success "gamemode staged." \
  "Opt games in with 'gamemoderun %command%' (Steam) or 'gamemoderun <game>';" \
  "verify after boot with 'gamemoded -t'."
