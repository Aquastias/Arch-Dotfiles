#!/usr/bin/env bash
# raw-config-reads.sh — the Raw Config Read Lint (install-config-reader/03).
# An Effective Config field is read through the Install Config Reader — bound
# to JSON (install_config_use_json) where the module holds JSON — never as a
# raw `.<config path> // <default>` jq read that re-declares its Install
# Default. Scans TRACKED installer code (top-level scripts, lib/, vm/, tools/),
# minus the reader itself.
#
# Ratchet: today's raw reads are counted per file in
# raw-config-reads-baseline.txt (`file<TAB>count`). More reads than the
# baseline fails (a new raw read); fewer fails too (stale baseline: lower it
# with --update), so the baseline only ever shrinks to zero.
#
# Usage: raw-config-reads.sh [--list | --update]
#   (none)     fail on a new raw read or a stale baseline
#   --list     print every raw read as `file:line: text`, never fail
#   --update   rewrite the baseline to today's counts
# Escape hatch: a line containing `raw-config-ok` is not a raw config read
# (e.g. the same keys on a Host Profile before assembly).
set -euo pipefail

BASELINE=".installer/tests/raw-config-reads-baseline.txt"

# The Effective Config's top-level keys a raw read starts from, then any
# `.key` / `[i]` steps, then `//` and a literal default (string, number,
# bool). `// empty`, `// null`, `// []`, `// {}` only coalesce — not defaults.
RAW_READ='\.(options|system|environment|post_install|disk_config|filesystem'
RAW_READ+='|data_pools|storage_groups|os_pool|os_pool_name|storage_pool_name'
RAW_READ+='|storage_mount|ashift|mode|users|host_programs|packages|persist'
RAW_READ+='|sysctl|dotfiles_repo|disk|disks)([.][A-Za-z_]+|\[[^]]*\])* *// *'
RAW_READ+='("|[0-9]|true|false)'

scanned_files() {
  git ls-files '.installer/*.sh' \
    | grep -E '^\.installer/([^/]+\.sh|(lib|vm|tools)/.+\.sh)$' \
    | grep -vE '^\.installer/lib/config/install-config[^/]*\.sh$' \
    || true
}

# Raw reads as `file<TAB>line<TAB>text`.
raw_reads() {
  local files
  mapfile -t files < <(scanned_files)
  ((${#files[@]})) || return 0
  PATTERN="$RAW_READ" awk '
    $0 ~ ENVIRON["PATTERN"] && $0 !~ /raw-config-ok/ {
      text = $0; sub(/^[[:space:]]+/, "", text)
      print FILENAME "\t" FNR "\t" text
    }' "${files[@]}"
}

# Per-file counts as `file<TAB>count`, sorted by file.
current_counts() {
  raw_reads | awk -F'\t' '{ count[$1]++ }
    END { for (file in count) print file "\t" count[file] }' | sort
}

# Compare today's counts with the baseline; print each mismatch, fail on any.
check_against_baseline() {
  local baseline_text=""
  [[ -f "$BASELINE" ]] && baseline_text="$(<"$BASELINE")"
  awk -F'\t' '
    NR == FNR { if ($1 != "") baseline[$1] = $2; next }
    { now[$1] = $2 }
    END {
      for (file in now) if (now[file] > baseline[file] + 0) {
        printf "%s: %d raw config read(s), baseline %d — read through" \
          " the Install Config Reader\n", file, now[file], baseline[file]
        failed = 1
      }
      for (file in baseline) if (now[file] + 0 < baseline[file]) {
        printf "stale baseline: %s: %d now, baseline %d — run" \
          " raw-config-reads.sh --update\n", file, now[file], baseline[file]
        failed = 1
      }
      exit failed
    }' <(printf '%s\n' "$baseline_text") <(current_counts)
}

main() {
  cd "$(git rev-parse --show-toplevel)"
  case "${1:-}" in
    --list) raw_reads | awk -F'\t' '{ print $1 ":" $2 ": " $3 }' ;;
    --update) current_counts > "$BASELINE" ;;
    "") check_against_baseline ;;
    *)
      echo "raw-config-reads: unknown option: $1" >&2
      exit 2
      ;;
  esac
}

main "$@"
