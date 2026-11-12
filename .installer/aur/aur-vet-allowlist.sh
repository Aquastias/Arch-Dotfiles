#!/usr/bin/env bash
# =============================================================================
# aur-vet-allowlist.sh — aur-vet's allowlist and prompts (ADR 0149)
# =============================================================================
# Sourced by aur-vet (it provides say, die and SELF_DIRECTORY).
# allow.tsv: pkgbase rule note — a suspicious rule accepted for a package at
# any version. The only stored state; nothing is pinned.
# =============================================================================

store_directory() {
  if [[ -n "${AUR_VET_STORE:-}" ]]; then printf '%s' "$AUR_VET_STORE"
  elif [[ -f "$SELF_DIRECTORY/allow.tsv" ]]; then printf '%s' "$SELF_DIRECTORY"
  else printf '%s' /etc/aur-vet; fi
}

# Unattended never prompts. The installer says so explicitly; otherwise a
# terminal on stdin means a human is there. AUR_VET_INTERACTIVE forces the
# prompt (tests) — it can only ask for more review, never skip it.
unattended() {
  [[ "${AUR_VET_UNATTENDED:-}" == 1 ]] && return 0
  [[ "${AUR_VET_INTERACTIVE:-}" == 1 ]] && return 1
  [[ ! -t 0 ]]
}

today() { date -u -d "@${AUR_VET_NOW:-$(date +%s)}" +%F; }

# Is suspicious <rule> accepted for <pkgbase>? A row is
# "<pkgbase><TAB><rule>[<TAB><note>]".
allowed() {
  local file line
  file="$(store_directory)/allow.tsv"
  [[ -r "$file" ]] || return 1
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" == "$1"$'\t'"$2" || "$line" == "$1"$'\t'"$2"$'\t'* ]] \
      && return 0
  done < "$file"
  return 1
}

# Replace <file>'s content with stdin. A writable store (repo, tests) is
# rewritten in place via a temp file in its own directory, so a failed write
# leaves the old file intact. The booted store is root-owned, so user-level
# malware can't forge allowlist rows (ADR 0143): writes go through sudo.
store_put() {
  local file="$1" temporary
  if [[ -w "$(dirname "$file")" ]]; then
    temporary="$(mktemp "${file}.XXXXXX")"
    cat > "$temporary"
    chmod 0644 "$temporary"
    command mv -f "$temporary" "$file"
    return 0
  fi
  local sudo="${AUR_VET_SUDO:-sudo}"
  temporary="$(mktemp)"
  cat > "$temporary"
  if ! command -v "$sudo" >/dev/null 2>&1 \
     || ! "$sudo" install -m0644 "$temporary" "$file"; then
    command rm -f "$temporary"
    die "allowlist not writable: ${file} (needs sudo)"
  fi
  command rm -f "$temporary"
}

# allow_add <row>… — append the rows to the allowlist.
allow_add() {
  local allowlist
  allowlist="$(store_directory)/allow.tsv"
  { cat "$allowlist" 2>/dev/null || true; printf '%s\n' "$@"; } \
    | store_put "$allowlist"
}

# One answer to a suspicious finding: n (abort), y (once) or a (always).
choose() {
  local answer
  printf 'aur-vet: %s [n/y/a] ' "$1" >&2
  read -r answer || answer=n
  answer="$(printf '%s\n' "$answer" | tr '[:upper:]' '[:lower:]')"
  case "$answer" in
    y | yes) printf y ;;
    a | always) printf a ;;
    *) printf n ;;
  esac
}

ask() {
  local answer
  printf 'aur-vet: %s [y/N] ' "$1" >&2
  read -r answer || return 1
  [[ "$answer" == [yY] || "$answer" == [yY][eE][sS] ]]
}

# ── export ──────────────────────────────────────────────────────────────────
# Merge the booted allowlist back into the repo copy (default: the dotfiles
# checkout) for the operator to commit: rows union on pkgbase + rule, repo
# comments stay. `--check` only reports drift (exit 1).
export_allowlist() {
  local check=0
  [[ "${1:-}" == --check ]] && { check=1; shift; }
  local repo="${1:-$HOME/.dotfiles/.installer/aur}"
  local store="${AUR_VET_STORE:-/etc/aur-vet}" merged changes
  [[ -f "$repo/allow.tsv" ]] || die "export: no allowlist at ${repo}"
  if [[ ! -r "$store/allow.tsv" ]]; then
    say "export: no allowlist at ${store} — nothing to export"
    return 0
  fi
  merged="$(export_merge "$store/allow.tsv" "$repo/allow.tsv")"
  changes="$(allowlist_changes "$repo/allow.tsv" "$merged")"
  # --check is two-way: a repo row the store lacks is drift too.
  local stale=""
  ((check)) && stale="$(export_stale "$store/allow.tsv" "$repo/allow.tsv")"
  [[ -n "$stale" ]] && printf 'only in the repo:\n%s\n' "$stale"
  if [[ -z "$changes" && -z "$stale" ]]; then
    if ((check)); then say "export: ${store} and ${repo} in sync"
    else say "export: nothing to export"; fi
    return 0
  fi
  [[ -n "$changes" ]] && printf 'allow.tsv:\n%s\n' "$changes"
  if ((check)); then
    say "export: drift between ${store} and ${repo}"
    return 1
  fi
  printf '%s\n' "$merged" > "$repo/allow.tsv"
  say "export: updated ${repo} — review the diff, then commit"
}

# allowlist_changes <file> <text> — what <text> adds ("+ row") and drops
# ("- row") against <file>.
allowlist_changes() {
  local line
  while IFS= read -r line; do
    case "$line" in
      "> "*) printf '+ %s\n' "${line:2}" ;;
      "< "*) printf -- '- %s\n' "${line:2}" ;;
    esac
  done < <(diff "$1" <(printf '%s\n' "$2"))
  return 0
}

# row_key <row> — "<pkgbase>\037<rule>": the row's first two tab-separated
# fields (the rule is empty when the row has no tab).
row_key() {
  local base rule=""
  base="$(printf '%s\n' "$1" | cut -f1)"
  [[ "$1" == *$'\t'* ]] && rule="$(printf '%s\n' "$1" | cut -f2)"
  printf '%s\037%s\n' "$base" "$rule"
}

# is_row <line> — rc 0 for an allowlist row (not a comment or blank line).
is_row() { [[ -n "$1" && "$1" != "#"* ]]; }

# <store-file> <repo-file> → repo rows (pkgbase + rule) the store lacks.
export_stale() {
  local line key base rule
  local -A stored=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    is_row "$line" && stored["$(row_key "$line")"]=1
  done < "$1"
  while IFS= read -r line || [[ -n "$line" ]]; do
    is_row "$line" || continue
    key="$(row_key "$line")"
    [[ -n "${stored[$key]:-}" ]] && continue
    IFS=$'\037' read -r base rule < <(printf '%s\n' "$key")
    printf '  %s %s\n' "$base" "$rule"
  done < "$2"
  return 0
}

# <store-file> <repo-file> → the merged repo allowlist on stdout: the repo's
# lines in order, a row the store also has taken from the store, then the
# store's other rows.
export_merge() {
  local line key
  local -A store_row=() written=()
  local -a order=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    is_row "$line" || continue
    key="$(row_key "$line")"
    [[ -n "${store_row[$key]+set}" ]] || order+=("$key")
    store_row[$key]="$line"
  done < "$1"
  while IFS= read -r line || [[ -n "$line" ]]; do
    key=""
    is_row "$line" && key="$(row_key "$line")"
    if [[ -n "$key" && -n "${store_row[$key]+set}" ]]; then
      printf '%s\n' "${store_row[$key]}"
      written[$key]=1
    else
      printf '%s\n' "$line"
    fi
  done < "$2"
  for key in "${order[@]}"; do
    [[ -n "${written[$key]:-}" ]] || printf '%s\n' "${store_row[$key]}"
  done
  return 0
}
