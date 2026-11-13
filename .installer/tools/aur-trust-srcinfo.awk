# aur-trust-srcinfo.awk — the .SRCINFO lines that decide what is built and
# run (sources, checksums, install and changelog scripts, per-arch variants
# too), leading whitespace dropped.

# A source/sums/install/changelog line, optionally _<arch>-suffixed.
$0 ~ "^[[:space:]]*(source|[a-z0-9]+sums|install|changelog)(_[a-z0-9_]+)? = " {
  sub(/^[[:space:]]+/, ""); print
}
