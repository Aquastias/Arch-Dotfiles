#!/usr/bin/env bash
# readability.sh — the Readability Lint (ADR 0153; rules in
# docs/agents/readability.md). Scans TRACKED installer shell files (*.sh,
# *.bash, *.bats under .installer/, minus program home/ payloads) and reports
# each violation as `rule: file:line: detail`.
#
# A ratchet, not a wall: the Readability Baseline lists the violations that
# existed when the lint landed. A violation absent from the baseline fails; a
# baseline entry no longer violated fails too (delete it), so the baseline only
# shrinks. Baseline keys are `rule<TAB>file<TAB>symbol` — no line numbers, so
# unrelated edits never churn it; a key repeated N times allows N violations.
#
# Docs: every `ADR NNNN` in tracked Markdown (minus .scratch/, vendored
# .agents/skills/, program payloads) must be a link (readability-adr-links.awk).
#
# Usage: readability.sh [--list | --write-baseline | --fix-adr-links]
#   (none)            check against the baseline
#   --list            print every violation, ignore the baseline
#   --write-baseline  regenerate the baseline from the current tree
#   --fix-adr-links   link every ADR mention in the docs, in place
# Escape hatch: a line containing `readability-ok` is exempt (on a function's
# opening line it exempts the whole-function rules too).
set -euo pipefail

script_path="${BASH_SOURCE[0]}"
[[ "$script_path" == */* ]] || script_path="./$script_path"
TESTS_DIR="$(cd "${script_path%/*}" && pwd)"
SCANNER="$TESTS_DIR/readability-scan.awk"
ADR_LINKER="$TESTS_DIR/readability-adr-links.awk"

cd "$(git rev-parse --show-toplevel)"

BASELINE="${READABILITY_BASELINE:-.installer/tests/readability-baseline.txt}"

mode="check"
case "${1:-}" in
  --list) mode="list" ;;
  --write-baseline) mode="write" ;;
  --fix-adr-links) mode="fix-adr-links" ;;
  "") ;;
  *)
    echo "readability: unknown option: $1" >&2
    exit 2
    ;;
esac

# The lint's own files carry the banned patterns as data — never scan them.
scanned_files() {
  git ls-files '.installer/*.sh' '.installer/*.bash' '.installer/*.bats' \
    | grep -vE '^\.installer/programs/[^/]+/[^/]+/home/' \
    | grep -vE '^\.installer/tests/readability(\.sh|\.bats|-.*\.awk)$' \
    || true
}

linked_docs() {
  git ls-files '*.md' \
    | grep -vE '^(\.scratch/|\.agents/skills/)' \
    | grep -vE '^\.installer/programs/[^/]+/[^/]+/home/' \
    || true
}

# ADR file names, one per line (`0058-some-slug.md`).
adr_index() {
  local adr
  for adr in docs/adr/[0-9][0-9][0-9][0-9]-*.md; do
    [[ -e "$adr" ]] && printf '%s\n' "${adr##*/}"
  done
  return 0
}

# Violations as TSV: rule, file, line, symbol, detail.
violations() {
  local files
  mapfile -t files < <(scanned_files)
  if ((${#files[@]})); then awk -f "$SCANNER" "${files[@]}"; fi
  mapfile -t files < <(linked_docs)
  ((${#files[@]})) || return 0
  awk -v mode=check -v adr_index="$(adr_index)" -f "$ADR_LINKER" \
    "${files[@]}"
}

case "$mode" in
  list)
    violations | awk -F'\t' '{ printf "%s: %s:%s: %s\n", $1, $2, $3, $5 }'
    exit 0
    ;;
  fix-adr-links)
    index_text="$(adr_index)"
    while IFS= read -r doc; do
      # Rewrapping can join an `ADR` split across lines into a new
      # mention, so repeat until the doc stops changing.
      passes=0
      while ((passes++ < 3)); do
        awk -v mode=fix -v adr_index="$index_text" -f "$ADR_LINKER" \
          "$doc" > "$doc.linked"
        if cmp -s "$doc" "$doc.linked"; then
          rm "$doc.linked"
          break
        fi
        mv "$doc.linked" "$doc"
      done
    done < <(linked_docs)
    exit 0
    ;;
  write)
    violations | awk -F'\t' '{ print $1 "\t" $2 "\t" $4 }' | sort > "$BASELINE"
    exit 0
    ;;
esac

# Multiset difference: each baseline key absorbs one matching violation.
# Unabsorbed violations are new; unused baseline keys are stale.
status=0
report="$(
  violations | awk -F'\t' -v baseline="$BASELINE" '
    BEGIN {
      while ((getline row < baseline) > 0) {
        if (row != "") allowed[row]++
      }
    }
    {
      key = $1 "\t" $2 "\t" $4
      if (allowed[key] > 0) { allowed[key]--; next }
      printf "%s: %s:%s: %s\n", $1, $2, $3, $5
    }
    END {
      for (key in allowed) {
        for (count = allowed[key]; count > 0; count--) {
          split(key, part, "\t")
          printf "stale-baseline: %s %s %s (fixed - delete it)\n", \
            part[1], part[2], part[3]
        }
      }
    }
  '
)"
if [[ -n "$report" ]]; then
  printf "%s\n" "$report" | sort | awk '{ print "readability: " $0 }' >&2
  status=1
fi
exit "$status"
