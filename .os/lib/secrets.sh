#!/usr/bin/env bash
# lib/secrets.sh — decrypt SOPS secrets from USB age key to tmpfs

set -Eeuo pipefail

_SECRETS_TMPFS=""

# secrets_load <hostname>
# Discovers users/*/secrets.json and hosts/<hostname>/secrets.json,
# decrypts each to a tmpfs, and writes paths into install-state.json.
# Caller must register: trap secrets_cleanup EXIT
secrets_load() {
  local hostname="$1"

  local host_sec="${OS_DIR}/hosts/${hostname}/secrets.json"
  local -a user_secs=() user_names=()

  while IFS= read -r -d '' f; do
    local name
    name="$(basename "$(dirname "$f")")"
    user_secs+=("$f")
    user_names+=("$name")
  done < <(find "${OS_DIR}/users" -maxdepth 2 -name "secrets.json" -print0 2>/dev/null | sort -z)

  local has_host=0
  [[ -f "$host_sec" ]] && has_host=1

  if [[ $has_host -eq 0 && ${#user_secs[@]} -eq 0 ]]; then
    echo "[secrets] no secrets files found — install continues with defaults" >&2
    return 0
  fi

  local age_enc=""
  local _url_tmp=""

  if [[ -n "${SECRETS_KEY_DEVICE:-}" ]]; then
    age_enc="${SECRETS_KEY_DEVICE}/age/key.age"
  elif key_device="$(_secrets_find_key_device 2>/dev/null)"; then
    age_enc="${key_device}/age/key.age"
  elif [[ -n "${SECRETS_KEY_URL:-}" ]]; then
    _url_tmp="$(mktemp --suffix=.age)"
    echo "[secrets] downloading age key from ${SECRETS_KEY_URL}" >&2
    if ! curl -fsSL "$SECRETS_KEY_URL" -o "$_url_tmp"; then
      echo "[secrets] failed to download age key" >&2
      rm -f "$_url_tmp"
      return 1
    fi
    age_enc="$_url_tmp"
  else
    echo "[secrets] no key source — plug in USB or set age_key_url in install.jsonc" >&2
    return 1
  fi

  _SECRETS_TMPFS="$(mktemp -d)"
  mount -t tmpfs -o size=10m,mode=700 tmpfs "$_SECRETS_TMPFS"

  local age_key="${_SECRETS_TMPFS}/keys.txt"
  if ! age --decrypt -o "$age_key" "$age_enc"; then
    echo "[secrets] wrong passphrase or corrupt key" >&2
    rm -f "$_url_tmp"
    secrets_cleanup
    return 1
  fi
  rm -f "$_url_tmp"
  chmod 600 "$age_key"

  if [[ $has_host -eq 1 ]]; then
    local out="${_SECRETS_TMPFS}/host-secrets.json"
    if ! SOPS_AGE_KEY_FILE="$age_key" sops --decrypt "$host_sec" > "$out"; then
      secrets_cleanup
      return 1
    fi
    chmod 600 "$out"
  fi

  for i in "${!user_secs[@]}"; do
    local out="${_SECRETS_TMPFS}/${user_names[$i]}-secrets.json"
    if ! SOPS_AGE_KEY_FILE="$age_key" sops --decrypt "${user_secs[$i]}" > "$out"; then
      secrets_cleanup
      return 1
    fi
    chmod 600 "$out"
  done

  _secrets_write_state "$has_host" "${user_names[@]+"${user_names[@]}"}"
}

_secrets_write_state() {
  local has_host="$1"
  shift
  local -a names=("$@")

  local state="${INSTALL_STATE:-/mnt/install-state.json}"
  local secrets="{}"

  if [[ $has_host -eq 1 ]]; then
    secrets="$(jq --arg p "${_SECRETS_TMPFS}/host-secrets.json" \
      '.host = $p' <<< "$secrets")"
  fi
  for name in "${names[@]+"${names[@]}"}"; do
    secrets="$(jq --arg n "$name" --arg p "${_SECRETS_TMPFS}/${name}-secrets.json" \
      '.users[$n] = $p' <<< "$secrets")"
  done

  local tmp
  tmp="$(mktemp)"
  jq --argjson s "$secrets" '.secrets = $s' "$state" > "$tmp"
  mv "$tmp" "$state"
}

_secrets_find_key_device() {
  local dev
  dev="$(lsblk -rno NAME,RM,TYPE 2>/dev/null \
    | awk '$2==1 && $3=="disk" {print $1}' | head -1)"
  if [[ -z "$dev" ]]; then
    echo "[secrets] no removable device found" >&2
    return 1
  fi
  local mp
  for mp in "/run/media" "/media" "/mnt"; do
    if [[ -f "${mp}/${dev}/age/key.age" ]]; then
      printf '%s' "${mp}/${dev}"
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

  local pub_key=""
  if command -v age-keygen &>/dev/null; then
    pub_key="$(age-keygen -y "$key_file" 2>/dev/null)" || true
  fi
  if [[ -z "$pub_key" ]]; then
    pub_key="$(grep '^# public key:' "$key_file" | awk '{print $NF}')" || true
  fi
  [[ -n "$pub_key" ]] || return 0

  echo ""
  echo "==> Machine age public key: ${pub_key}"
  echo "==> Run: sops updatekeys .os/users/*/secrets.json .os/hosts/*/secrets.json"
  echo "==> Then update .sops.yaml to include this key and commit."
}
