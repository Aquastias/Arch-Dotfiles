# explain-wrap.awk — the input words (one per line) packed into lines of at
# most `width` columns, each indented six spaces; no trailing newline.
# Variable: width.

# A word that would overflow the line: print the line, start a new one.
line != "" && length(line) + length($0) + 1 > width {
  sub(/[[:space:]]+$/, "", line); printf "%s      %s", separator, line
  separator = "\n"; line = ""
}

# Add the word to the line.
{ line = line $0 " " }

# Print the last line.
END {
  sub(/[[:space:]]+$/, "", line); printf "%s      %s", separator, line
}
