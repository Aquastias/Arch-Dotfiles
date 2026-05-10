#!/usr/bin/env bash
# lib/chroot/create-user.sh — Create or update a system user.
# Args: NAME LOGIN_SHELL GROUPS_CSV PASSWORD
# Run inside arch-chroot by profiles.sh::_profiles_create_user().
set -Eeuo pipefail
trap 'echo "[chroot:create-user] failed at line $LINENO" >&2' ERR

NAME="$1"; LOGIN_SHELL="$2"; GROUPS_CSV="$3"; PASSWORD="$4"

# Groups like docker/libvirt/kvm are created by their packages, installed
# later.  Filter to only groups that currently exist; the remainder are
# applied by _profiles_apply_user_groups after program installation.
filter_existing_groups() {
  local csv="$1" existing="" g
  IFS=',' read -ra _ALL <<< "$csv"
  for g in "${_ALL[@]}"; do
    [[ -z "$g" ]] && continue
    if getent group "$g" >/dev/null 2>&1; then
      existing+="${g},"
    else
      echo "  [create-user] group '${g}' absent — will reconcile after program install" >&2
    fi
  done
  printf '%s' "${existing%,}"
}

PRESENT="$(filter_existing_groups "$GROUPS_CSV")"

if id "$NAME" &>/dev/null; then
  usermod -s "$LOGIN_SHELL" "$NAME"
  [[ -n "$PRESENT" ]] && usermod -G "$PRESENT" "$NAME"
else
  if [[ -n "$PRESENT" ]]; then
    useradd -m -s "$LOGIN_SHELL" -G "$PRESENT" "$NAME"
  else
    useradd -m -s "$LOGIN_SHELL" "$NAME"
  fi
fi
printf '%s:%s\n' "$NAME" "$PASSWORD" | chpasswd
