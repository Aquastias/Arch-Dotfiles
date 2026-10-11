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
#
# Used by: lib/matrix/generator.sh.
# =============================================================================

# matrix_pairwise <axes_json> <constraints_json> [seed]. The phases below share
# this function's state arrays (dynamic scope): AXIS_NAMES, AXIS_COUNT,
# AXIS_VALUES["axis,index"] (JSON token), AXIS_VALUE_COUNTS[axis],
# VALUE_ORDER["axis,position"] (seed-rotated try-order), CONSTRAINTS
# ("key<TAB>value-json" blocks), UNCOVERED["axis,index,axis,index"], and the
# row being built: ROW[name] / ASSIGNED[axis] = value index.
matrix_pairwise() {
  local axes_json="$1" constraints_json="${2:-[]}" seed="${3:-0}"
  local -a AXIS_NAMES=() AXIS_VALUE_COUNTS=() CONSTRAINTS=() rows_out=()
  local -A AXIS_VALUES=() VALUE_ORDER=() UNCOVERED=() ROW=() ASSIGNED=()
  local AXIS_COUNT pair first_axis first_index second_axis second_index
  _pairwise_parse_axes "$axes_json"
  _pairwise_order_values "$seed"
  _pairwise_parse_constraints "$constraints_json"
  _pairwise_enumerate_pairs

  # Greedy build: seed a row from the first uncovered pair, complete it
  # forward, else backtrack; an uncompletable pair is dropped.
  while ((${#UNCOVERED[@]})); do
    pair="$(printf '%s\n' "${!UNCOVERED[@]}" \
      | sort -t, -k1,1n -k2,2n -k3,3n -k4,4n | awk 'NR == 1 { print; exit }')"
    IFS=',' read -r first_axis first_index second_axis second_index <<<"$pair"
    _pairwise_seed_row
    if ! _pairwise_forward; then
      # forward pass blocked → reset to the seed pair and backtrack.
      _pairwise_seed_row
      if ! _pairwise_extend 0; then unset "UNCOVERED[$pair]"; continue; fi
    fi
    _pairwise_mark_covered
    rows_out+=("$(_pairwise_row_json)")
  done

  ((${#rows_out[@]})) && printf '%s\n' "${rows_out[@]}"
  return 0
}

# _pairwise_parse_axes <axes_json> — AXIS_NAMES, AXIS_COUNT, AXIS_VALUES,
# AXIS_VALUE_COUNTS, in axis order.
_pairwise_parse_axes() {
  local axes_json="$1" axis index name
  local -a values
  mapfile -t AXIS_NAMES < <(jq -r 'keys_unsorted[]' <<<"$axes_json")
  AXIS_COUNT=${#AXIS_NAMES[@]}
  for ((axis = 0; axis < AXIS_COUNT; axis++)); do
    name="${AXIS_NAMES[axis]}"
    mapfile -t values < <(jq -c --arg k "$name" '.[$k][]' <<<"$axes_json")
    AXIS_VALUE_COUNTS[axis]=${#values[@]}
    for ((index = 0; index < ${#values[@]}; index++)); do
      AXIS_VALUES["$axis,$index"]="${values[index]}"
    done
  done
  return 0
}

# _pairwise_order_values <seed> — the seed-rotated try-order of value indices
# per axis (reproducible).
_pairwise_order_values() {
  local seed="$1" axis position rotation count
  for ((axis = 0; axis < AXIS_COUNT; axis++)); do
    count=${AXIS_VALUE_COUNTS[axis]}; ((count > 0)) || continue
    rotation=$((seed % count))
    for ((position = 0; position < count; position++)); do
      VALUE_ORDER["$axis,$position"]=$(((position + rotation) % count))
    done
  done
  return 0
}

# _pairwise_parse_constraints <constraints_json> — one TAB-delimited
# "key<TAB>value-json" block per constraint.
_pairwise_parse_constraints() {
  local constraint
  while IFS= read -r constraint; do
    [[ -n "$constraint" ]] || continue
    CONSTRAINTS+=("$(jq -r 'to_entries[] | "\(.key)\t\(.value|tojson)"' \
      <<<"$constraint")")
  done < <(jq -c '.[]?' <<<"$1")
  return 0
}

# _pairwise_enumerate_pairs — every valid value pair across axes i<j into
# UNCOVERED.
_pairwise_enumerate_pairs() {
  local first second
  for ((first = 0; first < AXIS_COUNT; first++)); do
    for ((second = first + 1; second < AXIS_COUNT; second++)); do
      _pairwise_enumerate_value_pairs "$first" "$second"
    done
  done
  return 0
}

# shellcheck disable=SC2034 # pair_row is read through _pairwise_ok's nameref
_pairwise_enumerate_value_pairs() {
  local first="$1" second="$2" first_index second_index
  for ((first_index = 0; first_index < AXIS_VALUE_COUNTS[first]; first_index++))
  do
    for ((second_index = 0; second_index < AXIS_VALUE_COUNTS[second];
          second_index++)); do
      local -A pair_row=()
      pair_row["${AXIS_NAMES[first]}"]="${AXIS_VALUES[$first,$first_index]}"
      pair_row["${AXIS_NAMES[second]}"]="${AXIS_VALUES[$second,$second_index]}"
      _pairwise_ok pair_row \
        && UNCOVERED["$first,$first_index,$second,$second_index"]=1
    done
  done
  return 0
}

# _pairwise_seed_row — ROW/ASSIGNED holding just the caller's seed pair.
_pairwise_seed_row() {
  ROW=(); ASSIGNED=()
  ROW["${AXIS_NAMES[first_axis]}"]="${AXIS_VALUES[$first_axis,$first_index]}"
  ASSIGNED[$first_axis]=$first_index
  ROW["${AXIS_NAMES[second_axis]}"]="${AXIS_VALUES[$second_axis,$second_index]}"
  ASSIGNED[$second_axis]=$second_index
}

# _pairwise_mark_covered — every pair in the completed row leaves UNCOVERED.
_pairwise_mark_covered() {
  local first second
  for first in "${!ASSIGNED[@]}"; do
    for second in "${!ASSIGNED[@]}"; do
      ((first < second)) || continue
      unset "UNCOVERED[$first,${ASSIGNED[$first]},$second,${ASSIGNED[$second]}]"
    done
  done
  return 0
}

# _pairwise_ok <row-assoc-name> — 0 iff the (partial) row violates no
# constraint.
_pairwise_ok() {
  local -n checked_row="$1"
  local constraint key value all_match
  for constraint in ${CONSTRAINTS[@]+"${CONSTRAINTS[@]}"}; do
    all_match=1
    while IFS=$'\t' read -r key value; do
      [[ -n "$key" ]] || continue
      if [[ -z "${checked_row[$key]+x}" || "${checked_row[$key]}" != "$value" ]]
      then
        all_match=0; break
      fi
    done <<<"$constraint"
    ((all_match)) && return 1
  done
  return 0
}

# _pairwise_forward — complete ROW/ASSIGNED by a coverage-maximising forward
# pass over the unassigned axes (no backtracking). 0 on a full valid row, 1 if
# some axis has no constraint-valid value.
_pairwise_forward() {
  local axis position value_index best best_coverage coverage
  for ((axis = 0; axis < AXIS_COUNT; axis++)); do
    [[ -n "${ASSIGNED[$axis]+x}" ]] && continue
    best=-1; best_coverage=-1
    for ((position = 0; position < AXIS_VALUE_COUNTS[axis]; position++)); do
      value_index=${VALUE_ORDER[$axis,$position]}
      ROW["${AXIS_NAMES[axis]}"]="${AXIS_VALUES[$axis,$value_index]}"
      if _pairwise_ok ROW; then
        _pairwise_coverage "$axis" "$value_index"
        ((coverage > best_coverage)) \
          && { best_coverage=$coverage; best=$value_index; }
      fi
      unset "ROW[${AXIS_NAMES[axis]}]"
    done
    ((best < 0)) && return 1
    ROW["${AXIS_NAMES[axis]}"]="${AXIS_VALUES[$axis,$best]}"
    ASSIGNED[$axis]=$best
  done
  return 0
}

# _pairwise_coverage <axis> <value-index> — set the caller's `coverage` to how
# many still-uncovered pairs that value would cover alongside the row's
# assigned values.
_pairwise_coverage() {
  local axis="$1" value_index="$2" assigned assigned_index key
  coverage=0
  for assigned in "${!ASSIGNED[@]}"; do
    assigned_index=${ASSIGNED[$assigned]}
    if ((assigned < axis)); then
      key="$assigned,$assigned_index,$axis,$value_index"
    else
      key="$axis,$value_index,$assigned,$assigned_index"
    fi
    [[ -n "${UNCOVERED[$key]+x}" ]] && ((coverage++))
  done
  return 0
}

# _pairwise_extend <axis> — backtracking completion from <axis>; 0 iff
# ROW/ASSIGNED can be extended to a full constraint-valid row. Deterministic
# (VALUE_ORDER first).
_pairwise_extend() {
  local axis=$1 position value_index
  ((axis == AXIS_COUNT)) && return 0
  if [[ -n "${ASSIGNED[$axis]+x}" ]]; then
    _pairwise_extend $((axis + 1)); return $?
  fi
  for ((position = 0; position < AXIS_VALUE_COUNTS[axis]; position++)); do
    value_index=${VALUE_ORDER[$axis,$position]}
    ROW["${AXIS_NAMES[axis]}"]="${AXIS_VALUES[$axis,$value_index]}"
    if _pairwise_ok ROW; then
      ASSIGNED[$axis]=$value_index
      _pairwise_extend $((axis + 1)) && return 0
      unset "ASSIGNED[$axis]"
    fi
  done
  unset "ROW[${AXIS_NAMES[axis]}]"
  return 1
}

# _pairwise_row_json — the completed ROW as a compact JSON object, keys in
# axis order (deterministic).
_pairwise_row_json() {
  local -a jq_arguments=()
  local program="{" index name
  for ((index = 0; index < AXIS_COUNT; index++)); do
    name="${AXIS_NAMES[index]}"
    jq_arguments+=(--arg "k$index" "$name" --argjson "v$index" "${ROW[$name]}")
    ((index)) && program+=","
    program+="(\$k$index):\$v$index"
  done
  program+="}"
  jq -c -n "${jq_arguments[@]}" "$program"
}
