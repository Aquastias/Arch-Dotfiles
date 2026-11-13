# report-skips.awk — the "Skipped checks" markdown section: every SKIP line of
# the probe files, once, with the variants that skipped it (Probe Gate, ADR
# 0152). Variable: run, the run folder with a trailing slash. Prints nothing
# when no check was skipped.

# A SKIP line: remember the check (first-seen order) and this file's variant.
/^SKIP / {
  rel = substr(FILENAME, length(run) + 1); split(rel, p, "/")
  k = substr($0, 6)
  if (!(k in v)) { order[++n] = k; v[k] = "" }
  if (index("," v[k] ",", "," p[1] ",") == 0)
    v[k] = v[k] (v[k] == "" ? "" : ",") p[1]
}

# The section: one bullet per skipped check with its variants.
END {
  if (!n) exit
  print "\n## Skipped checks\n"
  print "Gated off by the variant (Probe Gate) or not provable here."
  print ""
  for (i = 1; i <= n; i++) printf "- %s [%s]\n", order[i], v[order[i]]
}
