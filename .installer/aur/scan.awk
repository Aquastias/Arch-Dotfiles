# =============================================================================
# scan.awk — AUR Vetting scan engine (ADR 0143)
# =============================================================================
# Text-only: never sources the PKGBUILD. Input files are the clone's text
# files; data comes in via vars. Prints one TSV finding per hit:
#   severity  id  file  line  description
# Vars: root (clone dir, stripped from file names), pkgbase, days
# (candidate UTC YYYY-MM-DD days: commits + AUR LastModified), rules /
# indicators / campaigns (paths),
# binaries (\037-separated tracked files that are not text),
# list_trust / list_indicators (print that data instead of scanning).
# =============================================================================
BEGIN {
  FS = "\t"
  nr = load(rules, rec)
  for (k = 1; k <= nr; k++) {
    if (split(rec[k], c, "\t") < 5) continue
    if (c[3] == "builtin") { bsev[c[1]] = c[2]; bdesc[c[1]] = c[5]; continue }
    # list_trust: hand the RPC trust rules to aur-vet and stop.
    if (c[3] == "trust") {
      if (list_trust) printf "%s\t%s\t%s\n", c[1], c[2], c[5]
      continue
    }
    n++; rid[n] = c[1]; rsev[n] = c[2]; rscope[n] = c[3]; rre[n] = c[4]
    rdesc[n] = c[5]; runless[n] = (6 in c) ? c[6] : ""
    delete c
  }
  delete rec
  if (list_trust) exit
  if (campaigns != "") {
    nr = load(campaigns, rec)
    for (k = 1; k <= nr; k++)
      if (split(rec[k], c, "\t") >= 3) { cfrom[c[1]] = c[2]; cto[c[1]] = c[3] }
    delete rec
  }
  if (indicators != "") {
    nr = load(indicators, rec)
    for (k = 1; k <= nr; k++) {
      if (split(rec[k], c, "\t") < 3) continue
      if (c[1] == "pkgbase") ipkg[c[2]] = c[3]
      else if (c[1] == "npm") inpm[++nnpm] = c[2]
      else if (c[1] == "domain") idom[++ndom] = tolower(c[2])
      else if (c[1] == "sha256") isha[++nsha] = tolower(c[2])
      if (list_indicators) printf "%s\t%s\t%s\n", c[1], c[2], c[3]
    }
    delete rec
    if (list_indicators) exit
  }
}

# Read a TAB-separated data file into out[1..N], skipping comments/blanks. A
# trailing backslash continues a record; the continuation drops exactly one
# leading TAB, so a line opening with two TABs starts the next field.
function load(path, out,   line, held, t, r, cnt) {
  held = ""
  while ((getline line < path) > 0) {
    if (held == "" && (line ~ /^#/ || line ~ /^[[:space:]]*$/)) continue
    t = line
    if (held != "") sub(/^\t/, "", t)
    r = held t
    if (r ~ /\\$/) { held = substr(r, 1, length(r) - 1); continue }
    held = ""; out[++cnt] = r
  }
  close(path)
  return cnt
}

# ── per file ────────────────────────────────────────────────────────────────
FNR == 1 {
  f = FILENAME; sub("^" root "/", "", f)
  kind = (f == "PKGBUILD") ? "pkgbuild" : (f ~ /\.install$/) ? "install" \
       : (f == ".SRCINFO") ? "srcinfo" : "other"
  infn = 0; bfn = 0; depth = 0; braced = 0; inarr = 0; arrsums = 0
  hd_end = ""; hd_inert = 0
  if (kind == "srcinfo") have_srcinfo = 1
}
{
  line = $0
  comment = (line ~ /^[[:space:]]*#/)
  # An inert heredoc body (a message) reads like a comment; see heredoc().
  if (heredoc(line)) comment = 1
  cursums = 0; curtop = 0
  if (kind == "pkgbuild") {
    pkgbuild_pre(line)
    # Hosts are extracted at END, after top-level variables are known.
    if (!comment) { npb++; pbl[npb] = line; pbln[npb] = FNR }
    if (curtop) emit("toplevel-code", f, FNR)
  }
  if (kind == "srcinfo") srcinfo_collect(line)
  curbuild = (kind == "pkgbuild" && infn && bfn)
  for (i = 1; i <= n; i++) {
    s = rscope[i]
    if (s == "code") {
      if (kind == "srcinfo" || comment || cursums) continue
      subj = line
    } else if (s == "build") {
      if (!curbuild || comment) continue
      subj = line
    } else if (s == "install") {
      if (kind != "install" || comment) continue
      subj = line
    } else if (s == "source") {
      if (kind != "srcinfo" || !is_source(line)) continue
      subj = source_url(line)
    } else continue
    if (subj !~ rre[i]) continue
    if (runless[i] != "" && subj ~ runless[i]) continue
    printf "%s\t%s\t%s\t%d\t%s\n", rsev[i], rid[i], f, FNR, rdesc[i]
  }
  indicators_line(line)
  if (kind == "pkgbuild") pkgbuild_post(line)
}

END {
  if (list_trust || list_indicators) exit
  binaries_emit()
  if (pkgbase ~ /-bin$/) emit("bin-package", "PKGBUILD", 0)
  indicators_pkgbase()
  if (!have_srcinfo) { emit("srcinfo-missing", ".SRCINFO", 0); exit }
  pkgbuild_hosts()
  for (h in pbhost)
    if (!(h in sihost)) emit("srcinfo-mismatch", "PKGBUILD", pbhost[h])
  for (k = 1; k <= sn; k++) {
    if (sval[k] != "SKIP") continue
    u = src[skey[k], sidx[k]]
    if (u ~ /:\/\// && u !~ /^(git|svn|hg|bzr|fossil)[+:]/)
      emit("skip-checksum", ".SRCINFO", sline[k])
  }
  for (k = 1; k <= srcall; k++) {
    o = forge_owner(srcurl[k])
    if (o != "" && index(tolower(siurl), o) == 0)
      emit("source-owner", ".SRCINFO", srcline[k])
  }
}

function emit(id, file, ln, detail) {
  if (id in bsev)
    printf "%s\t%s\t%s\t%d\t%s%s\n", bsev[id], id, file, ln, bdesc[id], \
      (detail == "" ? "" : " [" detail "]")
}

# ── Indicators ──────────────────────────────────────────────────────────────
# npm names and hosts match on word boundaries in code lines (a host only
# after `/`, `@` or `.`, so a file named temp.sh is no hit; IPs and onions
# bare). Payload hashes match anywhere, checksum arrays included.
function indicators_line(l,   k, low, code) {
  low = tolower(l)
  code = !comment
  for (k = 1; k <= nnpm; k++)
    if (code && kind != "srcinfo" && has_word(l, inpm[k]))
      emit("indicator-npm", f, FNR, inpm[k])
  for (k = 1; k <= ndom; k++)
    if (code && has_host(low, idom[k]))
      emit("indicator-domain", f, FNR, idom[k])
  for (k = 1; k <= nsha; k++)
    if (index(low, isha[k])) emit("indicator-sha256", f, FNR, isha[k])
}
# The package itself is listed: critical when any candidate day (a commit's,
# or the AUR's server-side LastModified) falls inside the campaign window,
# else suspicious until pinned (ADR 0143).
function indicators_pkgbase(   c, k, nd, d) {
  if (!(pkgbase in ipkg)) return
  c = ipkg[pkgbase]
  nd = split(days, d, " ")
  for (k = 1; k <= nd; k++)
    if (d[k] >= cfrom[c] && d[k] <= cto[c]) {
      emit("indicator-pkgbase", "PKGBUILD", 0, c)
      return
    }
  emit("indicator-pkgbase-past", "PKGBUILD", 0, c)
}
function has_word(s, w,   p, i, a, b) {
  p = 0
  while ((i = index(substr(s, p + 1), w)) > 0) {
    p += i
    a = substr(s, p - 1, 1); b = substr(s, p + length(w), 1)
    if ((p == 1 || a !~ /[[:alnum:]_.-]/) && b !~ /[[:alnum:]_-]/) return 1
  }
  return 0
}
function has_host(s, h,   p, i, a, b, bare) {
  bare = (h ~ /^[0-9.]+$/ || h ~ /\.onion$/)
  p = 0
  while ((i = index(substr(s, p + 1), h)) > 0) {
    p += i
    a = substr(s, p - 1, 1); b = substr(s, p + length(h), 1)
    if (b ~ /[[:alnum:]_-]/) continue
    if (a ~ /[\/@.]/ || (bare && (p == 1 || a !~ /[[:alnum:].]/))) return 1
  }
  return 0
}

# ── PKGBUILD structure ──────────────────────────────────────────────────────
# Classifies the line BEFORE the rules run: inside a function (and whether a
# build function), inside a checksum array, or top-level code. Brace counting
# is naive (braces in strings count) — enough to bound the functions.
function pkgbuild_pre(l,   m) {
  if (inarr) {
    cursums = arrsums
    if (closes(l)) inarr = 0
    return
  }
  if (infn) return
  if (l ~ /^[[:space:]]*(function[[:space:]]+)?[[:alpha:]_][[:alnum:]_]*\
[[:space:]]*\(\)/) {
    m = l
    sub(/^[[:space:]]*(function[[:space:]]+)?/, "", m)
    sub(/[[:space:]]*\(\).*/, "", m)
    infn = 1; depth = 0; braced = 0
    bfn = (m ~ /^(prepare|build|check|pkgver|package(_.+)?)$/)
    return
  }
  if (l ~ /^[[:space:]]*(#|$)/) return
  if (l ~ /^[[:space:]]*[[:alpha:]_][[:alnum:]_]*(\[[^]]*\])?[+]?=/) {
    m = l; sub(/^[[:space:]]*/, "", m); sub(/[[+=].*/, "", m)
    if (l ~ /[$][(]|`/) curtop = 1
    else if (l !~ /=[(]/) pvar_set(m, l)
    if (l ~ /=[(]/) {
      arrsums = (m ~ /sums(_[[:alnum:]_]+)?$/); cursums = arrsums
      if (!closes(l)) inarr = 1
    }
    return
  }
  curtop = 1
}
function pkgbuild_post(l,   t, o, cl) {
  if (!infn) return
  t = l; o = gsub(/\{/, "", t); t = l; cl = gsub(/\}/, "", t)
  depth += o - cl
  if (o) braced = 1
  if (braced && depth <= 0) { infn = 0; bfn = 0 }
}
# Does an array line close its `(`? A ` #` comment tail is ignored; a bare `#`
# is kept (URL fragments like `#tag=v1`).
function closes(l,   t) {
  t = l; sub(/[[:space:]]#.*$/, "", t)
  return t ~ /\)[[:space:]]*$/
}

# ── URLs / .SRCINFO ─────────────────────────────────────────────────────────
function hosts_of(l, arr, ln,   s, h) {
  s = l
  while (match(s, /[[:alpha:]][[:alnum:]+.-]*:\/\/[^\/[:space:]"'$:)#?]+/)) {
    h = substr(s, RSTART, RLENGTH)
    sub(/^[^:]*:\/\//, "", h); sub(/^[^@]*@/, "", h)
    h = tolower(h)
    if (!(h in arr)) arr[h] = ln
    s = substr(s, RSTART + RLENGTH)
  }
}
function is_source(l) {
  return l ~ /^[[:space:]]*source(_[[:alnum:]_]+)?[[:space:]]*=/
}
function source_url(l,   u) {
  u = l; sub(/^[^=]*=[[:space:]]*/, "", u); sub(/^[^:\/]*::/, "", u)
  return u
}
# Collect .SRCINFO sources and checksums per arch key, aligned by index.
function srcinfo_collect(l,   key, typ) {
  hosts_of(l, sihost, FNR)
  if (l ~ /^[[:space:]]*url[[:space:]]*=/) {
    siurl = l; sub(/^[^=]*=[[:space:]]*/, "", siurl)
  } else if (is_source(l)) {
    key = l; sub(/^[[:space:]]*source/, "", key)
    sub(/[[:space:]]*=.*/, "", key)
    srcn[key]++; src[key, srcn[key]] = source_url(l)
    srcall++; srcurl[srcall] = source_url(l); srcline[srcall] = FNR
  } else if (l ~ /^[[:space:]]*[[:alnum:]]+sums(_[[:alnum:]_]+)?\
[[:space:]]*=/) {
    typ = l; sub(/^[[:space:]]*/, "", typ); sub(/[[:space:]]*=.*/, "", typ)
    key = typ; sub(/^[[:alnum:]]+sums/, "", key); sub(/_.*/, "", typ)
    sumn[typ, key]++
    sn++; skey[sn] = key; sidx[sn] = sumn[typ, key]; sline[sn] = FNR
    sval[sn] = l; sub(/^[^=]*=[[:space:]]*/, "", sval[sn])
  }
}
# Owner (first path segment, `~` stripped) of a forge-hosted source, else "".
function forge_owner(u,   h, o) {
  sub(/^[[:alnum:]+]+:\/\//, "", u)
  h = u; sub(/\/.*/, "", h); h = tolower(h)
  if (h !~ /^(github\.com|raw\.githubusercontent\.com|gitlab\.com\
|codeberg\.org|bitbucket\.org|git\.sr\.ht|sr\.ht)$/) return ""
  o = u; sub(/^[^\/]*\//, "", o); sub(/\/.*/, "", o); sub(/^~/, "", o)
  return tolower(o)
}

# Files grep -I calls binary are never text-scanned. A NUL in a file bash
# sources (PKGBUILD, .install, scripts) hides code from review — and from
# `git diff` — so it is critical; other binaries (icons) are suspicious.
function binaries_emit(   k, nb, bn) {
  nb = split(binaries, bn, "\037")
  for (k = 1; k <= nb; k++) {
    if (bn[k] == "") continue
    if (bn[k] ~ /(^|\/)(PKGBUILD|\.SRCINFO)$|\.(install|sh|bash)$/)
      emit("nul-in-script", bn[k], 0)
    else emit("binary-file", bn[k], 0)
  }
}

# ── Variable-aware host cross-check ─────────────────────────────────────────
# A URL built from variables (`https://${_h}/x`) would dodge a literal host
# match, so plain top-level `name=value` assignments are expanded first; a
# host still unresolved after that is itself a mismatch.
function pvar_set(name, l,   v) {
  v = l; sub(/^[^=]*=/, "", v); sub(/[[:space:]]+#.*$/, "", v)
  if (v ~ /^".*"$/ || v ~ /^'.*'$/) v = substr(v, 2, length(v) - 2)
  pvar[name] = v
}
function expand(s,   pass, out, v, n) {
  for (pass = 0; pass < 3; pass++) {
    out = ""
    while (match(s, /[$][{]?[[:alpha:]_][[:alnum:]_]*[}]?/)) {
      v = substr(s, RSTART, RLENGTH); n = v; gsub(/[${}]/, "", n)
      out = out substr(s, 1, RSTART - 1) ((n in pvar) ? pvar[n] : v)
      s = substr(s, RSTART + RLENGTH)
    }
    s = out s
  }
  return s
}
function pkgbuild_hosts(   k, e) {
  for (k = 1; k <= npb; k++) {
    e = expand(pbl[k])
    hosts_of(e, pbhost, pbln[k])
    if (e ~ /:\/\/[$]/)
      emit("srcinfo-mismatch", "PKGBUILD", pbln[k], "unresolved host")
  }
}

# ── Heredocs ────────────────────────────────────────────────────────────────
# Is <l> the body (or terminator) of an inert heredoc? A heredoc fed to a
# plain cat/echo/printf with no redirect or pipe is a message printed to the
# user (e.g. "put this line into ~/.zshrc"), so its body isn't code. One fed
# to a shell, or redirected into a file, stays code: the opener line itself
# is scanned as usual.
function heredoc(l,   inert, w, p) {
  if (hd_end != "") {
    inert = hd_inert
    if (l ~ ("^[\t]*" hd_end "[[:space:]]*$")) { hd_end = ""; hd_inert = 0 }
    return inert
  }
  if (kind == "srcinfo") return 0
  p = match(l, /(^|[^<])<<-?[[:space:]]*["']?[[:alpha:]_][[:alnum:]_]*["']?/)
  if (!p) return 0
  w = substr(l, RSTART, RLENGTH); sub(/^[^<]*<<-?[[:space:]]*/, "", w)
  gsub(/["']/, "", w)
  hd_end = w
  hd_inert = (l ~ /^[[:space:]]*(cat|echo|printf)[[:space:]]/ \
              && l !~ /[>|]/)
  return 0
}
