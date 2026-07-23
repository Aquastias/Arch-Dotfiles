#!/usr/bin/env bash
# lib/chroot/create-user.sh — Create or update a system user.
# Args: NAME LOGIN_SHELL GROUPS_CSV PASSWORD [SECRETS_FILE]
# Run inside arch-chroot by profiles.sh::_profiles_create_user().
set -Eeuo pipefail
# shellcheck source=./chroot-common.sh
source "$(dirname "${BASH_SOURCE[0]}")/chroot-common.sh"
chroot_err_trap "create-user"

NAME="$1"; LOGIN_SHELL="$2"; GROUPS_CSV="$3"; PASSWORD="$4"
SECRETS_FILE="${5:-}"

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
      echo "  [create-user] group '${g}' absent —" \
           "will reconcile after program install" >&2
    fi
  done
  printf '%s' "${existing%,}"
}

# A login shell whose binary is absent is unusable: display managers exec
# `$SHELL --login` and bounce back to the greeter before the session ever runs
# (SDDM's wayland-session wrapper does exactly this). The guided menu offers
# zsh/fish, but neither is guaranteed by a profile's package list — so install
# the chosen shell's package here. bash/sh ship with base and are skipped.
ensure_login_shell_installed() {
  local shell="$1" bin pkg
  [[ -x "$shell" ]] && return 0
  bin="$(basename "$shell")"
  case "$bin" in
    bash|sh) return 0 ;;
    zsh)     pkg=zsh ;;
    fish)    pkg=fish ;;
    *)       pkg="$bin" ;;
  esac
  echo "  [create-user] login shell '${shell}' missing —" \
       "installing '${pkg}'" >&2
  pacman -S --noconfirm --needed "$pkg"
}

ensure_login_shell_installed "$LOGIN_SHELL"

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

if [[ -n "$SECRETS_FILE" && -f "$SECRETS_FILE" ]]; then
  sec_pw="$(jq -r '.password // empty' "$SECRETS_FILE")"
  [[ -n "$sec_pw" ]] && PASSWORD="$sec_pw"

  sec_ssh_key="$(jq -r '.ssh_identity_private_key // empty' "$SECRETS_FILE")"
  if [[ -n "$sec_ssh_key" ]]; then
    sec_key_type="$(jq -r \
      '.ssh_identity_key_type // "ed25519"' "$SECRETS_FILE")"
    _ssh_dir="${HOME_BASE:-/home}/$NAME/.ssh"
    mkdir -p "$_ssh_dir"
    chmod 700 "$_ssh_dir"
    chown "$NAME:$NAME" "$_ssh_dir"
    printf '%s\n' "$sec_ssh_key" > "$_ssh_dir/id_${sec_key_type}"
    chmod 600 "$_ssh_dir/id_${sec_key_type}"
    ssh-keygen -y -f "$_ssh_dir/id_${sec_key_type}" \
      > "$_ssh_dir/id_${sec_key_type}.pub"
    chmod 644 "$_ssh_dir/id_${sec_key_type}.pub"
    chown "$NAME:$NAME" \
      "$_ssh_dir/id_${sec_key_type}" "$_ssh_dir/id_${sec_key_type}.pub"
  fi
fi

printf '%s:%s\n' "$NAME" "$PASSWORD" | chpasswd
