#!/usr/bin/env bash
# =============================================================================
# lib/guided-secrets.sh — Guided Installer no-SOPS password injector (issue 07)
# =============================================================================
# The guided counterpart of the Secrets Module (lib/secrets.sh): it sets root
# and per-user passwords (and optional SSH identities) WITHOUT SOPS. Passwords
# are collected in the TUI at Proceed, never enter the Config State, and are
# never written by Save or Export — so no plaintext secret lands in a committed
# or exported file.
#
# It writes the same *decrypted* file shape the Secrets Module decrypts to —
# host-secrets.json `{root_password}` and <name>-secrets.json `{password,
# ssh_identity_private_key?, ssh_identity_key_type?}` — into a tmpfs dir, and
# points the back-end at them via install-state's `.guided_passwords.*` key.
# Crucially it does NOT touch `.secrets.*`: that key gates implicit SOPS-program
# activation (ADR 0025), which guided passwords must not trigger. The chroot
# host-secrets resolver and the Runner user-secrets resolver read both keys.
#
# Requires install_state_update (lib/install-state.sh).
# =============================================================================

# shellcheck source=./install-state.sh
[[ "$(type -t install_state_update)" == "function" ]] \
  || source "${BASH_SOURCE[0]%/*}/install-state.sh"

# guided_write_passwords <secrets-json> <dir> <state-file>
# <secrets-json>: { root_password?: str,
#                   users?: { <name>: { password, ssh_identity_private_key?,
#                                        ssh_identity_key_type? } } }
# Writes the decrypted files under <dir> and records their paths in the
# install-state file under `.guided_passwords.*`. A missing root_password / empty
# users object simply writes fewer files.
guided_write_passwords() {
  local secrets="$1" dir="$2" state="$3" enc
  mkdir -p "$dir"
  [[ -f "$state" ]] || echo '{}' > "$state"

  install_state_update "$state" '.guided_passwords' '{}'

  local root_pw
  root_pw="$(jq -r '.root_password // empty' <<<"$secrets")"
  if [[ -n "$root_pw" ]]; then
    local hf="${dir}/host-secrets.json"
    jq -n --arg pw "$root_pw" '{root_password: $pw}' > "$hf"
    enc="$(jq -nR --arg v "$hf" '$v')"
    install_state_update "$state" '.guided_passwords.host' "$enc"
  fi

  local name uf
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    uf="${dir}/${name}-secrets.json"
    jq -c --arg n "$name" '.users[$n]' <<<"$secrets" > "$uf"
    enc="$(jq -nR --arg v "$uf" '$v')"
    install_state_update "$state" ".guided_passwords.users[\"${name}\"]" "$enc"
  done < <(jq -r '(.users // {}) | keys[]' <<<"$secrets")
}

# tmpfs dir owned by this module, holding the decrypted guided password files
# for the life of the install (the chroot + Runner copy from it). Cleared by
# guided_secrets_cleanup.
_GUIDED_SECRETS_DIR=""

# guided_persist_passwords <state-file>
# Symmetric with secrets_persist_state: when the Guided Installer staged a
# password manifest (GUIDED_SECRETS_MANIFEST), materialize it into a tmpfs dir
# this module owns and record the paths under .guided_passwords.* in
# <state-file>. No-op when no manifest. Pair with guided_secrets_cleanup.
# Must run after /mnt is mounted (the state file lives under /mnt).
guided_persist_passwords() {
  local state="$1"
  [[ -n "${GUIDED_SECRETS_MANIFEST:-}" && -s "${GUIDED_SECRETS_MANIFEST}" ]] \
    || return 0
  _GUIDED_SECRETS_DIR="$(mktemp -d /run/guided-secrets.XXXXXX)"
  guided_write_passwords "$(cat "${GUIDED_SECRETS_MANIFEST}")" \
    "${_GUIDED_SECRETS_DIR}" "${state}"
}

# guided_secrets_cleanup
# Removes the staged plaintext guided passwords once the chroot + Runner have
# consumed them. No-op when nothing was staged. (Live-ISO /run is RAM, but
# clear it eagerly all the same.)
guided_secrets_cleanup() {
  [[ -n "${_GUIDED_SECRETS_DIR:-}" ]] || return 0
  rm -rf "${_GUIDED_SECRETS_DIR}"
  _GUIDED_SECRETS_DIR=""
}
