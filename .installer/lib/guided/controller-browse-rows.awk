# controller-browse-rows.awk — the package browser's toggle rows (ADR 0086).
#
# Input: one package name per line (the slot's whole package list).
# Variables (-v), each a newline-separated name list:
#   base   the baseline's packages in the slot
#   extra  the packages this session added to the slot
#   excl   the excluded packages
#   deriv  the packages another choice already pulls in
# Output: one "[x] name" / "[ ] name" row per package; "  ●" flags a row this
# session touched, "  ⟲ derived" a derived (read-only) one.

# Turn each name list into a set: name → 1.
BEGIN {
  count = split(base, names, "\n")
  for (i = 1; i <= count; i++) if (names[i] != "") in_base[names[i]] = 1
  count = split(extra, names, "\n")
  for (i = 1; i <= count; i++) if (names[i] != "") in_extra[names[i]] = 1
  count = split(excl, names, "\n")
  for (i = 1; i <= count; i++) if (names[i] != "") in_excl[names[i]] = 1
  count = split(deriv, names, "\n")
  for (i = 1; i <= count; i++) if (names[i] != "") in_deriv[names[i]] = 1
}

# One row per package, the first matching set deciding its mark.
{
  if ($0 in in_excl)       print "[ ] " $0 "  ●"           # excluded here
  else if ($0 in in_base)  print "[x] " $0                 # from the baseline
  else if ($0 in in_extra) print "[x] " $0 "  ●"           # added here
  else if ($0 in in_deriv) print "[x] " $0 "  ⟲ derived"   # pulled in
  else                     print "[ ] " $0                 # available
}
