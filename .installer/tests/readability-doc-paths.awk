# readability-doc-paths.awk — the `doc-path` rule of the Readability Lint
# (ADR 0156). Every backticked repo path in a doc must name a tracked file, so
# a doc cannot keep pointing an agent at a renamed or deleted file.
#
# Input: the tracked file list (`git ls-files`) first, then the docs.
# Output: TSV `doc-path  file  line  path  detail`, like the other rules.
#
# A path counts when it holds a `/` and ends in a repo file extension. It
# resolves when it is a tracked path or the tail of one (`vm/lib/core.sh`
# names `.installer/vm/lib/core.sh`); leading `./` / `../` are dropped.
# Target-system paths (`/usr/…`, `~/…`) and placeholders (`<name>`, `*`) are
# skipped. Name a removed file without backticks.

FNR == NR {
  tracked[$0] = 1
  tracked_count++
  tracked_paths[tracked_count] = $0
  next
}

{
  rest = $0
  while (match(rest, /`[^` ]+`/)) {
    path = substr(rest, RSTART + 1, RLENGTH - 2)
    rest = substr(rest, RSTART + RLENGTH)
    if (is_repo_path(path) && !resolves(path)) {
      printf "doc-path\t%s\t%d\t%s\t%s is not a tracked file\n", \
        FILENAME, FNR, path, path
    }
  }
}

function is_repo_path(path) {
  if (path !~ /\//) return 0
  if (path !~ /\.(sh|bash|bats|awk|md|json|jsonc|txt)$/) return 0
  if (path ~ /^[\/~$]/) return 0
  return path !~ /[<>*{}$|:]/
}

function resolves(path,    reference, suffix, i, candidate) {
  reference = path
  sub(/^(\.\.?\/)+/, "", reference)
  if (reference in tracked) return 1
  suffix = "/" reference
  for (i = 1; i <= tracked_count; i++) {
    candidate = tracked_paths[i]
    if (substr(candidate, length(candidate) - length(suffix) + 1) == suffix)
      return 1
  }
  return 0
}
