#!/usr/bin/env bash
# =============================================================================
# lib/guided-secrets.sh — Guided Installer no-SOPS password injector (issue 07)
# =============================================================================
# The guided counterpart of the Secrets Module (lib/secrets.sh): sets root and
# per-user passwords (+ optional SSH identities) WITHOUT SOPS. Collected in the
# TUI at Proceed; never in Config State, Save, or Export.
#
# Writes the same *decrypted* file shape the Secrets Module produces
# (host-secrets.json, <name>-secrets.json) into a tmpfs dir, pointing the
# back-end at them via install-state's `.guided_passwords.*`. It does NOT touch
# `.secrets.*`, which gates implicit SOPS activation (ADR 0025) that guided
# passwords must not trigger. The chroot + Runner resolvers read both keys.
#
# Requires install_state_update (lib/install-state.sh).
# =============================================================================

# shellcheck source=./install-state.sh
declare -F install_state_update >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/install-state.sh"
# INSTALL_DEFAULT_ENC_PASSPHRASE (ADR 0059) — the 8-char passphrase default.
# shellcheck source=./globals.sh
[[ -n "${INSTALL_DEFAULT_ENC_PASSPHRASE:-}" ]] \
  || source "${BASH_SOURCE[0]%/*}/globals.sh"

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

# guided_default_missing_secrets <manifest> <users-json> <encryption-bool>
# The ADR-0055 default posture: fill any UNSET secret — root and every effective
# user (from <users-json>, a JSON array of names) with the `12345` account
# default, and, when <encryption-bool> is "true", the encryption passphrase with
# the 8-char disk default (ADR 0059 — accounts have no length floor, the disk
# passphrase does: ZFS rejects a 5-char one at pool creation). An already-set,
# non-empty value is left untouched, so an operator override (or an age-decrypted
# secret merged in earlier) always wins over the default. Pure: JSON in, JSON out.
guided_default_missing_secrets() {
  local manifest="$1" users="${2:-[]}" enc="${3:-false}"
  manifest="$(jq --argjson u "$users" '
    def dflt: if (. // "") == "" then "12345" else . end;
    .root_password = (.root_password | dflt)
    | reduce $u[] as $n (.; .users[$n].password = (.users[$n].password | dflt))
  ' <<<"$manifest")"
  if [[ "$enc" == "true" ]]; then
    manifest="$(jq --arg d "$INSTALL_DEFAULT_ENC_PASSPHRASE" '
      .enc_passphrase = (if (.enc_passphrase // "") == "" then $d
                         else .enc_passphrase end)' <<<"$manifest")"
  fi
  printf '%s\n' "$manifest"
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
