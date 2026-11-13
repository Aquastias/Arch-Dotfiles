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
# The jq programs held in single-quoted variables use jq's $names.
# shellcheck disable=SC2016

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
  jsonc_strip "$noise_file" | jq -r -f "${BASH_SOURCE[0]%/*}/report-noise.jq"
}

# _report_candidates <run-dir> — one aggregated Finding per line (TSV):
# phase-rank source program check phases variants count total excerpt logs
# severity (blocking | advisory, ADR 0165)
_report_candidates() {
  local run="$1" phases; phases="${FA_PHASES[*]}"
  local -a files
  mapfile -t files < <(find "$run" -mindepth 3 -maxdepth 3 -type f \
    \( -name '*.log' -o -name '*.lines' -o -name '*.warnings' \
       -o -name '*.probe' \) | sort)
  ((${#files[@]})) || return 0
  # an error-shaped word, not part of a name (libgpg-error, perl-error)
  local error_regex='(^|[^a-z0-9_./-])(err|error|errors|warn|warning|failed|'
  error_regex+='failure|fatal|critical)([^a-z0-9_-]|$)'
  # the same minus warn/warning: a line matching only those is advisory
  local blocking_regex='(^|[^a-z0-9_./-])(err|error|errors|failed|failure|'
  blocking_regex+='fatal|critical)([^a-z0-9_-]|$)'
  awk -v run="$run/" -v phases="$phases" -v error_regex="$error_regex" \
    -v blocking_regex="$blocking_regex" -F'\t' \
    -f "${BASH_SOURCE[0]%/*}/report-candidates.awk" \
    noisef="$FA_NOISE_TSV" "$FA_NOISE_TSV" "${files[@]}"
}

feature_audit_report() {
  local run="$1"
  # Without a trailing slash.
  [[ "$run" == */ ]] && run="${run:0:${#run}-1}"
  if [[ ! -d "$run" ]]; then
    echo "feature-audit: no run folder: $run" >&2; return 2
  fi
  local jsonl="$run/findings.jsonl" markdown="$run/findings.md"
  local advisories="$run/advisories.jsonl" all
  rm -f "$jsonl" "$markdown" "$advisories"
  FA_NOISE_TSV="$(mktemp)"
  _report_noise_tsv > "$FA_NOISE_TSV"
  local adr_map
  adr_map="$(_report_variant_adr_map "$run")"
  # The candidates, stable-sorted by phase rank then source (first-seen order
  # within a group), each as a Finding object.
  all="$(_report_candidates "$run" | sort -s -t$'\t' -k1,1 -k2,2 \
    | jq -R -c --arg run "$run" --argjson va "$adr_map" \
      -f "${BASH_SOURCE[0]%/*}/report-finding.jq")"
  rm -f "$FA_NOISE_TSV"
  _report_numbered "$all" blocking F > "$jsonl"
  _report_numbered "$all" advisory A > "$advisories"
  _report_render_markdown "$jsonl" "$run" > "$markdown"
  [[ -s "$jsonl" ]] && return 1
  return 0
}

# _report_numbered <entries> <severity> <prefix> — the <severity> entries of
# <entries> (JSON lines), numbered <prefix>NNN in order (width ≥ 3).
_report_numbered() {
  [[ -n "$1" ]] || return 0
  # The entries of that severity, numbered.
  printf '%s\n' "$1" | jq -c -s --arg sev "$2" --arg p "$3" \
    -f "${BASH_SOURCE[0]%/*}/report-numbered.jq"
}

# _report_render_markdown <jsonl> <run-dir> — agent-ready findings list + the
# screenshots a script cannot judge (theming), for the fixing agent to view.
_report_render_markdown() {
  local jsonl="$1" run="$2" count; count="$(grep -c . "$jsonl" || true)"
  echo "# Feature Audit findings"
  echo
  if [[ "$count" -eq 0 ]]; then
    echo "No findings."; _report_render_advisories "$run"
    _report_render_skips "$run"; _report_render_visual "$run"; return 0
  fi
  echo "$count finding(s). Fix each, or propose a Known Noise entry (regex +"
  echo "reason) for maintainer approval. Repro: rerun the variant with"
  echo "\`--keep\`, then inspect the listed log on the held VM."
  jq -r -s -f "${BASH_SOURCE[0]%/*}/report-markdown.jq" "$jsonl"
  _report_render_advisories "$run"
  _report_render_skips "$run"
  _report_render_visual "$run"
}

# _report_render_advisories <run-dir> — warning-level lines (ADR 0165): listed
# with frequency so a trend stays visible, never a Finding.
_report_render_advisories() {
  local advisories="$1/advisories.jsonl"
  [[ -s "$advisories" ]] || return 0
  echo
  echo "## Advisory warnings"
  echo
  echo "Warning-level lines: reported, never failing the run."
  echo
  local bullet='"- **\(.id)** [\(.variants | join(", "))] \(.source) seen "'
  bullet+=' + "\(.count)/\(.total) (\(.phases | join(", "))): `\(.excerpt)`"'
  # One bullet per advisory.
  jq -r "$bullet" "$advisories"
}

# _report_render_skips <run-dir> — every SKIPped probe check (Probe Gate, ADR
# 0152) with its reason and variants: never a Finding, but never silent either.
_report_render_skips() {
  local run="$1"; local -a probes
  mapfile -t probes < <(find "$run" -mindepth 3 -maxdepth 3 -name '*.probe' \
    | sort)
  ((${#probes[@]})) || return 0
  awk -v run="$run/" -f "${BASH_SOURCE[0]%/*}/report-skips.awk" "${probes[@]}"
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
  # Every variant's ADRs, merged into one map.
  jq -s -c 'map({(.variant): (.adrs // [])}) | add' "${variant_files[@]}"
}
