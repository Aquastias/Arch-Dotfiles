# =============================================================================
# bump-only.awk — is a Vetted-Commit diff a pure version bump? (ADR 0143)
# =============================================================================
# Input: `git diff -U0 <pin> <head> -- PKGBUILD .SRCINFO`. Exit 0 when every
# changed line is a pkgver/pkgrel/epoch or checksum assignment, a bare
# checksum, or a source line equal to its old self with the old pkgver
# swapped for the new; else 1. Such a diff can't add logic, so it is
# auto-accepted.
# =============================================================================
/^(diff |index |@@|\+\+\+ |--- )/ { next }
!/^[+-]/ { next }
{
  l = substr($0, 2); sign = substr($0, 1, 1)
  if (l ~ /^[[:space:]]*pkgver[[:space:]]*=/) {
    v = l; sub(/^[^=]*=[[:space:]]*/, "", v); gsub(/["'[:space:]]/, "", v)
    if (sign == "-") ov = v; else nv = v
    next
  }
  if (l ~ /^[[:space:]]*(pkgrel|epoch)[[:space:]]*=/) next
  # sha256sums=('…' 'SKIP') / .SRCINFO `sha256sums = …`: sums only, no code.
  if (l ~ /^[[:space:]]*[[:alnum:]]+sums(_[[:alnum:]_]+)?[[:space:]]*[+]?=\
[[:space:]]*[(]?([[:space:]]*["']?([0-9a-fA-F]+|SKIP)["']?)*[[:space:]]*\
[)]?[[:space:]]*$/) next
  # A continuation line of a multi-line sums array.
  if (l ~ /^[[:space:]]*["']?([0-9a-fA-F]{32,}|SKIP)["']?[)]?[[:space:]]*$/)
    next
  if (l ~ /^[[:space:]]*source(_[[:alnum:]_]+)?[[:space:]]*=/) {
    if (sign == "-") om[++no] = l; else pm[++np] = l
    next
  }
  bad = 1
}
function swap(s, a, b,   i, r) {
  r = ""
  while (a != "" && (i = index(s, a)) > 0) {
    r = r substr(s, 1, i - 1) b; s = substr(s, i + length(a))
  }
  return r s
}
END {
  if (bad || no != np) exit 1
  for (k = 1; k <= no; k++) if (swap(om[k], ov, nv) != pm[k]) exit 1
}
