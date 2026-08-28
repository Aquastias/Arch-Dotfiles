#!/usr/bin/env bash
# =============================================================================
# lib/guided-userforms.sh — Guided Installer install-scoped per-user edits (0051)
# =============================================================================
# The User Editor (ADR 0051) lets the operator change a user's profile fields
# (shell, sudo, groups, …) INSIDE the persistent fzf. Those edits are
# install-scoped: they take effect on the installed machine but must never
# rewrite a committed users/<name>/profile.jsonc in the repo, and — like
# passwords — must never enter the Config State (so Save/Export stay clean).
#
# So each edit is held aside as a sparse User Profile DELTA in a dedicated tmpfs
# file, keyed by user name: { "<name>": { shell?, sudo?, groups?, … } }. The
# controller reads/writes it through these pure helpers (fzf binds run as
# subprocesses, so a shell variable can't carry the state); at Proceed the deltas
# are merged onto each user's profile on the install clone. The file lives on
# tmpfs for the life of the menu and is cleared by the persistent-fzf RETURN trap
# alongside the other GUIDED_*_FILE files.
#
# Pure: a file path + JSON in, a file mutation or JSON out. No fzf, no tty.
# =============================================================================

# guided_userforms_init <file> — ensure <file> exists as an empty object.
guided_userforms_init() { [[ -s "$1" ]] || printf '{}\n' > "$1"; }

# guided_userform_get <file> <name> — the delta object for <name> ({} if none).
guided_userform_get() {
  [[ -s "$1" ]] || { printf '{}'; return; }
  jq -c --arg n "$2" '.[$n] // {}' "$1" 2>/dev/null || printf '{}'
}

# guided_userform_field <file> <name> <key> — the raw string value at
# .[name][key], or empty when unset. For scalar fields (shell); callers default.
guided_userform_field() {
  [[ -s "$1" ]] || return 0
  jq -r --arg n "$2" --arg k "$3" '.[$n][$k] // empty' "$1" 2>/dev/null
}

# guided_userform_set <file> <name> <key> <json-value> — set .[name][key] to the
# JSON value (a quoted string for scalars, or any JSON for arrays/bools). Creates
# the per-user object as needed.
guided_userform_set() {
  local f="$1" n="$2" k="$3" v="$4" tmp
  guided_userforms_init "$f"
  tmp="$(jq --arg n "$n" --arg k "$k" --argjson v "$v" \
    '.[$n][$k] = $v' "$f")" && printf '%s\n' "$tmp" > "$f"
}

# guided_userform_unset <file> <name> <key> — drop a single field from a user's
# delta (strict-delta: an edit that lands back on the committed value leaves no
# override). Removes the per-user object entirely once it is empty. No-op on a
# missing file.
guided_userform_unset() {
  local f="$1" n="$2" k="$3" tmp
  [[ -s "$f" ]] || return 0
  tmp="$(jq --arg n "$n" --arg k "$k" \
    'if .[$n] then (.[$n] |= del(.[$k])
       | if (.[$n] == {}) then del(.[$n]) else . end) else . end' "$f")" \
    && printf '%s\n' "$tmp" > "$f"
}

# guided_userform_clear <file> <name> — drop a user's whole delta (used when a
# session-created user is removed). No-op on a missing file.
guided_userform_clear() {
  local f="$1" n="$2" tmp
  [[ -s "$f" ]] || return 0
  tmp="$(jq --arg n "$n" 'del(.[$n])' "$f")" && printf '%s\n' "$tmp" > "$f"
}

# guided_userform_names <file> — the user names carrying a non-empty delta, one
# per line. Drives the Save-warn predicate (slice 04) and the Proceed merge.
guided_userform_names() {
  [[ -s "$1" ]] || return 0
  jq -r 'to_entries[] | select(.value != {}) | .key' "$1" 2>/dev/null
}
