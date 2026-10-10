#!/usr/bin/env bash
# lib/secrets.sh — decrypt SOPS secrets from USB age key to tmpfs

set -Eeuo pipefail

# shellcheck source=./install-state.sh
declare -F install_state_update >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/install-state.sh"

_SECRETS_TMPFS=""
_SECRETS_HAS_HOST=0
_SECRETS_USER_NAMES=()

# secrets_load <profile>
# Discovers users/*/secrets.json and hosts/<profile>/secrets.json,
# decrypts each to a tmpfs, and writes paths into install-state.json.
# Caller must register: trap secrets_cleanup EXIT

# Arch ISO ships neither age nor sops; install them on demand.
_secrets_install_tools() {
  local -a packages=()
  command_exists age  || packages+=("age")
  command_exists sops || packages+=("sops")
  [[ ${#packages[@]} -eq 0 ]] && return 0
  echo "[secrets] installing on live ISO: ${packages[*]}" >&2
  pacman -Sy --noconfirm --needed "${packages[@]}" >&2
}

secrets_load() {
  local profile="$1"

  local host_secrets="${INSTALLER_DIR}/hosts/${profile}/secrets.json"
  # VM hosts live under hosts/vm/<name>/ (fallback mirrors _profile_load).
  [[ -f "$host_secrets" ]] \
    || host_secrets="${INSTALLER_DIR}/hosts/vm/${profile}/secrets.json"
  local -a user_secrets=() user_names=()

  # Scope user secrets to the users this host declares (mirrors runner_run_profiles'
  # .users[]), not every users/*/secrets.json in the repo. Otherwise a
  # committed fixture such as users/vm/test/secrets.json would force every
  # host to demand an age key. When load_profile is unavailable (unit
  # tests sourcing this file standalone) no users are scoped in.
  local host_json="" user user_file
  if host_json="$(load_profile "$profile" 2>/dev/null)"; then
    while IFS= read -r user; do
      [[ -n "$user" ]] || continue
      # VM users live under users/vm/<name>/ (fallback mirrors _profile_load).
      user_file="${INSTALLER_DIR}/users/${user}/secrets.json"
      [[ -f "$user_file" ]] || user_file="${INSTALLER_DIR}/users/vm/${user}/secrets.json"
      [[ -f "$user_file" ]] && { user_secrets+=("$user_file"); user_names+=("$user"); }
    done < <(printf '%s' "$host_json" | jq -r '.users[]?')
  fi

  local has_host=0
  [[ -f "$host_secrets" ]] && has_host=1

  # Gate: nothing to decrypt for this host → skip without installing age/sops
  # or requiring an age key. Secrets tooling runs only where the host or one
  # of its declared users ships an encrypted secrets.json.
  if [[ $has_host -eq 0 && ${#user_secrets[@]} -eq 0 ]]; then
    echo "[secrets] no secrets for host '${profile}' —" \
         "skipping (age/sops not installed)" >&2
    return 0
  fi

  # Something to decrypt → install age + sops on the live ISO on demand.
  _secrets_install_tools || return 1

  local encrypted_age_key=""
  local _downloaded_key=""

  if [[ -n "${SECRETS_KEY_DEVICE:-}" ]]; then
    encrypted_age_key="${SECRETS_KEY_DEVICE}/age/key.age"
  elif key_device="$(_secrets_find_key_device 2>/dev/null)"; then
    encrypted_age_key="${key_device}/age/key.age"
  elif [[ -n "${SECRETS_KEY_URL:-}" ]]; then
    _downloaded_key="$(mktemp --suffix=.age)"
    echo "[secrets] downloading age key from ${SECRETS_KEY_URL}" >&2
    if ! curl -fsSL "$SECRETS_KEY_URL" -o "$_downloaded_key"; then
      echo "[secrets] failed to download age key" >&2
      rm -f "$_downloaded_key"
      return 1
    fi
    encrypted_age_key="$_downloaded_key"
  else
    echo "[secrets] no key source —" \
         "plug in USB or set options.age_key_url in the host profile" >&2
    return 1
  fi

  _SECRETS_TMPFS="$(mktemp -d)"
  mount -t tmpfs -o size=10m,mode=700 tmpfs "$_SECRETS_TMPFS"

  local age_key="${_SECRETS_TMPFS}/keys.txt"
  local _age_rc=0
  if [[ -n "${SECRETS_AGE_PASSPHRASE:-}" ]]; then
    # Non-interactive seam (VM/test harness only): age reads the passphrase from
    # the tty, not stdin, so feed it through a pty via util-linux `script`
    # (mirrors vm/fixtures/regenerate.sh). Operator installs leave
    # SECRETS_AGE_PASSPHRASE unset and are prompted by age as before.
    script -qc "age -d -o '$age_key' '$encrypted_age_key'" /dev/null \
      <<< "${SECRETS_AGE_PASSPHRASE}"$'\n' >/dev/null 2>&1 || _age_rc=$?
  else
    age --decrypt -o "$age_key" "$encrypted_age_key" || _age_rc=$?
  fi
  if (( _age_rc != 0 )); then
    echo "[secrets] age --decrypt failed —" \
         "wrong passphrase, corrupt key, or missing 'age' binary" >&2
    rm -f "$_downloaded_key"
    secrets_cleanup
    return 1
  fi
  rm -f "$_downloaded_key"
  chmod 600 "$age_key"

  if [[ $has_host -eq 1 ]]; then
    local out="${_SECRETS_TMPFS}/host-secrets.json"
    if ! SOPS_AGE_KEY_FILE="$age_key" sops --decrypt "$host_secrets" > "$out"; then
      secrets_cleanup
      return 1
    fi
    chmod 600 "$out"
  fi

  for i in "${!user_secrets[@]}"; do
    local out="${_SECRETS_TMPFS}/${user_names[$i]}-secrets.json"
    if ! SOPS_AGE_KEY_FILE="$age_key" sops --decrypt \
         "${user_secrets[$i]}" > "$out"; then
      secrets_cleanup
      return 1
    fi
    chmod 600 "$out"
  done

  _SECRETS_HAS_HOST="$has_host"
  _SECRETS_USER_NAMES=("${user_names[@]+"${user_names[@]}"}")
}

# secrets_persist_state
# Writes secret tmpfs paths into /mnt/install-state.json (or $INSTALL_STATE).
# Must run after the root pool is mounted, before chroot_configure_system.
secrets_persist_state() {
  [[ -z "${_SECRETS_TMPFS:-}" ]] && return 0

  local state="${INSTALL_STATE:-/mnt/install-state.json}"
  local encoded_path
  mkdir -p "$(dirname "$state")"
  [[ -f "$state" ]] || echo '{}' > "$state"

  install_state_update "$state" '.secrets' '{}'
  if [[ "${_SECRETS_HAS_HOST:-0}" -eq 1 ]]; then
    encoded_path="$(jq -nR --arg v "${_SECRETS_TMPFS}/host-secrets.json" '$v')"
    install_state_update "$state" '.secrets.host' "$encoded_path"
  fi
  local name
  for name in "${_SECRETS_USER_NAMES[@]+"${_SECRETS_USER_NAMES[@]}"}"; do
    encoded_path="$(jq -nR --arg v "${_SECRETS_TMPFS}/${name}-secrets.json" '$v')"
    install_state_update "$state" ".secrets.users[\"$name\"]" "$encoded_path"
  done
}

_secrets_find_key_device() {
  local dev
  dev="$(lsblk -rno NAME,RM,TYPE 2>/dev/null \
    | awk '$2==1 && $3=="disk" {print $1}' | head -1)"
  if [[ -z "$dev" ]]; then
    echo "[secrets] no removable device found" >&2
    return 1
  fi
  local mountpoint
  for mountpoint in "/run/media" "/media" "/mnt"; do
    if [[ -f "${mountpoint}/${dev}/age/key.age" ]]; then
      printf '%s' "${mountpoint}/${dev}"
      return 0
    fi
  done
  echo "[secrets] age key not found on removable device ${dev}" >&2
  return 1
}

secrets_cleanup() {
  [[ -z "${_SECRETS_TMPFS:-}" ]] && return 0
  umount "$_SECRETS_TMPFS" 2>/dev/null || true
  rm -rf "$_SECRETS_TMPFS"
  _SECRETS_TMPFS=""
}

# secrets_print_machine_key
# Reads the Machine Age Key from /mnt/etc/secrets/age/keys.txt after the chroot
# phase and prints the age public key plus the sops updatekeys command.
# No-op if the key file is absent (sops program not installed on this host).
secrets_print_machine_key() {
  local key_file="${MOUNT_ROOT:-/mnt}/etc/secrets/age/keys.txt"
  [[ -f "$key_file" ]] || return 0

  local public_key=""
  if command_exists age-keygen; then
    public_key="$(age-keygen -y "$key_file" 2>/dev/null)" || true
  fi
  if [[ -z "$public_key" ]]; then
    public_key="$(grep '^# public key:' "$key_file" | awk '{print $NF}')" || true
  fi
  [[ -n "$public_key" ]] || return 0

  echo ""
  echo "==> Machine age public key: ${public_key}"
  echo "==> Run: sops updatekeys" \
       ".installer/users/*/secrets.json .installer/hosts/*/secrets.json"
  echo "==> Then update .sops.yaml to include this key and commit."
}
