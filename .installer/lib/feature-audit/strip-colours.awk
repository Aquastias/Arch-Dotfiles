# strip-colours.awk — the input without ANSI colour codes (ESC [ … m), so a
# Finding reads the same in a terminal and in a file.

# Drop every colour code from the line.
{ gsub(/\033\[[0-9;]*m/, ""); print }
