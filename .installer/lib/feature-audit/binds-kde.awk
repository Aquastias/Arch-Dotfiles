# binds-kde.awk — KDE kglobalshortcutsrc parser (ADR 0152):
# `Action=Active\tAlt,Default,Label` per [component]. Rows:
# `kde<TAB><shortcut><TAB><component>/<action>`, one per active shortcut.

# A [component] header: remember it.
/^\[/ { g = substr($0, 2, length($0) - 2); next }

# The component's display name is no shortcut.
/^_k_friendly_name=/ { next }

# An action line: each of its active shortcuts (a `++` key is `+Plus`).
index($0, "=") {
  name = substr($0, 1, index($0, "=") - 1)
  a = substr($0, index($0, "=") + 1); sub(/,.*$/, "", a)
  if (a == "none" || a == "") next
  n = split(a, ks, /\\t/)
  for (i = 1; i <= n; i++) {
    k = ks[i]
    if (k ~ /\+\+$/) k = substr(k, 1, length(k) - 2) "+Plus"
    if (k != "" && k != "none") printf "kde\t%s\t%s/%s\n", k, g, name
  }
}
