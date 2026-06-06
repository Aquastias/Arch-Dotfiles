#!/usr/bin/env bash
# =============================================================================
# programs/virtualization/podman/install.sh
# =============================================================================
# Invoked by .os/lib/profiles/runner.sh inside arch-chroot, as the owning user, with
# OS_DIR, PROGRAMS, SHELL_COMMONS pre-exported and temp NOPASSWD sudo granted.
#
# Installs podman, fuse-overlayfs, and slirp4netns for rootless container
# support. Ensures /etc/subuid and /etc/subgid entries exist for the owning
# user (useradd normally creates these; usermod fills gaps).
# =============================================================================

set -Eeuo pipefail
trap 'echo "[podman] error on line $LINENO" >&2' ERR

paru -S --noconfirm --needed podman fuse-overlayfs slirp4netns

grep -q "^${USER}:" /etc/subuid \
  || sudo usermod --add-subuids 100000-165535 "$USER"
grep -q "^${USER}:" /etc/subgid \
  || sudo usermod --add-subgids 100000-165535 "$USER"

print_status success "Podman staged for ${USER} (rootless, no group required)."
