#!/usr/bin/env bash
# raw-config-reads.sh — the Raw Config Read Lint (install-config-reader/03).
# An Effective Config field is read through the Install Config Reader — bound
# to JSON (install_config_use_json) where the module holds JSON — never as a
# raw `.<schema path> // <literal>` jq read that restates its Install Default
# (only fields the schema owns — the rows of _INSTALL_CONFIG_SCHEMA). Scans
# TRACKED installer code (top-level scripts, lib/, vm/, tools/), minus the
# reader itself.
#
# Strict: any raw read fails. (The migration baseline that eased the lint in
# reached zero and was removed — install-config-reader/08.)
#
# Usage: raw-config-reads.sh [--list]
#   (none)     fail on any raw read
#   --list     print every raw read as `file:line: text`, never fail
# Escape hatch: a line containing `raw-config-ok` is not a raw config read
# (e.g. the same keys on a Host Profile before assembly).
set -euo pipefail

SCHEMA=".installer/lib/config/install-config.sh"

# The schema's jq paths, one per line: each `"name|path|type|default"` row of
# _INSTALL_CONFIG_SCHEMA (a row split as `"a|"\` + `"b"` is joined first).
schema_paths() {
  [[ -f "$SCHEMA" ]] || return 0
  awk '
    /^_INSTALL_CONFIG_SCHEMA=\(/ { inside = 1; next }
    inside && /^\)/ { exit }
    inside && /^[[:space:]]*#/ { next }
    inside && /"\\$/ { held = held $0; next }
    inside {
      row = held $0; held = ""
      gsub(/"\\[[:space:]]*"/, "", row)
      if (match(row, /"[^"]*"/)) {
        split(substr(row, RSTART + 1, RLENGTH - 2), field, "|")
        if (field[2] != "") print field[2]
      }
    }' "$SCHEMA"
}

# A raw read: a schema-owned path (from a jq input or a `$variable`, not a
# deeper path that merely ends the same), optional `[i]` steps, then `//` and
# a literal default (non-empty string or array, number, bool). `// ""`,
# `// empty`, `// null`, `// []`, `// {}` only coalesce — not defaults. A
# field the schema does not own has no Install Default to restate: never a
# raw read.
raw_read_pattern() {
  local paths
  paths="$(schema_paths | awk '{ gsub(/[.[\]]/, "\\\\&"); print }' \
    | awk 'NR > 1 { printf "|" } { printf "%s", $0 }')"
  [[ -n "$paths" ]] || return 0
  printf '%s' '(^|[^A-Za-z0-9_\]]|[$][A-Za-z_]+)('"$paths"')(\[[^]]*\])*'
  printf '%s' ' *// *("[^"]|\[[^]]|[0-9]|true|false)'
}

scanned_files() {
  git ls-files '.installer/*.sh' \
    | grep -E '^\.installer/([^/]+\.sh|(lib|vm|tools)/.+\.sh)$' \
    | grep -vE '^\.installer/lib/config/install-config[^/]*\.sh$' \
    || true
}

# Raw reads as `file<TAB>line<TAB>text`.
raw_reads() {
  local files pattern
  pattern="$(raw_read_pattern)"
  [[ -n "$pattern" ]] || return 0
  mapfile -t files < <(scanned_files)
  ((${#files[@]})) || return 0
  PATTERN="$pattern" awk '
    $0 ~ ENVIRON["PATTERN"] && $0 !~ /raw-config-ok/ {
      text = $0; sub(/^[[:space:]]+/, "", text)
      print FILENAME "\t" FNR "\t" text
    }' "${files[@]}"
}

# Every raw read as `file:line: text`, one per line.
listed_reads() { raw_reads | awk -F'\t' '{ print $1 ":" $2 ": " $3 }'; }

# Fail on any raw read, naming each one and the fix.
check_reads() {
  local reads
  reads="$(listed_reads)"
  [[ -z "$reads" ]] && return 0
  awk '{ print "raw config read: " $0 }' <<<"$reads"
  echo "Read these through the Install Config Reader" \
    "(docs/agents/readability.md, Config reads)."
  return 1
}

main() {
  cd "$(git rev-parse --show-toplevel)"
  case "${1:-}" in
    --list) listed_reads ;;
    "") check_reads ;;
    *)
      echo "raw-config-reads: unknown option: $1" >&2
      exit 2
      ;;
  esac
}

main "$@"
