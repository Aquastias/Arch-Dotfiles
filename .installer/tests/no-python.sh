#!/usr/bin/env bash
# no-python.sh — fail if any Python enters the repo (policy: docs/agents/
# no-python.md). Three mechanical checks on TRACKED files only (git ls-files ==
# "in the repo"; the gitignored vendored bats-core tree is not):
#   1. no committed *.py file, anywhere;
#   2. no python-family shebang in any tracked non-doc file;
#   3. no python/pip/pipx/poetry/pyenv/uv INVOCATION in a shell script.
# It keys on what EXECUTES python (extension, shebang, command), never on
# syntax: jq's `def f($x): … end;` in picker.sh reads like Python but is data
# to the jq binary, so it must pass. Untouched: python package NAMES in
# profiles, editor/prompt config, and prose/comments naming python (incl. this
# file and the policy docs — check 3 strips comments and skips *.md/self).
# Escape hatch: a line containing `no-python-ok` is exempt from check 3.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$(git rev-parse --show-toplevel)"

fail=0
emit() { fail=1; printf 'no-python: %s\n' "$1" >&2; }

# The check's own files carry the banned patterns as data — never scan them.
self=".installer/tests/no-python.sh .installer/tests/no-python.bats"
is_self() { case " $self " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

# ── 1. committed .py files ───────────────────────────────────────────────────
while IFS= read -r f; do
  [[ -n "$f" ]] && emit "committed Python file: $f"
done < <(git ls-files '*.py')

# ── 2. python-family shebang (any tracked non-doc, non-self file) ────────────
while IFS= read -r hit; do
  [[ -n "$hit" ]] || continue
  # The file before the first ":".
  is_self "$(printf '%s\n' "$hit" | cut -d: -f1)" && continue
  emit "Python shebang: $hit"
done < <(git grep -I -n -E '^#!.*python' -- ':!*.md' || true)

# ── 3. python invocation in shell scripts ───────────────────────────────────
# Shell scripts = repo tooling that could run python inline: *.sh/*.bash/*.bats
# plus any tracked file with a sh/bash shebang (git hooks, PATH commands).
inv='(^|[^[:alnum:]_-])(python[23]?|pip[23]?|pipx|poetry|pyenv|uv)([[:space:]]|$)'
while IFS= read -r f; do
  [[ -n "$f" ]] || continue
  is_self "$f" && continue
  while IFS= read -r hit; do
    [[ -n "$hit" ]] && emit "Python invocation: $f:$hit"
  # The file's code lines that invoke Python, numbered.
  done < <(INV="$inv" awk -f "$here/no-python-invocations.awk" "$f")
done < <(
  {
    git ls-files '*.sh' '*.bash' '*.bats'
    git grep -I -l -E '^#!.*(bash|[[:space:]/]sh)([[:space:]]|$)' -- ':!*.md' \
      || true
  } | sort -u
)

exit "$fail"
