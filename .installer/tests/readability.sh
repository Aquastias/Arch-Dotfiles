#!/usr/bin/env bash
# readability.sh — the Readability Lint (ADR 0153, ADR 0167; rules in
# docs/agents/readability.md). Scans TRACKED shell files and reports each
# violation as `rule: file:line: detail`.
#
# Scanned: shell under .installer/ (minus program home/ payloads), the
# user scripts in .local/bin, and every other tracked *.sh outside
# .scratch/ and vendored .agents/skills/.
#
# Strict and advisory findings. ADR 0153's rules are strict inside
# .installer/. ADR 0167's rules (and any finding outside .installer/) are
# advisory — shown by --list, never failing — until the file's area is in
# the Migrated Areas list (readability-migrated.txt).
#
# Commands and flags are checked against the Tool Reference
# (docs/tool-reference.md): it is the allowlist.
#
# Docs: every `ADR NNNN` in tracked Markdown (minus .scratch/, vendored
# .agents/skills/, program payloads) must be a link (readability-adr-links.awk),
# and every backticked repo path in them (ADRs aside) must be a tracked file
# (readability-doc-paths.awk, ADR 0156).
#
# Usage: readability.sh [--list | --fix-adr-links]
#   (none)            fail on any strict violation
#   --list            print every violation, strict and advisory, never fail
#   --fix-adr-links   link every ADR mention in the docs, in place
# Escape hatch: a line containing `readability-ok` is exempt (on a function's
# opening line it exempts the whole-function rules too).
set -euo pipefail

script_path="${BASH_SOURCE[0]}"
[[ "$script_path" == */* ]] || script_path="./$script_path"
TESTS_DIR="$(cd "${script_path%/*}" && pwd)"
SCANNER="$TESTS_DIR/readability-scan.awk"
COMMAND_CHECKER="$TESTS_DIR/readability-commands.awk"
FEATURE_CHECKER="$TESTS_DIR/readability-features.awk"
PROGRAM_FILE_CHECKER="$TESTS_DIR/readability-program-files.awk"
ADR_LINKER="$TESTS_DIR/readability-adr-links.awk"
DOC_PATH_CHECKER="$TESTS_DIR/readability-doc-paths.awk"

cd "$(git rev-parse --show-toplevel)"

PREFIX_RULES=".installer/tests/readability-prefixes.txt"
[[ -f "$PREFIX_RULES" ]] || PREFIX_RULES=""
MIGRATED_AREAS=".installer/tests/readability-migrated.txt"
[[ -f "$MIGRATED_AREAS" ]] || MIGRATED_AREAS=""
TOOL_REFERENCE="docs/tool-reference.md"
[[ -f "$TOOL_REFERENCE" ]] || TOOL_REFERENCE=""

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

# Never scanned: program home/ payloads (app config), test fixtures
# (sample data), and the lint's own files (they hold the banned patterns
# as data).
NOT_SCANNED='^\.installer/(programs/[^/]+/[^/]+/home/|tests/fixtures/'
NOT_SCANNED+='|tests/readability(\.sh|\.bats|-.*\.awk)$)'
# Other tracked files: .installer/ is listed on its own; notes and
# vendored skills are not ours to lint.
NOT_OURS='^(\.installer/|\.scratch/|\.agents/skills/)'

scanned_files() {
  local installer_files other_files
  installer_files="$(git ls-files '.installer/*.sh' '.installer/*.bash' \
    '.installer/*.bats' '.installer/*.jq' '.installer/*.awk')"
  other_files="$(git ls-files '*.sh' '.local/bin/*' \
    | grep -vE "$NOT_OURS" || true)"
  printf '%s\n' "$installer_files" "$other_files" \
    | grep -vE "$NOT_SCANNED|^$" || true
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

# Violations as TSV: rule, file, line, symbol, detail, strictness. Doc
# rows have no strictness column: they are always strict.
violations() {
  local files
  mapfile -t files < <(scanned_files)
  if ((${#files[@]})); then
    awk -v prefix_rules="$PREFIX_RULES" \
      -v migrated_areas="$MIGRATED_AREAS" \
      -v tool_reference="$TOOL_REFERENCE" \
      -f "$PROGRAM_FILE_CHECKER" -f "$SCANNER" -f "$COMMAND_CHECKER" \
      -f "$FEATURE_CHECKER" "${files[@]}"
  fi
  mapfile -t files < <(linked_docs)
  ((${#files[@]})) || return 0
  awk -v mode=check -v adr_index="$(adr_index)" -f "$ADR_LINKER" \
    "${files[@]}"
  # ADRs are history: they keep naming files that later moved.
  mapfile -t files < <(linked_docs | grep -v '^docs/adr/' || true)
  ((${#files[@]})) || return 0
  awk -f "$DOC_PATH_CHECKER" <(git ls-files) "${files[@]}"
}

# print_findings — read TSV violations on stdin, print each as
# `rule: file:line: detail`.
print_findings() {
  local rule file line _symbol detail _strictness
  while IFS=$'\t' read -r rule file line _symbol detail _strictness; do
    printf '%s: %s:%s: %s\n' "$rule" "$file" "$line" "$detail"
  done
}

case "$mode" in
  list)
    violations | print_findings
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

# Only strict violations fail the lint.
strict_rows="$(violations | grep -v $'\tadvisory$' || true)"
[[ -z "$strict_rows" ]] && exit 0
mapfile -t findings < <(printf '%s\n' "$strict_rows" | print_findings | sort)
for finding in "${findings[@]}"; do
  printf 'readability: %s\n' "$finding" >&2
done
exit 1
