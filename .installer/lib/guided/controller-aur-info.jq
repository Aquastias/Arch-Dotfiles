# controller-aur-info.jq — the AUR browser's preview text for one package, from
# the AUR RPC v5 info response (ADR 0086). Prints nothing when the response
# names no package.

# The first (only) result.
.results[0] // empty

# One "Label: value" line per detail; the out-of-date line only when flagged.
| "Name:        \(.Name)",
  "Version:     \(.Version)",
  "Description: \(.Description // "-")",
  "Maintainer:  \(.Maintainer // "(orphaned)")",
  "Votes:       \(.NumVotes)   Popularity: \(.Popularity)",
  (if .OutOfDate then "⚠ OUT OF DATE" else empty end),
  "URL:         \(.URL // "-")",
  "AUR:         https://aur.archlinux.org/packages/\(.Name)"
