#!/usr/bin/env bash
# =============================================================================
# programs/dev/emacs/install.sh
# =============================================================================
# Invoked by .installer/lib/profiles/runner.sh inside arch-chroot as the owning
# user with temp NOPASSWD sudo, with INSTALLER_DIR, PROGRAMS, SHELL_COMMONS and
# AUR_HELPER pre-exported.
#
# Installs emacs-wayland (the Arch Wiki's PGTK build) plus what Doom needs
# (git, ripgrep, fd — the Fleet Layer places them, a non-fleet host would not;
# cmake + libvterm build vterm's module, per Doom's vterm README),
# then clones Doom core at the commit in doom-ref (ADR 0160). A re-run fetches
# and re-pins the clone, never deletes it. The Doom config (home/) is applied
# by the Runner's Config Apply pass (ADR 0134), and post-config.sh runs Doom's
# install against it — Doom bakes its config dir's path into what it generates.
# =============================================================================

set -Eeuo pipefail
trap 'echo "[emacs] error on line $LINENO" >&2' ERR

SELF="${PROGRAMS}/dev/emacs"
DOOM_CORE="${HOME}/.config/emacs"
DOOM_URL="https://github.com/doomemacs/core"

print_status info "Installing Emacs (emacs-wayland) and Doom's tools..."
${AUR_HELPER} -S --noconfirm --needed emacs-wayland git ripgrep fd \
  cmake libvterm

# _install_pin_doom <pin> — create the clone if missing, then fetch the pinned
# commit alone and check it out detached.
_install_pin_doom() {
  local pin="$1"
  if [[ ! -d "${DOOM_CORE}/.git" ]]; then
    git init -q "$DOOM_CORE" \
      && git -C "$DOOM_CORE" remote add origin "$DOOM_URL" || return 1
  fi
  git -C "$DOOM_CORE" fetch -q --depth 1 origin "$pin" \
    && git -C "$DOOM_CORE" checkout -q --detach FETCH_HEAD
}

pin="$(grep -vE '^[[:space:]]*(#|$)' "${SELF}/doom-ref")"
if [[ -e "$DOOM_CORE" && ! -d "${DOOM_CORE}/.git" ]]; then
  # A hand-made Emacs config owns the dir: never adopt or clobber it.
  print_status warning "${DOOM_CORE} exists and is not a Doom clone;" \
    "skipping Doom."
elif _install_pin_doom "$pin"; then
  print_status info "Doom core pinned at ${pin:0:12}."
else
  # An upstream/network blip is a gap, not a broken editor: Emacs works, and a
  # re-run (or the operator) re-pins.
  print_status warning "Could not fetch Doom ${pin:0:12} from ${DOOM_URL}."
fi

print_status success "Emacs staged." \
  "Config applied by the Runner pass; Doom synced by post-config.sh."
