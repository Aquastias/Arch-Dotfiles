#!/usr/bin/env bash
# =============================================================================
# aur-vet-scan.sh — aur-vet's scan of one clone (ADR 0143, ADR 0149)
# =============================================================================
# Sourced by aur-vet (it provides say, die, data_directory,
# library_directory and the result globals). Runs scan.awk over the clone's
# text files, compares the findings with the previous commit's (a Gained
# Finding climbs one tier) and adds the RPC trust signals.
# =============================================================================
# The result globals (CRITICAL_RULES, SUSPICIOUS_RULES, TALLY) are read by
# aur-vet.
# shellcheck disable=SC2034

# is_text <file> — rc 0 when <file> holds text: no NUL byte and at least one
# character that is not a newline.
is_text() {
  local size without_nul without_newlines
  size="$(wc -c 2>/dev/null < "$1")" || return 1
  # The size without the NUL bytes, then without the newlines.
  without_nul="$(tr -d '\000' < "$1" | wc -c)"
  without_newlines="$(tr -d '\n' < "$1" | wc -c)"
  ((size == without_nul && without_newlines > 0))
}

# Findings for the tree at <root> (paths NUL-separated on stdin) of
# <pkgbase>, with the campaign-window <days>, on stdout: TSV from scan.awk
# (severity id file line description).
scan_tree() {
  local root="$1" base="$2" days="$3" data binaries="" tracked="" file
  local -a files=()
  data="$(data_directory)"
  for file in rules indicators campaigns; do
    [[ -r "$data/$file.tsv" ]] || die "missing data file: $data/$file.tsv"
  done
  while IFS= read -r -d '' file; do
    tracked+="${file}"$'\037'
    [[ -s "$root/$file" ]] || continue
    # Text files are scanned; the rest are reported by name, never skipped.
    if is_text "$root/$file"; then files+=("$root/$file")
    else binaries+="${file}"$'\037'; fi
  done
  # Clone-derived strings go through the environment: awk -v would expand
  # backslash escapes in file names.
  AV_ROOT="$root" AV_PKGBASE="$base" AV_DAYS="$days" AV_BINARIES="$binaries" \
  AV_TRACKED="$tracked" awk -v rules="$data/rules.tsv" \
    -v indicators="$data/indicators.tsv" -v campaigns="$data/campaigns.tsv" \
    -f "$(library_directory)/scan.awk" "${files[@]+"${files[@]}"}" </dev/null
}

# Days that may place the clone at <directory> in a campaign window, on one
# space-separated line: every commit's author + committer day, and the AUR's
# own LastModified epoch <modified> (server-side). Backdating a commit can't
# hide an in-window one.
commit_days() {
  local days
  days="$(TZ=UTC git -C "$1" log --format='%ad %cd' --date=format-local:%F)" \
    || return 1
  [[ -n "${2:-}" ]] && days+=" $(date -u -d "@$2" +%F)"
  printf '%s' "$days" | tr '\n' ' '
}

# Findings for the clone at <directory> <pkgbase>, with campaign-window
# <days>.
scan_clone() { git -C "$1" ls-files -z | scan_tree "$1" "$2" "$3"; }

# Finding keys (see finding_key) of the clone's previous commit (HEAD~1),
# one per line. Its tree is extracted from the git objects into a temp
# directory — written, never checked out, sourced or run. Fails when there
# is no previous commit.
previous_keys() {
  local directory="$1" base="$2" days="$3" temporary output status=0
  git -C "$directory" rev-parse -q --verify 'HEAD~1^{commit}' >/dev/null 2>&1 \
    || return 1
  temporary="$(mktemp -d)"
  if git -C "$directory" archive HEAD~1 | tar -x -C "$temporary" \
     && output="$(git -C "$directory" ls-tree -r -z --name-only HEAD~1 \
       | scan_tree "$temporary" "$base" "$days")"; then
    print_finding_keys "$output"
  else
    status=2
  fi
  command rm -rf "$temporary"
  ((status == 0)) || die "${base}: scan of the previous commit failed"
}

# print_finding_keys <scan-rows> — the finding key of each row, one per line.
print_finding_keys() {
  local severity id file line_number description
  [[ -n "$1" ]] || return 0
  while IFS=$'\t' read -r severity id file line_number description; do
    finding_key "$id" "$file"
    printf '\n'
  done < <(printf '%s\n' "$1")
}

# Identity of a finding for the Gained Finding count: rule + file. Line
# numbers and text are left out — a version bump rewrites a flagged source
# line, a new line moves the rest — so only a rise in the count is a gain.
finding_key() { printf '%s\037%s' "$1" "$2"; }

# Scan + trust one clone and print its findings into the result globals.
evaluate() {
  local directory="$1" base="$2" modified="" json=""
  CRITICAL_RULES=(); SUSPICIOUS_RULES=()
  RPC_DOWN=0
  # One RPC answer feeds both the trust signals and the Indicator window.
  json="$(rpc_for "$directory" "$base")" || RPC_DOWN=1
  if ((!RPC_DOWN)); then
    modified="$(last_modified "$json" "$base")"
    [[ -z "$modified" || "$modified" =~ ^[0-9]+$ ]] \
      || die "${base}: AUR RPC answer malformed"
  fi
  # Fail closed: an engine error must abort, never read as "no findings".
  local output keys="" trust_rows="" has_previous=1 days status=0
  days="$(commit_days "$directory" "$modified")" \
    || die "${base}: git log failed"
  output="$(scan_clone "$directory" "$base" "$days")" \
    || die "${base}: scan failed"
  # Exit 1 = no previous commit (no comparison); anything else is a failed
  # scan and aborts — never a silent skip of the gain check.
  keys="$(previous_keys "$directory" "$base" "$days")" || status=$?
  case "$status" in
    0) ;;
    1) has_previous=0 ;;
    *) die "${base}: scan of the previous commit failed" ;;
  esac
  if ((!RPC_DOWN)); then
    trust_rows="$(trust "$json" "$base")" || die "${base}: trust check failed"
  fi
  report_findings "$output" "$trust_rows" "$keys" "$has_previous"
}

# report_findings <scan-rows> <trust-rows> <previous-keys> <has-previous> —
# say each finding (a Gained Finding one tier up) and fill the result
# globals.
report_findings() {
  local output="$1" trust_rows="$2" keys="$3" has_previous="$4"
  local -A before=() now=()
  local -a findings=()
  local row severity id file line_number description key tag shown
  local critical=0 suspicious=0 info=0 gained=0
  # Per-key counts in the previous commit and now; a rise is a gain.
  if [[ -n "$keys" ]]; then
    while IFS= read -r key; do
      before["$key"]=$((${before["$key"]:-0} + 1))
    done < <(printf '%s\n' "$keys")
  fi
  [[ -n "$output" ]] && mapfile -t findings < <(printf '%s\n' "$output")
  for row in "${findings[@]}"; do
    IFS=$'\t' read -r severity id file line_number description \
      < <(printf '%s\n' "$row")
    key="$(finding_key "$id" "$file")"
    now["$key"]=$((${now["$key"]:-0} + 1))
  done
  [[ -n "$trust_rows" ]] && mapfile -t -O "${#findings[@]}" findings \
    < <(printf '%s\n' "$trust_rows")
  for row in "${findings[@]}"; do
    IFS=$'\t' read -r severity id file line_number description \
      < <(printf '%s\n' "$row")
    tag=""
    # A Gained Finding climbs one tier (ADR 0149); trust rows have no past.
    key="$(finding_key "$id" "$file")"
    if ((has_previous)) && [[ "$file" != AUR ]] \
       && ((${now["$key"]:-0} > ${before["$key"]:-0})); then
      gained=1; tag=" (gained since the previous commit)"
      case "$severity" in
        info) severity=suspicious ;;
        suspicious) severity=critical ;;
      esac
    fi
    # A probable adoption that also gained something is the Atomic Arch
    # takeover shape (ADR 0149). Trust rows come last, after every gain.
    if [[ "$id" == trust-adopted ]] && ((gained)); then
      severity=critical; tag=" (adopted and gained a finding)"
    fi
    shown="$(printf '%s\n' "$severity" | tr '[:lower:]' '[:upper:]')"
    say "${shown} ${id} ${file}:${line_number} ${description}${tag}"
    case "$severity" in
      critical) critical=$((critical + 1)); CRITICAL_RULES["$id"]=1 ;;
      suspicious) suspicious=$((suspicious + 1)); SUSPICIOUS_RULES["$id"]=1 ;;
      *) info=$((info + 1)) ;;
    esac
  done
  TALLY="${critical} critical, ${suspicious} suspicious, ${info} info"
}
