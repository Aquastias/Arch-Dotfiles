#!/usr/bin/env bash
# =============================================================================
# programs/virtualization/podman/install.sh
# =============================================================================
# Invoked by .installer/lib/profiles/runner.sh inside arch-chroot, as the owning user, with
# INSTALLER_DIR, PROGRAMS, SHELL_COMMONS pre-exported and temp NOPASSWD sudo
# granted.
#
# Installs podman, fuse-overlayfs, and slirp4netns for rootless container
# support. Ensures /etc/subuid and /etc/subgid entries exist for the owning
# user (useradd normally creates these; usermod fills gaps).
# =============================================================================

set -Eeuo pipefail
trap 'echo "[podman] error on line $LINENO" >&2' ERR

${AUR_HELPER} -S --noconfirm --needed podman fuse-overlayfs slirp4netns

SUBUID_FILE="${PODMAN_SUBUID_FILE:-/etc/subuid}"
SUBGID_FILE="${PODMAN_SUBGID_FILE:-/etc/subgid}"

# install_next_subid_range <file> — the 65536-ID range after every range
# already in <file> (from 100000), so two rootless users never share
# subordinate IDs.
install_next_subid_range() {
  local start=100000 _name first count
  # Each "name:first:count" line: the next range starts past the highest.
  # (The `|| -n` keeps a last line that has no newline.)
  if [[ -f "$1" ]]; then
    while IFS=: read -r _name first count || [[ -n "$_name" ]]; do
      [[ "$first" =~ ^[0-9]+$ && "$count" =~ ^[0-9]+$ ]] || continue
      if (( count > 0 && first + count > start )); then
        start=$((first + count))
      fi
    done < "$1"
  fi
  printf '%d-%d\n' "$start" "$((start + 65535))"
}

if ! grep -q "^${USER}:" "$SUBUID_FILE" 2>/dev/null; then
  sudo usermod --add-subuids "$(install_next_subid_range "$SUBUID_FILE")" \
    "$USER"
fi
if ! grep -q "^${USER}:" "$SUBGID_FILE" 2>/dev/null; then
  sudo usermod --add-subgids "$(install_next_subid_range "$SUBGID_FILE")" \
    "$USER"
fi

print_status success "Podman staged for ${USER} (rootless, no group required)."
