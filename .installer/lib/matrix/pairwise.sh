#!/usr/bin/env bash
# =============================================================================
# lib/matrix/pairwise.sh — Combination Matrix Pairwise Reducer (ADR 0046)
# =============================================================================
# A pure, menu-agnostic 2-wise covering-array builder. Given axes (each with its
# allowed values) and exclusion constraints, it emits a deterministic set of
# rows in which every VALID value-pair (across every axis-pair) co-occurs in at
# least one row and no constraint-excluded pair ever appears. Reproducible: the
# same axes+constraints+seed yield byte-identical output. Minimality is not a
# goal (an implementation detail) — correctness and determinism are.
#
# I/O (JSON):
#   axes         object, axis order preserved: {"fs":["zfs","btrfs"], ...}.
#                Values may be strings/bools/numbers (kept as JSON tokens).
#   constraints  array of forbidden partial assignments: [{"fs":"ext4",
#                "topology":"mirror"}]. A row is excluded iff it matches ALL of
#                a constraint's keys. 1-key constraints forbid a value outright.
#   seed         integer; rotates each axis's value try-order for a reproducible
#                but seed-varied cover.
#   output       one JSON row object per line, keys in axis order.
#
# Algorithm: greedy pair coverage — seed a row from the deterministically-first
# uncovered pair, complete it by a coverage-maximising forward pass, and fall
# back to a backtracking search when constraints block the forward pass (so a
# genuinely completable pair is never dropped, and an impossible pair emits no
# row). Pure bash after jq parse; no TTY, no disk writes.
#
# Public API:
#   matrix_pairwise <axes_json> <constraints_json> [seed]  → rows (JSON lines)
# =============================================================================

# matrix_pairwise <axes_json> <constraints_json> [seed]
matrix_pairwise() {
  local axes_json="$1" constraints_json="${2:-[]}" seed="${3:-0}"

  # ── parse axes ────────────────────────────────────────────────────────────
  local -a NAMES=()
  mapfile -t NAMES < <(jq -r 'keys_unsorted[]' <<<"$axes_json")
  local n=${#NAMES[@]}
  local -A VAL=()          # VAL["i,idx"] = JSON token
  local -a NVAL=()         # NVAL[i] = value count of axis i
  local i idx k
  local -a _vs
  for ((i = 0; i < n; i++)); do
    k="${NAMES[i]}"
    mapfile -t _vs < <(jq -c --arg k "$k" '.[$k][]' <<<"$axes_json")
    NVAL[i]=${#_vs[@]}
    for ((idx = 0; idx < ${#_vs[@]}; idx++)); do VAL["$i,$idx"]="${_vs[idx]}"; done
  done

  # seed-rotated try-order of value indices per axis (reproducible).
  local -A ORDER=() pos r cnt
  for ((i = 0; i < n; i++)); do
    cnt=${NVAL[i]}; ((cnt > 0)) || continue
    r=$((seed % cnt))
    for ((pos = 0; pos < cnt; pos++)); do ORDER["$i,$pos"]=$(((pos + r) % cnt)); done
  done

  # ── parse constraints into TAB-delimited "key<TAB>valjson" blocks ──────────
  local -a CONSTR=()
  local cj
  while IFS= read -r cj; do
    [[ -n "$cj" ]] || continue
    CONSTR+=("$(jq -r 'to_entries[] | "\(.key)\t\(.value|tojson)"' <<<"$cj")")
  done < <(jq -c '.[]?' <<<"$constraints_json")

  # ── enumerate valid uncovered pairs (i<j) ─────────────────────────────────
  local -A UNCOV=()
  local j ai aj
  for ((i = 0; i < n; i++)); do
    for ((j = i + 1; j < n; j++)); do
      for ((ai = 0; ai < NVAL[i]; ai++)); do
        for ((aj = 0; aj < NVAL[j]; aj++)); do
          local -A _p=()
          _p["${NAMES[i]}"]="${VAL[$i,$ai]}"
          _p["${NAMES[j]}"]="${VAL[$j,$aj]}"
          _pw_ok _p && UNCOV["$i,$ai,$j,$aj"]=1
        done
      done
    done
  done

  # ── greedy build ──────────────────────────────────────────────────────────
  local -a ROWS_OUT=()
  local -A ROW=() ASSIGNED=()
  local pk pi pai pj paj m a b
  while ((${#UNCOV[@]})); do
    pk="$(printf '%s\n' "${!UNCOV[@]}" | sort -t, -k1,1n -k2,2n -k3,3n -k4,4n \
      | head -1)"
    IFS=',' read -r pi pai pj paj <<<"$pk"

    ROW=(); ASSIGNED=()
    ROW["${NAMES[pi]}"]="${VAL[$pi,$pai]}"; ASSIGNED[$pi]=$pai
    ROW["${NAMES[pj]}"]="${VAL[$pj,$paj]}"; ASSIGNED[$pj]=$paj

    if ! _pw_forward; then
      # forward pass blocked → reset to the seed pair and backtrack.
      ROW=(); ASSIGNED=()
      ROW["${NAMES[pi]}"]="${VAL[$pi,$pai]}"; ASSIGNED[$pi]=$pai
      ROW["${NAMES[pj]}"]="${VAL[$pj,$paj]}"; ASSIGNED[$pj]=$paj
      if ! _pw_extend 0; then unset "UNCOV[$pk]"; continue; fi
    fi

    # mark every pair in the completed row covered.
    for a in "${!ASSIGNED[@]}"; do
      for b in "${!ASSIGNED[@]}"; do
        ((a < b)) || continue
        unset "UNCOV[$a,${ASSIGNED[$a]},$b,${ASSIGNED[$b]}]"
      done
    done
    ROWS_OUT+=("$(_pw_row_json)")
  done

  ((${#ROWS_OUT[@]})) && printf '%s\n' "${ROWS_OUT[@]}"
  return 0
}

# _pw_ok <row-assoc-name> — 0 iff the (partial) row violates no constraint.
_pw_ok() {
  local -n _row="$1"
  local c key val allmatch
  for c in ${CONSTR[@]+"${CONSTR[@]}"}; do
    allmatch=1
    while IFS=$'\t' read -r key val; do
      [[ -n "$key" ]] || continue
      if [[ -z "${_row[$key]+x}" || "${_row[$key]}" != "$val" ]]; then
        allmatch=0; break
      fi
    done <<<"$c"
    ((allmatch)) && return 1
  done
  return 0
}

# _pw_forward — complete ROW/ASSIGNED by a coverage-maximising forward pass over
# the unassigned axes (no backtracking). 0 on a full valid row, 1 if some axis
# has no constraint-valid value. Reads NAMES/NVAL/VAL/ORDER/UNCOV/ASSIGNED/n.
_pw_forward() {
  local m pos vi best best_cov cov a aidx key
  for ((m = 0; m < n; m++)); do
    [[ -n "${ASSIGNED[$m]+x}" ]] && continue
    best=-1; best_cov=-1
    for ((pos = 0; pos < NVAL[m]; pos++)); do
      vi=${ORDER[$m,$pos]}
      ROW["${NAMES[m]}"]="${VAL[$m,$vi]}"
      if _pw_ok ROW; then
        cov=0
        for a in "${!ASSIGNED[@]}"; do
          aidx=${ASSIGNED[$a]}
          if ((a < m)); then key="$a,$aidx,$m,$vi"; else key="$m,$vi,$a,$aidx"; fi
          [[ -n "${UNCOV[$key]+x}" ]] && ((cov++))
        done
        ((cov > best_cov)) && { best_cov=$cov; best=$vi; }
      fi
      unset "ROW[${NAMES[m]}]"
    done
    ((best < 0)) && return 1
    ROW["${NAMES[m]}"]="${VAL[$m,$best]}"; ASSIGNED[$m]=$best
  done
  return 0
}

# _pw_extend <m> — backtracking completion from axis <m>; 0 iff ROW/ASSIGNED can
# be extended to a full constraint-valid row. Deterministic (ORDER-first).
_pw_extend() {
  local m=$1 pos vi
  ((m == n)) && return 0
  if [[ -n "${ASSIGNED[$m]+x}" ]]; then _pw_extend $((m + 1)); return $?; fi
  for ((pos = 0; pos < NVAL[m]; pos++)); do
    vi=${ORDER[$m,$pos]}
    ROW["${NAMES[m]}"]="${VAL[$m,$vi]}"
    if _pw_ok ROW; then
      ASSIGNED[$m]=$vi
      _pw_extend $((m + 1)) && return 0
      unset "ASSIGNED[$m]"
    fi
  done
  unset "ROW[${NAMES[m]}]"
  return 1
}

# _pw_row_json — the completed ROW as a compact JSON object, keys in axis order
# (deterministic). Reads NAMES/ROW/n.
_pw_row_json() {
  local -a jqargs=()
  local prog="{" idx k
  for ((idx = 0; idx < n; idx++)); do
    k="${NAMES[idx]}"
    jqargs+=(--arg "k$idx" "$k" --argjson "v$idx" "${ROW[$k]}")
    ((idx)) && prog+=","
    prog+="(\$k$idx):\$v$idx"
  done
  prog+="}"
  jq -c -n "${jqargs[@]}" "$prog"
}
