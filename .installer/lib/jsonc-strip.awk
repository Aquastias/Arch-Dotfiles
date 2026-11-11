# jsonc-strip.awk — JSONC to plain JSON: drops `//` comments.
# Used by: lib/jsonc.sh (jsonc_strip).
#
# A trailing comment is cut only when no `"` follows the `//`, so a URL
# inside a string ("https://…") survives.

# Cut a trailing comment: a bare `//` at the end, or ` // text` with no
# quote in the text.
{
  sub(/[[:space:]]*\/\/$/, "")
  sub(/[[:space:]]\/\/[^"]*$/, "")
}

# Skip a line that is only a comment.
/^[[:space:]]*\/\// { next }

# Print everything else unchanged.
{ print }
