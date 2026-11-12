# tests/lib/language-registry.awk — read the Language Registry (ADR 0141)
# out of nvim's languages.lua without a Lua runtime. -v part= picks what to
# print:
#   keys        each language key, one per line
#   formatters  "<filetype> <formatter>" for each filetype a language
#               formats (the language's first formatter)
# Used by: tests/config/vscodium-program.bats, emacs-program-helpers.bash.

# The registry table starts at `local registry = {` …
/^local registry = \{/ { inside = 1; next }

# … and ends at the first `}` in column one.
inside && /^}/ { exit }

# A language entry starts at a two-space-indented `<key> = `.
inside && match($0, /^  [a-z_]+ = /) {
  key = substr($0, 3)
  sub(/ = .*/, "", key)
  if (part == "keys") print key
  filetypes = ""
  formatters = ""
}

# Its `ft = { … }` list (the filetypes it covers).
part == "formatters" && inside && /ft = \{/ {
  list = $0
  sub(/.*ft = \{/, "", list)
  sub(/\}.*/, "", list)
  filetypes = list
}

# Its `formatter = { … }` list.
part == "formatters" && inside && /formatter = \{/ {
  list = $0
  sub(/.*formatter = \{/, "", list)
  sub(/\}.*/, "", list)
  formatters = list
}

# Both lists seen: one line per filetype, with the first formatter.
part == "formatters" && inside && filetypes != "" && formatters != "" {
  gsub(/[" ]/, "", filetypes)
  gsub(/[" ]/, "", formatters)
  count = split(filetypes, filetype, ",")
  split(formatters, formatter, ",")
  for (n = 1; n <= count; n++)
    if (filetype[n] != "") print filetype[n], formatter[1]
  filetypes = ""
  formatters = ""
}
