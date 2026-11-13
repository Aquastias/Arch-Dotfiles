# raw-config-match.awk — each line of the input files matching the ERE in
# ENVIRON["PATTERN"], as `file:line: text` with leading blanks trimmed. A line
# carrying a `raw-config-ok` pragma is never a match.

# A raw read: print where it is and what it says.
$0 ~ ENVIRON["PATTERN"] && $0 !~ /raw-config-ok/ {
  text = $0; sub(/^[[:space:]]+/, "", text)
  print FILENAME ":" FNR ": " text
}
