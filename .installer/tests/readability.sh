#!/usr/bin/env bash
# readability.sh — the Readability Lint (ADR 0153; rules in
# docs/agents/readability.md). Scans TRACKED installer shell files (*.sh,
# *.bash, *.bats under .installer/, minus program home/ payloads) and reports
# each violation as `rule: file:line: detail`.
#
# Strict: any violation fails. (The Readability Baseline ratchet that eased
# the lint in reached zero and was retired with ADR 0153's last ticket.)
#
# Docs: every `ADR NNNN` in tracked Markdown (minus .scratch/, vendored
# .agents/skills/, program payloads) must be a link (readability-adr-links.awk).
#
# Usage: readability.sh [--list | --fix-adr-links]
#   (none)            fail on any violation
#   --list            print every violation, never fail
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

PREFIX_RULES=".installer/tests/readability-prefixes.txt"
[[ -f "$PREFIX_RULES" ]] || PREFIX_RULES=""

mode="check"
case "${1:-}" in
  --list) mode="list" ;;
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
  if ((${#files[@]})); then
    awk -v prefix_rules="$PREFIX_RULES" -f "$SCANNER" "${files[@]}"
  fi
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
esac

report="$(violations \
  | awk -F'\t' '{ printf "%s: %s:%s: %s\n", $1, $2, $3, $5 }')"
[[ -z "$report" ]] && exit 0
printf "%s\n" "$report" | sort | awk '{ print "readability: " $0 }' >&2
exit 1
