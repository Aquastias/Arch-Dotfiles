#!/usr/bin/env bash
# =============================================================================
# lib/feature-audit/report.sh — Audit Run folder → Findings (ADR 0152)
# =============================================================================
# Judging is kept apart from collecting: collectors only drop raw artifacts
# into <run>/<variant>/<phase>/, this turns them into Findings, so the whole
# judgement is testable without a VM and re-runnable after Known Noise edits.
#
# Artifact kinds (by extension):
#   *.log    free-form (installer): error/warn/fail-shaped lines are Findings
#   *.lines  pre-filtered signal (journal ≥ warning, failed units, coredumps,
#            kernel errors, probe stderr): every non-empty line is a Finding
#   *.probe  probe output `PASS|FAIL|SKIP <check> <msg>`: FAIL is a Finding
#            (a probes-offline FAIL whose check PASSes in probes-online is a
#            "runtime-fetch" Finding: the feature needs network after install)
# Probe artifacts are named `probe-<program>@<user>.probe` (stderr:
# `…@<user>.err.lines`); program names may hold `-`, never `@`.
#
# Public API:
#   fa_report <run-dir>   → writes findings.jsonl + findings.md; 1 if any
# =============================================================================

# Phase order for grouping; unknown phases sort last.
FA_PHASES=(check install boot1 sessions probes-offline probes-online keybinds
           power timers boot2 upgrade)

fa_known_noise_path() {
  local def="$INSTALLER_DIR/tests/vm/feature-audit/known-noise.jsonc"
  printf '%s\n' "${FEATURE_AUDIT_KNOWN_NOISE:-$def}"
}

# _fa_noise_tsv — Known Noise as `regex<TAB>source<TAB>phase` rows.
_fa_noise_tsv() {
  local f; f="$(fa_known_noise_path)"
  [[ -f "$f" ]] || return 0
  jsonc_strip "$f" | jq -r '.[] | [.regex, (.source // ""), (.phase // "")]
    | @tsv'
}

# _fa_candidates <run-dir> — one aggregated Finding per line (TSV):
# phase-rank source program check phases variants count total excerpt logs
_fa_candidates() {
  local run="$1" phases; phases="${FA_PHASES[*]}"
  local -a files
  mapfile -t files < <(find "$run" -mindepth 3 -maxdepth 3 -type f \
    \( -name '*.log' -o -name '*.lines' -o -name '*.probe' \) | sort)
  ((${#files[@]})) || return 0
  # an error-shaped word, not part of a name (libgpg-error, perl-error)
  local errre='(^|[^a-z0-9_./-])(err|error|errors|warn|warning|failed|'
  errre+='failure|fatal|critical)([^a-z0-9_-]|$)'
  awk -v run="$run/" -v phases="$phases" -v errre="$errre" -F'\t' '
    function clean(s) {
      gsub(/\033\[[0-9;]*[A-Za-z]/, "", s); gsub(/\t/, " ", s)
      gsub(/\r/, "", s)
      # journal short-iso/short prefix: "Mon DD HH:MM:SS host "
      sub(/^[A-Z][a-z][a-z] [ 0-9][0-9] [0-9:][0-9:]+ [^ ]+ /, "", s)
      return s
    }
    function norm(s) {
      gsub(/\[[0-9]+\]/, "[N]", s)
      gsub(/0x[0-9a-fA-F]+/, "0xN", s)
      gsub(/[0-9a-fA-F]{8}-[0-9a-fA-F-]{27}/, "UUID", s)
      gsub(/[0-9]+/, "N", s)
      return s
    }
    function noisy(line, src, ph,   i) {
      for (i = 1; i <= nn; i++)
        if ((ns[i] == "" || ns[i] == src) && (np[i] == "" || np[i] == ph) \
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
    BEGIN { np0 = split(phases, pl, " ") }
    FILENAME == noisef { nn++; nr[nn] = $1; ns[nn] = $2; np[nn] = $3; next }
    FNR == 1 {
      rel = substr(FILENAME, length(run) + 1)
      split(rel, parts, "/"); var = parts[1]; ph = parts[2]; base = parts[3]
      kind = base; sub(/^.*\./, "", kind)
      src = base; sub(/\.[^.]*$/, "", src); prog = ""
      if (src ~ /^probe-/) {
        prog = src; sub(/^probe-/, "", prog); sub(/@.*$/, "", prog)
        src = (src ~ /\.err$/) ? "probe-stderr" : "probe"
      }
      g = src SUBSEP prog
      if (!((g, var, ph) in units)) { units[g, var, ph] = 1; tot[g]++ }
    }
    {
      line = clean($0)
      if (line ~ /^[[:space:]]*$/) next
      if (kind == "log") {
        l = tolower(line)
        if (l ~ errre)
          add(src, prog, "", line, rel)
      } else if (kind == "lines") {
        add(src, prog, "", line, rel)
      } else if (kind == "probe") {
        if (line ~ /^PASS / && ph == "probes-online") {
          c = line; sub(/^PASS /, "", c); sub(/ .*$/, "", c)
          onpass[prog, c, var] = 1
        }
        if (line ~ /^FAIL /) {
          chk = line; sub(/^FAIL /, "", chk); sub(/ .*$/, "", chk)
          if (ph == "probes-offline") {
            # judged at END: passes online too ⇒ a runtime fetch
            nd++; dsrc[nd] = src; dprog[nd] = prog; dchk[nd] = chk
            dline[nd] = line; drel[nd] = rel; dvar[nd] = var; dph[nd] = ph
          } else add(src, prog, chk, line, rel)
        }
      }
    }
    END {
      for (d = 1; d <= nd; d++) {
        var = dvar[d]; ph = dph[d]
        if ((dprog[d], dchk[d], var) in onpass) {
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
  ' noisef="$FA_NOISE_TSV" "$FA_NOISE_TSV" "${files[@]}"
}

fa_report() {
  local run="${1%/}"
  if [[ ! -d "$run" ]]; then
    echo "feature-audit: no run folder: $run" >&2; return 2
  fi
  local jsonl="$run/findings.jsonl" md="$run/findings.md"
  rm -f "$jsonl" "$md"
  FA_NOISE_TSV="$(mktemp)"
  _fa_noise_tsv > "$FA_NOISE_TSV"
  # stable sort: phase rank, then source; first-seen order within a group
  _fa_candidates "$run" | sort -s -t$'\t' -k1,1 -k2,2 \
    | jq -R -c --arg run "$run" '
        split("\t") as $f
        | { phase: ($f[4] | split(",")[0]), phases: ($f[4] | split(",")),
            source: $f[1], program: (if $f[2] == "" then null else $f[2] end),
            check: (if $f[3] == "" then null else $f[3] end),
            variants: ($f[5] | split(",")), count: ($f[6] | tonumber),
            total: ($f[7] | tonumber), excerpt: $f[8],
            logs: ($f[9] | split(",") | map($run + "/" + .)), adrs: [],
            repro: ("tools/feature-audit.sh run --variant "
                    + ($f[5] | split(",")[0]) + " --keep") }' \
    | jq -c -s 'to_entries | map(.value + {id: ("F" + ((.key + 1)
        | tostring | (("000" + .) | .[-3:])))}) | .[]' > "$jsonl"
  rm -f "$FA_NOISE_TSV"
  [[ -s "$jsonl" ]] || : > "$jsonl"
  _fa_render_md "$jsonl" "$run" > "$md"
  [[ -s "$jsonl" ]] && return 1
  return 0
}

# _fa_render_md <jsonl> <run-dir> — agent-ready findings list + the
# screenshots a script cannot judge (theming), for the fixing agent to view.
_fa_render_md() {
  local jsonl="$1" run="$2" n; n="$(grep -c . "$jsonl" || true)"
  echo "# Feature Audit findings"
  echo
  if [[ "$n" -eq 0 ]]; then
    echo "No findings."; _fa_render_visual "$run"; return 0
  fi
  echo "$n finding(s). Fix each, or propose a Known Noise entry (regex +"
  echo "reason) for maintainer approval. Repro: rerun the variant with"
  echo "\`--keep\`, then inspect the listed log on the held VM."
  jq -r -s '
    group_by(.phase) | sort_by(.[0].id) | .[] |
    "\n## \(.[0].phase)\n" + (
      group_by(.source) | sort_by(.[0].id) | map(
        "\n### \(.[0].source)\n" + (map(
          "\n- **\(.id)** [\(.variants | join(", "))] "
          + (if .program then "program=\(.program) " else "" end)
          + (if .check then "check=\(.check) " else "" end)
          + "seen \(.count)/\(.total) (\(.phases | join(", ")))\n"
          + "  ```\n  \(.excerpt)\n  ```\n"
          + "  logs: \(.logs | join(" "))\n"
          + "  repro: `\(.repro)`"
        ) | join("\n"))
      ) | join("\n"))
  ' "$jsonl"
  _fa_render_visual "$run"
}

# _fa_render_visual <run-dir> — screenshots for visual review (theming,
# layout): the fixing agent opens each and judges it.
_fa_render_visual() {
  local run="$1"; local -a shots
  mapfile -t shots < <(find "$run" -name '*.png' | sort)
  ((${#shots[@]})) || return 0
  echo
  echo "## Visual review"
  echo
  echo "Open each screenshot; report theming/layout breakage (wrong colours,"
  echo "unthemed Qt/GTK app, missing bar/wallpaper) as a finding."
  echo
  printf -- '- %s\n' "${shots[@]}"
}
