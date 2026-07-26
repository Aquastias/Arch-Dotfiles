#!/usr/bin/env bash
# =============================================================================
# lib/guided-secrets-file.sh — in-menu credential handoff file (ticket 03)
# =============================================================================
# The Guided Installer captures the root + per-user passwords INSIDE the
# persistent fzf. The masked prompt runs in an execute() subprocess that cannot
# write the parent shell's variables, so the captured secret is handed back
# through a dedicated tmpfs file. Its shape is identical to the no-SOPS
# manifest — { root_password?, users?: { <name>: { password } } } — so the
# parent loads it into the existing held-aside vars and the tested manifest
# path (_guided_secrets_manifest) stays unchanged.
#
# This file is NEVER referenced by config emit / Save / Export, so the Config
# State stays secret-free (the invariant ADR 0042 established). It lives on
# tmpfs for the life of the menu and is cleared by the persistent-fzf RETURN
# trap alongside the other GUIDED_*_FILE files.
# =============================================================================

# guided_secretsfile_init <file> — ensure <file> exists as an empty object.
guided_secretsfile_init() { [[ -s "$1" ]] || printf '{}\n' > "$1"; }

# guided_secretsfile_set_root <file> <password>
guided_secretsfile_set_root() {
  local f="$1" pw="$2" tmp
  guided_secretsfile_init "$f"
  tmp="$(jq --arg pw "$pw" '.root_password = $pw' "$f")" \
    && printf '%s\n' "$tmp" > "$f"
}

# guided_secretsfile_set_user <file> <name> <password>
guided_secretsfile_set_user() {
  local f="$1" n="$2" pw="$3" tmp
  guided_secretsfile_init "$f"
  tmp="$(jq --arg n "$n" --arg pw "$pw" '.users[$n] = {password: $pw}' "$f")" \
    && printf '%s\n' "$tmp" > "$f"
}

# guided_secretsfile_set_enc <file> <passphrase> — the ZFS/LUKS encryption
# passphrase (ADR 0054). Same handoff file as the passwords; consumed pre-chroot
# from the manifest by collect_enc_passphrase, never staged to install-state.
guided_secretsfile_set_enc() {
  local f="$1" pw="$2" tmp
  guided_secretsfile_init "$f"
  tmp="$(jq --arg pw "$pw" '.enc_passphrase = $pw' "$f")" \
    && printf '%s\n' "$tmp" > "$f"
}

# guided_secretsfile_has_root <file> → rc0 iff a non-empty root password is set.
guided_secretsfile_has_root() {
  [[ -s "$1" ]] || return 1
  [[ -n "$(jq -r '.root_password // "" | select(. != "")' "$1" 2>/dev/null)" ]]
}

# guided_secretsfile_has_user <file> <name> → rc0 iff <name> has a non-empty pw.
guided_secretsfile_has_user() {
  [[ -s "$1" ]] || return 1
  [[ -n "$(jq -r --arg n "$2" \
    '.users[$n].password // "" | select(. != "")' "$1" 2>/dev/null)" ]]
}

# guided_secretsfile_has_enc <file> → rc0 iff a non-empty passphrase is set.
guided_secretsfile_has_enc() {
  [[ -s "$1" ]] || return 1
  [[ -n "$(jq -r '.enc_passphrase // "" | select(. != "")' "$1" 2>/dev/null)" ]]
}

# guided_secretsfile_missing <file> <users-json> → the missing credentials, one
# per line: "root" when root is unset, then each user name in <users-json> (a
# JSON array) lacking a password. Empty output = complete — drives the Proceed
# gate.
guided_secretsfile_missing() {
  local f="$1" users="$2" n
  guided_secretsfile_has_root "$f" || printf 'root\n'
  while IFS= read -r n; do
    [[ -n "$n" ]] || continue
    guided_secretsfile_has_user "$f" "$n" || printf '%s\n' "$n"
  done < <(jq -r '(. // []) | .[]' <<<"$users" 2>/dev/null)
}
