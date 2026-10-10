# pacman-options.awk — rewrite pacman.conf's managed `[options]` directives
# (ADR 0074). Each flag's on/off comes from the PAC_* environment that
# pacman_config_apply_options (lib/packages/pacman-config.sh) sets:
# PAC_COLOR, PAC_VERBOSE, PAC_TIMEOUT, PAC_NOPROGRESS, PAC_CANDY ("on"/"off")
# and PAC_PARALLEL (ParallelDownloads value, "" leaves it alone). Every other
# line passes through verbatim.

BEGIN {
  want["Color"]         = ENVIRON["PAC_COLOR"]
  want["VerbosePkgLists"]        = ENVIRON["PAC_VERBOSE"]
  want["DisableDownloadTimeout"] = ENVIRON["PAC_TIMEOUT"]
  want["NoProgressBar"]          = ENVIRON["PAC_NOPROGRESS"]
  want["ILoveCandy"]             = ENVIRON["PAC_CANDY"]
  parallel = ENVIRON["PAC_PARALLEL"]
  names = "Color VerbosePkgLists DisableDownloadTimeout"
  names = names " NoProgressBar ILoveCandy"
  n = split(names, order, " ")
}
# Which managed directive (if any) a line carries, comment or not.
function directive(line,   l, i) {
  l = line
  sub(/^[#[:space:]]+/, "", l)
  for (i = 1; i <= n; i++)
    if (l ~ ("^" order[i] "[[:space:]]*$")) return order[i]
  if (l ~ /^ParallelDownloads([[:space:]]|=)/) return "ParallelDownloads"
  return ""
}
# Emit the managed on-flags / ParallelDownloads not yet seen, at the end of
# the [options] block (called before the next section header or at EOF).
function flush(   i, nm) {
  if (flushed) return
  for (i = 1; i <= n; i++) {
    nm = order[i]
    if (!seen[nm] && want[nm] == "on") print nm
  }
  if (parallel != "" && !seen["ParallelDownloads"])
    print "ParallelDownloads = " parallel
  flushed = 1
}
/^[[:space:]]*\[/ {
  if (in_options) flush()
  in_options = ($0 ~ /^\[options\][[:space:]]*$/)
  print; next
}
{
  if (in_options) {
    d = directive($0)
    if (d != "") {
      seen[d] = 1
      if (d == "ParallelDownloads") {
        if (parallel != "") print "ParallelDownloads = " parallel
        else print
        next
      }
      if (want[d] == "on") print d
      else if ($0 ~ /^[[:space:]]*#/) print   # already off — keep verbatim
      else print "#" d
      next
    }
  }
  print
}
END { if (in_options) flush() }
