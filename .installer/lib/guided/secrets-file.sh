#!/usr/bin/env bash
# =============================================================================
# lib/guided/secrets-file.sh — in-menu credential handoff file (ticket 03)
# =============================================================================
# The Guided Installer captures the root + per-user passwords INSIDE the
# persistent fzf. The masked prompt runs in an execute() subprocess that cannot
# write the parent shell's variables, so the captured secret is handed back
# through a dedicated tmpfs file. Its shape is identical to the no-SOPS
# manifest — { root_password?, users?: { <name>: { password } } } — so the
# parent loads it into the existing held-aside vars and the tested manifest
# path (_guided_shell_secrets_manifest) stays unchanged.
#
# This file is NEVER referenced by config emit / Save / Export, so the Config
# State stays secret-free (the invariant ADR 0042 established). It lives on
# tmpfs for the life of the menu and is cleared by the persistent-fzf RETURN
# trap alongside the other GUIDED_*_FILE files.
#
# Used by: lib/guided/controller.sh, lib/guided/fzf-entry.sh.
# =============================================================================

# guided_secrets_file_init <file> — ensure <file> exists as an empty object.
guided_secrets_file_init() { [[ -s "$1" ]] || printf '{}\n' > "$1"; }

# guided_secrets_file_set_root <file> <password>
guided_secrets_file_set_root() {
  local secrets_file="$1" password="$2" updated_json
  guided_secrets_file_init "$secrets_file"
  updated_json="$(jq --arg pw "$password" '.root_password = $pw' \
    "$secrets_file")" \
    && printf '%s\n' "$updated_json" > "$secrets_file"
}

# guided_secrets_file_set_user <file> <name> <password>
guided_secrets_file_set_user() {
  local secrets_file="$1" user="$2" password="$3" updated_json
  guided_secrets_file_init "$secrets_file"
  updated_json="$(jq --arg n "$user" --arg pw "$password" \
    '.users[$n] = {password: $pw}' "$secrets_file")" \
    && printf '%s\n' "$updated_json" > "$secrets_file"
}

# guided_secrets_file_set_encryption <file> <passphrase> — the ZFS/LUKS
# encryption passphrase (ADR 0054). Same handoff file as the passwords; consumed
# pre-chroot from the manifest by zfs_collect_encryption_passphrase, never
# staged to install-state.
guided_secrets_file_set_encryption() {
  local secrets_file="$1" password="$2" updated_json
  guided_secrets_file_init "$secrets_file"
  updated_json="$(jq --arg pw "$password" '.enc_passphrase = $pw' \
    "$secrets_file")" \
    && printf '%s\n' "$updated_json" > "$secrets_file"
}

# guided_secrets_file_has_root <file> → rc0 iff a non-empty root password is
# set.
guided_secrets_file_has_root() {
  [[ -s "$1" ]] || return 1
  [[ -n "$(jq -r '.root_password // "" | select(. != "")' "$1" 2>/dev/null)" ]]
}

# guided_secrets_file_has_user <file> <name> → rc0 iff <name> has a non-empty
# pw.
guided_secrets_file_has_user() {
  [[ -s "$1" ]] || return 1
  [[ -n "$(jq -r --arg n "$2" \
    '.users[$n].password // "" | select(. != "")' "$1" 2>/dev/null)" ]]
}

# guided_secrets_file_has_encryption <file> → rc0 iff a non-empty passphrase is
# set.
guided_secrets_file_has_encryption() {
  [[ -s "$1" ]] || return 1
  [[ -n "$(jq -r '.enc_passphrase // "" | select(. != "")' "$1" 2>/dev/null)" ]]
}

# guided_secrets_file_missing <file> <users-json> → the missing credentials, one
# per line: "root" when root is unset, then each user name in <users-json> (a
# JSON array) lacking a password. Empty output = complete — drives the Proceed
# gate.
guided_secrets_file_missing() {
  local secrets_file="$1" users="$2" user
  guided_secrets_file_has_root "$secrets_file" || printf 'root\n'
  while IFS= read -r user; do
    [[ -n "$user" ]] || continue
    guided_secrets_file_has_user "$secrets_file" "$user" \
      || printf '%s\n' "$user"
  done < <(jq -r '(. // []) | .[]' <<<"$users" 2>/dev/null)
}
