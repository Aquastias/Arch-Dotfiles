# binds-kitty.awk — kitty keybind parser (ADR 0152): `map <keys> <action>`
# lines. kitty_mod is ctrl+shift (kitty's default; the curated config does not
# rebind it). Rows: `kitty<TAB><Keys><TAB><action>`, modifiers capitalised.

# A map line: its keys (modifiers capitalised) and the rest as the action.
/^[ \t]*map[ \t]/ {
  k = $2; sub(/^[ \t]*map[ \t]+[^ \t]+[ \t]+/, "")
  gsub(/kitty_mod/, "ctrl+shift", k)
  n = split(k, p, "+"); o = ""
  for (i = 1; i <= n; i++) {
    t = p[i]
    if (t == "ctrl") t = "Ctrl"; else if (t == "shift") t = "Shift"
    else if (t == "alt") t = "Alt"; else if (t == "super") t = "Super"
    o = o (o == "" ? "" : "+") t
  }
  printf "kitty\t%s\t%s\n", o, $0
}
