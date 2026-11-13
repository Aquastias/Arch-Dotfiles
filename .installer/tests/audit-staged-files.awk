# audit-staged-files.awk — the quoted entries of runner.sh's
# `_STAGED_RUNTIME_FILES=( … )` array, one per line.

# Inside the array: each line's quoted text (lines without a quote skipped).
/_STAGED_RUNTIME_FILES=\(/, /^\)/ {
  if (!/"/) next
  sub(/"[^"]*$/, ""); sub(/.*"/, ""); print
}
