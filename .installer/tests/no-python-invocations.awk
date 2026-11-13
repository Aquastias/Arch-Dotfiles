# no-python-invocations.awk — the code lines of a shell file that invoke a
# Python tool, as "<line-number>:<code>". A line carrying a `no-python-ok`
# pragma is skipped; comments are stripped first. The pattern comes in
# ENVIRON["INV"] (an ERE).

# A pragma line: never a finding.
/no-python-ok/ { next }

# Strip a trailing comment and comment-only lines, then report a match.
{
  sub(/[[:space:]]#.*$/, ""); sub(/^[[:space:]]*#.*$/, "")
  if ($0 ~ ENVIRON["INV"]) print NR ":" $0
}
