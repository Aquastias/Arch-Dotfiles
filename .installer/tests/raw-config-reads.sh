#!/usr/bin/env bash
# raw-config-reads.sh — the Raw Config Read Lint (ADR 0154): a field the
# Install Config schema owns is read through the reader, never as a raw
# `.<schema path> // <literal>` jq read that restates its Install Default. Scans
# TRACKED installer code (top-level scripts, lib/, vm/, tools/, extras/,
# programs/ minus home/ payloads), minus the reader itself.
#
# Usage: raw-config-reads.sh [--list]
#   (none)     fail on any raw read
#   --list     print every raw read as `file:line: text`, never fail
# Escape hatch: a line containing `raw-config-ok` is not a raw config read
# (e.g. the same keys on a Host Profile before assembly).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCHEMA=".installer/lib/config/install-config.sh"

# A raw read: a schema-owned path (from a jq input or a `$variable`, not a
# deeper path that merely ends the same), optional `[i]` steps, then `//` and
# a literal default (non-empty string or array, number, bool). `// ""`,
# `// empty`, `// null`, `// []`, `// {}` only coalesce — not defaults. A
# field the schema does not own has no Install Default to restate: never a
# raw read.
raw_read_pattern() {
  local paths
  [[ -f "$SCHEMA" ]] || return 0
  # The schema's jq paths as ERE literals, joined by "|".
  paths="$(awk -v escape=1 -f "$HERE/raw-config-schema-paths.awk" "$SCHEMA" \
    | paste -sd'|')"
  [[ -n "$paths" ]] || return 0
  printf '%s' '(^|[^A-Za-z0-9_\]]|[$][A-Za-z_]+)('"$paths"')(\[[^]]*\])*'
  printf '%s' ' *// *("[^"]|\[[^]]|[0-9]|true|false)'
}

# Tracked installer scripts, minus home/ payloads and the reader itself.
scanned_files() {
  local directories='(lib|vm|tools|extras|programs)'
  local payloads='^\.installer/programs/[^/]+/[^/]+/home/'
  local reader='^\.installer/lib/config/install-config[^/]*\.sh$'
  local tracked
  tracked="$(git ls-files '.installer/*.sh')"
  # Top-level scripts and those under the scanned directories, minus
  # payloads and the reader.
  printf '%s\n' "$tracked" \
    | grep -E "^\\.installer/([^/]+\\.sh|$directories/.+\\.sh)\$" \
    | grep -vE "$payloads|$reader" \
    || true
}

# Every raw read as `file:line: text`, one per line.
listed_reads() {
  local files pattern
  pattern="$(raw_read_pattern)"
  [[ -n "$pattern" ]] || return 0
  mapfile -t files < <(scanned_files)
  ((${#files[@]})) || return 0
  PATTERN="$pattern" awk -f "$HERE/raw-config-match.awk" "${files[@]}"
}

# Fail on any raw read, naming each one and the fix.
check_reads() {
  local reads read
  reads="$(listed_reads)"
  [[ -z "$reads" ]] && return 0
  while IFS= read -r read; do
    echo "raw config read: $read"
  done < <(printf '%s\n' "$reads")
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
