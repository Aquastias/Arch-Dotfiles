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
#   feature_audit_report <run-dir>
#       → writes findings.jsonl + findings.md; 1 if any
#
# Used by: tools/feature-audit.sh (report).
# =============================================================================

# Phase order for grouping; unknown phases sort last.
FA_PHASES=(check install boot1 sessions probes-offline probes-online keybinds
           timers boot2 upgrade power)

feature_audit_known_noise_path() {
  local def="$INSTALLER_DIR/tests/vm/feature-audit/known-noise.jsonc"
  printf '%s\n' "${FEATURE_AUDIT_KNOWN_NOISE:-$def}"
}

# _report_noise_tsv — Known Noise as `regex<TAB>source<TAB>phase<TAB>variants`
# rows (variants comma-joined; empty = every variant; an array regex is one
# regex split across lines and concatenated, so the file keeps 80 columns).
_report_noise_tsv() {
  local noise_file; noise_file="$(feature_audit_known_noise_path)"
  [[ -f "$noise_file" ]] || return 0
  jsonc_strip "$noise_file" | jq -r '.[] | [(.regex | if type == "array"
      then join("") else . end), (.source // ""), (.phase // ""),
    ((.variants // []) | join(","))]
    | join("\t")'  # not @tsv: it escapes the regexes' backslashes
}

# _report_candidates <run-dir> — one aggregated Finding per line (TSV):
# phase-rank source program check phases variants count total excerpt logs
_report_candidates() {
  local run="$1" phases; phases="${FA_PHASES[*]}"
  local -a files
  mapfile -t files < <(find "$run" -mindepth 3 -maxdepth 3 -type f \
    \( -name '*.log' -o -name '*.lines' -o -name '*.probe' \) | sort)
  ((${#files[@]})) || return 0
  # an error-shaped word, not part of a name (libgpg-error, perl-error)
  local error_regex='(^|[^a-z0-9_./-])(err|error|errors|warn|warning|failed|'
  error_regex+='failure|fatal|critical)([^a-z0-9_-]|$)'
  awk -v run="$run/" -v phases="$phases" -v error_regex="$error_regex" -F'\t' \
    -f "${BASH_SOURCE[0]%/*}/report-candidates.awk" \
    noisef="$FA_NOISE_TSV" "$FA_NOISE_TSV" "${files[@]}"
}

feature_audit_report() {
  local run="${1%/}"
  if [[ ! -d "$run" ]]; then
    echo "feature-audit: no run folder: $run" >&2; return 2
  fi
  local jsonl="$run/findings.jsonl" markdown="$run/findings.md"
  rm -f "$jsonl" "$markdown"
  FA_NOISE_TSV="$(mktemp)"
  _report_noise_tsv > "$FA_NOISE_TSV"
  # stable sort: phase rank, then source; first-seen order within a group
  _report_candidates "$run" | sort -s -t$'\t' -k1,1 -k2,2 \
    | jq -R -c --arg run "$run" \
        --argjson va "$(_report_variant_adr_map "$run")" '
        split("\t") as $f
        | { phase: ($f[4] | split(",")[0]), phases: ($f[4] | split(",")),
            source: $f[1], program: (if $f[2] == "" then null else $f[2] end),
            check: (if $f[3] == "" then null else $f[3] end),
            variants: ($f[5] | split(",")), count: ($f[6] | tonumber),
            total: ($f[7] | tonumber), excerpt: $f[8],
            logs: ($f[9] | split(",") | map($run + "/" + .)),
            adrs: ([($f[5] | split(","))[] | $va[.] // [] | .[]] | unique),
            repro: ("tools/feature-audit.sh run --variant "
                    + ($f[5] | split(",")[0]) + " --keep") }' \
    | jq -c -s '([length, 999] | max | tostring | length) as $w
        | to_entries | map(.value + {id: ("F" + ((.key + 1) | tostring
        | ("0" * $w + .) | .[-$w:]))}) | .[]' > "$jsonl"
  rm -f "$FA_NOISE_TSV"
  [[ -s "$jsonl" ]] || : > "$jsonl"
  _report_render_markdown "$jsonl" "$run" > "$markdown"
  [[ -s "$jsonl" ]] && return 1
  return 0
}

# _report_render_markdown <jsonl> <run-dir> — agent-ready findings list + the
# screenshots a script cannot judge (theming), for the fixing agent to view.
_report_render_markdown() {
  local jsonl="$1" run="$2" count; count="$(grep -c . "$jsonl" || true)"
  echo "# Feature Audit findings"
  echo
  if [[ "$count" -eq 0 ]]; then
    echo "No findings."; _report_render_skips "$run"
    _report_render_visual "$run"; return 0
  fi
  echo "$count finding(s). Fix each, or propose a Known Noise entry (regex +"
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
  _report_render_skips "$run"
  _report_render_visual "$run"
}

# _report_render_skips <run-dir> — every SKIPped probe check (Probe Gate, ADR
# 0152) with its reason and variants: never a Finding, but never silent either.
_report_render_skips() {
  local run="$1"; local -a probes
  mapfile -t probes < <(find "$run" -mindepth 3 -maxdepth 3 -name '*.probe' \
    | sort)
  ((${#probes[@]})) || return 0
  awk -v run="$run/" '
    /^SKIP / {
      rel = substr(FILENAME, length(run) + 1); split(rel, p, "/")
      k = substr($0, 6)
      if (!(k in v)) { order[++n] = k; v[k] = "" }
      if (index("," v[k] ",", "," p[1] ",") == 0)
        v[k] = v[k] (v[k] == "" ? "" : ",") p[1]
    }
    END {
      if (!n) exit
      print "\n## Skipped checks\n"
      print "Gated off by the variant (Probe Gate) or not provable here."
      print ""
      for (i = 1; i <= n; i++) printf "- %s [%s]\n", order[i], v[order[i]]
    }' "${probes[@]}"
}

# _report_render_visual <run-dir> — screenshots for visual review (theming,
# layout): the fixing agent opens each and judges it.
_report_render_visual() {
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

# _report_variant_adr_map <run-dir> — {variant: [adr…]} from each variant.json,
# so a Finding names the ADRs its variants exist to cover.
_report_variant_adr_map() {
  local -a variant_files
  mapfile -t variant_files < <(find "$1" -mindepth 2 -maxdepth 2 \
    -name variant.json)
  ((${#variant_files[@]})) || { echo '{}'; return; }
  jq -s -c 'map({(.variant): (.adrs // [])}) | add' "${variant_files[@]}"
}
