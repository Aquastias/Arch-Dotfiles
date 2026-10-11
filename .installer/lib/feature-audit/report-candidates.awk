# report-candidates.awk — aggregate an Audit Run's artifacts into candidate
# Findings (lib/feature-audit/report.sh, _report_candidates). Inputs: the
# Known Noise TSV first (noisef=), then every *.log / *.lines / *.probe under
# <run>/<variant>/<phase>/. Variables: run (the run dir + "/"), phases (the
# phase order), error_regex (the error-shaped-word regex). Output, one line per
# Finding (TSV): phase-rank source program check phases variants count total
# excerpt logs.
function clean(s) {
  gsub(/\033\[[0-9;]*[A-Za-z]/, "", s); gsub(/\t/, " ", s)
  gsub(/\r/, "", s)
  # journal short-iso/short prefix: "Mon DD HH:MM:SS host "
  sub(/^[A-Z][a-z][a-z] [ 0-9][0-9] [0-9:][0-9:]+ [^ ]+ /, "", s)
  return s
}
# hexnorm: a run of 6+ hex chars holding a digit (mount ids, unit
# instance hashes) is volatile; a hex-only English word is not.
function hexnorm(s,   out, t) {
  out = ""
  while (match(s, /[0-9a-fA-F]{6,}/)) {
    t = substr(s, RSTART, RLENGTH)
    out = out substr(s, 1, RSTART - 1) (t ~ /[0-9]/ ? "H" : t)
    s = substr(s, RSTART + RLENGTH)
  }
  return out s
}
function norm(s) {
  s = hexnorm(s)
  gsub(/\[[0-9]+\]/, "[N]", s)
  gsub(/0x[0-9a-fA-F]+/, "0xN", s)
  gsub(/[0-9a-fA-F]{8}-[0-9a-fA-F-]{27}/, "UUID", s)
  gsub(/[0-9]+/, "N", s)
  return s
}
function noisy(line, src, ph,   i) {
  for (i = 1; i <= nn; i++)
    if ((ns[i] == "" || ns[i] == src) && (np[i] == "" || np[i] == ph) \
        && (nv[i] == "" || index("," nv[i] ",", "," var ",")) \
        && line ~ nr[i]) return 1
  return 0
}
function add(src, prog, chk, line, path,   k, u, g) {
  if (noisy(line, src, ph)) return
  k = src SUBSEP prog SUBSEP norm(chk " " line)
  if (!(k in ex)) { ex[k] = line; order[++nk] = k; ksrc[k] = src
                    kprog[k] = prog; kchk[k] = chk }
  u = var SUBSEP ph
  if (!((k, u) in seen)) { seen[k, u] = 1; cnt[k]++
    if (!((k, "v", var) in seen)) { seen[k, "v", var] = 1
      vars[k] = vars[k] (vars[k] == "" ? "" : ",") var }
    if (!((k, "p", ph) in seen)) { seen[k, "p", ph] = 1
      phs[k] = phs[k] (phs[k] == "" ? "" : ",") ph
      if (!(k in rank)) rank[k] = prank(ph) }
  }
  if (!((k, "l", path) in seen)) { seen[k, "l", path] = 1
    logs[k] = logs[k] (logs[k] == "" ? "" : ",") path }
}
function prank(p,   i) {
  for (i = 1; i <= np0; i++) if (pl[i] == p) return i
  sub(/-.*$/, "", p)   # per-desktop phases (sessions-kde) rank as sessions
  for (i = 1; i <= np0; i++) if (pl[i] == p) return i
  return 99
}
# flush — keep held attempt errors that no [RETRY] superseded
function flush(   i) {
  for (i = 1; i <= nh; i++) add(hsrc, hprog, "", hl[i], hr[i])
  nh = 0; inatt = 0
}
BEGIN { np0 = split(phases, pl, " ") }
FILENAME == noisef { nn++; nr[nn] = $1; ns[nn] = $2; np[nn] = $3
                    nv[nn] = $4; next }
FNR == 1 {
  flush()
  rel = substr(FILENAME, length(run) + 1)
  split(rel, parts, "/"); var = parts[1]; ph = parts[2]; base = parts[3]
  kind = base; sub(/^.*\./, "", kind)
  src = base; sub(/\.[^.]*$/, "", src); prog = ""
  if (src ~ /^probe-/) {
    prog = src; sub(/^probe-/, "", prog); sub(/@.*$/, "", prog)
    acct = src; sub(/^[^@]*@/, "", acct); sub(/\..*$/, "", acct)
    src = (src ~ /\.err$/) ? "probe-stderr" : "probe"
  }
  g = src SUBSEP prog
  if (!((g, var, ph) in units)) { units[g, var, ph] = 1; tot[g]++ }
}
{
  line = clean($0)
  if (line ~ /^[[:space:]]*$/) next
  # a whitespace-led line continues the previous journal entry (wrapped
  # text, stack frames): the entry is one Finding, keyed by its head
  if (kind == "lines" && $0 ~ /^[[:space:]]/) next
  if (kind == "log") {
    # _retry markers: hold the errors of an attempt; a [RETRY] (a later
    # attempt follows) drops them, any other end keeps them
    if (line ~ /^\[ATTEMPT\] /) { flush(); inatt = 1; next }
    if (line ~ /^\[RETRY\] /) { nh = 0; inatt = 0; next }
    l = tolower(line)
    if (l ~ error_regex && l !~ / is up to date -- skipping$/) {
      if (inatt) { hl[++nh] = line; hr[nh] = rel
                  hsrc = src; hprog = prog }
      else add(src, prog, "", line, rel)
    }
  } else if (kind == "lines") {
    add(src, prog, "", line, rel)
  } else if (kind == "probe") {
    if (line ~ /^PASS / && ph == "probes-online") {
      c = line; sub(/^PASS /, "", c); sub(/ .*$/, "", c)
      onpass[prog, c, var, acct] = 1
    }
    if (line ~ /^FAIL /) {
      chk = line; sub(/^FAIL /, "", chk); sub(/ .*$/, "", chk)
      if (ph == "probes-offline") {
        # judged at END: passes online too ⇒ a runtime fetch
        nd++; dsrc[nd] = src; dprog[nd] = prog; dchk[nd] = chk
        dline[nd] = line; drel[nd] = rel; dvar[nd] = var; dph[nd] = ph
        dacct[nd] = acct
      } else add(src, prog, chk, line, rel)
    }
  }
}
END {
  flush()
  for (d = 1; d <= nd; d++) {
    var = dvar[d]; ph = dph[d]
    if ((dprog[d], dchk[d], var, dacct[d]) in onpass) {
      add("runtime-fetch", dprog[d], dchk[d], "offline only: " dline[d],
          drel[d])
      tot["runtime-fetch" SUBSEP dprog[d]] = tot[dsrc[d] SUBSEP dprog[d]]
    } else add(dsrc[d], dprog[d], dchk[d], dline[d], drel[d])
  }
  for (i = 1; i <= nk; i++) { k = order[i]
    printf "%02d\t%s\t%s\t%s\t%s\t%s\t%d\t%d\t%s\t%s\n", rank[k], ksrc[k],
      kprog[k], kchk[k], phs[k], vars[k], cnt[k],
      tot[ksrc[k] SUBSEP kprog[k]], ex[k], logs[k]
  }
}
