# audit-strip-jsonc.awk — a JSONC file as plain JSON: a trailing `// …`
# comment (one with no quote after it) dropped, whole-line comments dropped.

# Drop a trailing comment.
{ sub(/[[:space:]]*\/\/[^"]*$/, "") }

# Print every line that is not a comment line.
!/^[[:space:]]*\/\// { print }
