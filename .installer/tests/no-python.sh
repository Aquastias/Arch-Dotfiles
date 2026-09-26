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
  is_self "${hit%%:*}" && continue
  emit "Python shebang: $hit"
done < <(git grep -I -nE '^#!.*python' -- ':!*.md' || true)

# ── 3. python invocation in shell scripts ───────────────────────────────────
# Shell scripts = repo tooling that could run python inline: *.sh/*.bash/*.bats
# plus any tracked file with a sh/bash shebang (git hooks, PATH commands).
inv='(^|[^[:alnum:]_-])(python[23]?|pip[23]?|pipx|poetry|pyenv|uv)([[:space:]]|$)'
while IFS= read -r f; do
  [[ -n "$f" ]] || continue
  is_self "$f" && continue
  # Blank pragma lines (keep numbering), strip comments, then match invocations.
  while IFS= read -r hit; do
    [[ -n "$hit" ]] && emit "Python invocation: $f:$hit"
  done < <(
    awk '/no-python-ok/{print ""; next} {print}' "$f" \
      | sed 's/[[:space:]]#.*$//; s/^[[:space:]]*#.*$//' \
      | grep -nE "$inv" || true
  )
done < <(
  {
    git ls-files '*.sh' '*.bash' '*.bats'
    git grep -I -lE '^#!.*(bash|[[:space:]/]sh)([[:space:]]|$)' -- ':!*.md' \
      || true
  } | sort -u
)

exit "$fail"
