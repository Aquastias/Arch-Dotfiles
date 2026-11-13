# binds-zsh.awk — zsh keybind parser (ADR 0152): explicit
# `bindkey [-M map] <seq> <widget>` lines (a bare `bindkey -e/-v` keymap
# switch is not a bind). Rows: `zsh<TAB><seq><TAB><map> <widget>`.

# Drop a trailing comment.
{ sub(/[ \t]+#.*$/, "") }

# A bindkey line: its keymap (main unless -M), sequence and widget.
/^[ \t]*bindkey[ \t]/ {
  m = "main"; i = 2
  if ($2 == "-M") { m = $3; i = 4 }
  if ($i ~ /^-/ || NF < i + 1) next
  s = $i; gsub(/^[\x27"]|[\x27"]$/, "", s)
  printf "zsh\t%s\t%s %s\n", s, m, $(i + 1)
}
