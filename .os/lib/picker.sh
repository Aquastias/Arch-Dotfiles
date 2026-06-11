#!/usr/bin/env bash
# =============================================================================
# lib/picker.sh — Pre-Install Picker deep modules
# =============================================================================
# Pure functions consumed by tools/pick.sh. No TTY, no fzf, no side effects
# beyond reading files and writing to stdout/stderr.
#
# Sourced by tools/pick.sh and tests/picker.bats.
# =============================================================================

# shellcheck source=./jsonc.sh
source "${BASH_SOURCE[0]%/*}/jsonc.sh"

# picker_enum_hosts <hosts_dir>
#   Emits, one per line, the names of <hosts_dir>/<name>/ directories that
#   ship an install.template.jsonc. The reserved name `core` is excluded.
#   Output is sorted; missing dir yields empty output.
picker_enum_hosts() {
  local hosts_dir="$1" name entry
  [[ -d "$hosts_dir" ]] || return 0
  {
    for entry in "$hosts_dir"/*/ "$hosts_dir"/vm/*/; do
      [[ -d "$entry" ]] || continue
      name="$(basename "$entry")"
      [[ "$name" == "core" || "$name" == "vm" ]] && continue
      [[ -f "$entry/install.template.jsonc" ]] || continue
      printf '%s\n' "$name"
    done
  } | sort -u
}

# picker_validate_layout <mode> <disk_count>
#   Pure rule check on a mode/topology and the picked disk count. Accepts
#   both the prompt tokens (`single`, `mirror`, `raidz`) and the config
#   topologies a pinned template passes through (`stripe`, `raidz1`,
#   `raidz2`, `none`) — `raidz` is an alias for `raidz1`. Min-disk table
#   per ADR 0029. Returns 0 with empty output on ok; non-zero with a
#   human-readable error on stderr otherwise.
picker_validate_layout() {
  local mode="$1" count="$2" min
  case "$mode" in
    single)
      if (( count != 1 )); then
        echo "single mode requires exactly 1 disk (got $count)" >&2
        return 1
      fi
      return 0
      ;;
    mirror | stripe | none) min=2 ;;
    raidz | raidz1) min=3 ;;
    raidz2) min=4 ;;
    *)
      echo "unknown mode '$mode' (expected: single, mirror, stripe," \
           "raidz, raidz1, raidz2, none)" >&2
      return 1
      ;;
  esac
  if (( count < min )); then
    echo "$mode mode requires at least $min disks (got $count)" >&2
    return 1
  fi
}

# picker_load_template <hosts_dir> <host>
#   Reads <hosts_dir>/core/install.template.jsonc and <hosts_dir>/<host>/
#   install.template.jsonc, returns the merged JSON on stdout. Merge rules
#   match Host Config / Host Core: arrays concat+dedupe, objects deep merge,
#   scalars host-wins.
picker_load_template() {
  local hosts_dir="$1" host="$2"
  local core_file="$hosts_dir/core/install.template.jsonc"
  local host_file="$hosts_dir/$host/install.template.jsonc"
  [[ -f "$host_file" ]] || host_file="$hosts_dir/vm/$host/install.template.jsonc"
  local core_json host_json
  core_json="$(jsonc_strip "$core_file" | jq '.')" || return 1
  host_json="$(jsonc_strip "$host_file" | jq '.')" || return 1
  jq -n --argjson a "$core_json" --argjson b "$host_json" '
    def dedup_keep_first:
      reduce .[] as $x ([]; if any(.[]; . == $x) then . else . + [$x] end);
    def merge(x; y):
      if   (x == null) then y
      elif (y == null) then x
      elif (x | type) == "array"  and (y | type) == "array"
        then ((x + y) | dedup_keep_first)
      elif (x | type) == "object" and (y | type) == "object"
        then reduce ((x + y) | keys_unsorted | unique[]) as $k
          ({}; .[$k] = merge(x[$k]; y[$k]))
      else y
      end;
    merge($a; $b)
  '
}

# picker_enum_disks <live_set>
#   Emits, one per line, sorted /dev/disk/by-id/* paths excluding the live
#   medium whole-disk(s) and their partitions. <live_set> is the Live-Medium
#   Detector's output: zero or more whole-disk paths such as `/dev/sdz`, one
#   per line (empty = no exclusion). PICKER_BY_ID_DIR overrides /dev/disk/by-id
#   for tests.
picker_enum_disks() {
  local live_set="$1"
  local by_id="${PICKER_BY_ID_DIR:-/dev/disk/by-id}"
  [[ -d "$by_id" ]] || return 0

  # Whole-disk kernel bases to exclude (e.g. sdz), one per live-medium disk.
  local live_bases=() d
  while IFS= read -r d; do
    [[ -n "$d" ]] && live_bases+=("$(basename "$d")")
  done <<<"$live_set"

  local link target_base lb skip
  for link in "$by_id"/*; do
    [[ -L "$link" ]] || continue
    target_base="$(basename "$(readlink -f "$link")")"
    skip=""
    if ((${#live_bases[@]})); then
      for lb in "${live_bases[@]}"; do
        if [[ "$target_base" == "$lb" \
              || "$target_base" =~ ^${lb}p?[0-9]+$ ]]; then
          skip=1
          break
        fi
      done
    fi
    [[ -n "$skip" ]] && continue
    printf '%s\n' "$link"
  done | sort
}

# picker_pin_from_template <template_json>
#   Reads an optional layout pin from a merged Install Template (ADR 0029).
#   Pin trigger is `.mode`:
#     absent/null  → unpinned: empty stdout, return 0 (picker prompts).
#     "single"     → prints `single`, return 0.
#     "multi"      → requires `.os_pool.topology`; prints
#                    `multi<TAB><topology>`, return 0. Missing topology is
#                    a template error: message on stderr, return non-zero.
#     anything else → error on stderr, return non-zero.
#   Pure: reads the JSON arg only, never disks (those are always picked).
picker_pin_from_template() {
  local template="$1" mode topology
  mode="$(jq -r '.mode // ""' <<<"$template")" || return 1
  [[ -z "$mode" || "$mode" == "null" ]] && return 0
  case "$mode" in
    single)
      printf '%s\n' single
      ;;
    multi)
      topology="$(jq -r '.os_pool.topology // ""' <<<"$template")"
      if [[ -z "$topology" || "$topology" == "null" ]]; then
        echo "pinned mode=multi requires os_pool.topology in the" \
             "template (ADR 0029)" >&2
        return 1
      fi
      printf '%s\t%s\n' multi "$topology"
      ;;
    *)
      echo "unknown pinned mode '$mode' (expected single or multi)" >&2
      return 1
      ;;
  esac
}

# picker_assemble_config <template_json> <profile> <mode> <disk> [<disk>...]
#   Returns full install.jsonc text on stdout. The template provides every
#   per-machine field. The <profile> arg is the chosen host directory name
#   (the Host Profile). Hostname resolution: template's .system.hostname
#   wins when set, else falls back to <profile>. No host_profile field is
#   written — the directory name is the identity (ADR 0036). Layout fields
#   are written fresh per <mode>:
#     single                       → .mode="single", .disk=<disk>
#     mirror | stripe | raidz1     → .mode="multi", os_pool.topology=<mode>,
#     | raidz2 | none                 os_pool.disks=[<disks>...]
#     raidz (prompt token)         → alias for raidz1
#   The expanded topology vocabulary (stripe/raidz2/none) lets a pinned
#   template pass its os_pool.topology straight through (ADR 0029); the
#   unpinned prompt still only supplies single/mirror/raidz.
picker_assemble_config() {
  local template="$1" profile="$2" mode="$3"
  shift 3
  local disks_json
  disks_json="$(printf '%s\n' "$@" | jq -R . | jq -s .)"
  case "$mode" in
    single)
      jq -n --argjson tpl "$template" \
            --arg profile "$profile" \
            --arg disk "$1" '
        $tpl
        | .system = (.system // {})
        | .system.hostname =
            (if (.system.hostname // "") == ""
             then $profile else .system.hostname end)
        | .mode = "single"
        | .disk = $disk
      '
      ;;
    mirror | stripe | raidz | raidz1 | raidz2 | none)
      local topology
      [[ "$mode" == raidz ]] && topology="raidz1" || topology="$mode"
      jq -n --argjson tpl "$template" \
            --arg profile "$profile" \
            --arg topology "$topology" \
            --argjson disks "$disks_json" '
        $tpl
        | .system = (.system // {})
        | .system.hostname =
            (if (.system.hostname // "") == ""
             then $profile else .system.hostname end)
        | .mode = "multi"
        | .os_pool = (.os_pool // {})
                     + { topology: $topology, disks: $disks }
        | del(.disk)
      '
      ;;
    *)
      echo "picker_assemble_config: unknown mode '$mode'" >&2
      return 1
      ;;
  esac
}

# picker_assign_disks <profile_json> <assignment_json>
#   Maps operator-picked disks onto the pool skeleton declared in a unified
#   Host Profile (os_pool + storage_groups + data_pools, with
#   topology/ashift/owners but NO device fields), producing the effective
#   install config on stdout. Per-group assignment: each declared group gets
#   its own disks, validated against the min-disk table (picker_validate_
#   layout) before any field is written. Pure: reads its JSON args only,
#   never disks.
#
#   Assignment shape:
#     single → {"mode":"single","disk":"/dev/x"}        (exactly one device)
#     multi  → {"mode":"multi",
#               "os_pool":["/dev/a","/dev/b"],
#               "storage_groups":[["/dev/c","/dev/d","/dev/e"]],
#               "data_pools":[["/dev/f"]]}
#   Returns non-zero with a human-readable error on stderr on any
#   under-populated group.
picker_assign_disks() {
  local profile="$1" assignment="$2" mode
  mode="$(jq -r '.mode // "multi"' <<<"$assignment")"

  case "$mode" in
    single)
      local -a disks
      mapfile -t disks < <(jq -r '
        if .disk then .disk elif .os_pool then .os_pool[]? else empty end
      ' <<<"$assignment")
      picker_validate_layout single "${#disks[@]}" || return 1
      jq -n --argjson p "$profile" --arg disk "${disks[0]}" '
        $p | .mode = "single" | .disk = $disk
      '
      ;;
    multi)
      # Validate every declared group's picked-disk count up front (fail fast,
      # naming the offending group), then merge devices into the skeleton.
      local topo i count
      topo="$(jq -r '.os_pool.topology // "stripe"' <<<"$profile")"
      count="$(jq '(.os_pool // []) | length' <<<"$assignment")"
      _picker_validate_group os_pool "$topo" "$count" || return 1

      local n
      n="$(jq '(.storage_groups // []) | length' <<<"$profile")"
      for ((i = 0; i < n; i++)); do
        topo="$(jq -r ".storage_groups[$i].topology // \"stripe\"" \
          <<<"$profile")"
        count="$(jq "(.storage_groups[$i] // []) | length" <<<"$assignment")"
        _picker_validate_group "storage_groups[$i]" "$topo" "$count" \
          || return 1
      done

      n="$(jq '(.data_pools // []) | length' <<<"$profile")"
      for ((i = 0; i < n; i++)); do
        topo="$(jq -r ".data_pools[$i].topology // \"stripe\"" <<<"$profile")"
        count="$(jq "(.data_pools[$i] // []) | length" <<<"$assignment")"
        _picker_validate_group "data_pools[$i]" "$topo" "$count" || return 1
      done

      # All groups valid — write each group's disks into the skeleton by index.
      jq -n --argjson p "$profile" --argjson a "$assignment" '
        def assign($key):
          if (.[$key] | type) == "array"
          then .[$key] = [ .[$key] | to_entries[]
                           | .value + { disks: ($a[$key][.key] // []) } ]
          else . end;
        $p
        | .mode = "multi"
        | .os_pool = (.os_pool // {}) + { disks: ($a.os_pool // []) }
        | assign("storage_groups")
        | assign("data_pools")
      '
      ;;
    *)
      echo "picker_assign_disks: unknown mode '$mode'" >&2
      return 1
      ;;
  esac
}

# _picker_group_min <topology> <count>
#   Assignment-path per-group min-disk check (ADR 0037), distinct from
#   picker_validate_layout (the interactive OS-pool *mode* prompt, where `none`
#   = 1 OS disk + folded leftovers). Aligns with the layout's real min-disk
#   rules: stripe/independent >=1, mirror >=2, raidz1 >=3, raidz2 >=4;
#   none/single = exactly 1 (the single OS disk). Silent + returns 0 on ok;
#   human-readable message on stderr + non-zero otherwise.
_picker_group_min() {
  local topo="$1" count="$2" min
  case "$topo" in
    single | none)
      if (( count != 1 )); then
        echo "$topo requires exactly 1 disk (got $count)" >&2
        return 1
      fi
      return 0
      ;;
    stripe | independent) min=1 ;;
    mirror)               min=2 ;;
    raidz | raidz1)       min=3 ;;
    raidz2)               min=4 ;;
    *)
      echo "unknown topology '$topo' (expected: single, none, stripe," \
           "independent, mirror, raidz, raidz1, raidz2)" >&2
      return 1
      ;;
  esac
  if (( count < min )); then
    echo "$topo requires at least $min disk(s) (got $count)" >&2
    return 1
  fi
}

# _picker_validate_group <label> <topology> <count>
#   Validate one group's disk count against the assignment-path min table
#   (_picker_group_min), prefixing the group label so an under-populated group
#   is named in the error.
_picker_validate_group() {
  local label="$1" topo="$2" count="$3" msg
  if ! msg="$(_picker_group_min "$topo" "$count" 2>&1)"; then
    echo "${label}: ${msg}" >&2
    return 1
  fi
}

# _picker_slice_json <disk...>
#   Emits the args as a JSON array (empty args → []). Guards the printf-with-
#   no-args case that would otherwise yield [""] instead of [].
_picker_slice_json() {
  if (( $# == 0 )); then
    printf '[]\n'
  else
    printf '%s\n' "$@" | jq -R . | jq -s .
  fi
}

# picker_build_assignment <profile_json> <disk...>
#   Slices a flat list of operator-picked disks onto the profile's declared
#   pool groups by each group's disk_count, in declared order (os_pool, then
#   each storage_groups[], then each data_pools[]) — ADR 0037. Emits the
#   per-group assignment JSON consumed by picker_assign_disks. The number of
#   disks must equal sum(disk_count); a mismatch aborts naming the expected
#   total. os_pool topology none/single defaults to disk_count 1 when omitted;
#   every other group must declare disk_count. Pure: reads its args only.
picker_build_assignment() {
  local profile="$1"; shift
  local -a disks=("$@")
  local total=${#disks[@]}

  # Per-group disk_count in declared order — os_pool, storage_groups[],
  # data_pools[]. Validate presence as we go so a missing count names its group.
  local -a counts=()
  local topo dc n i sg_n dp_n

  topo="$(jq -r '.os_pool.topology // "stripe"' <<<"$profile")"
  dc="$(jq -r '.os_pool.disk_count // ""' <<<"$profile")"
  if [[ -z "$dc" ]]; then
    case "$topo" in
      none | single) dc=1 ;;
      *) echo "picker_build_assignment: os_pool ('$topo') needs a disk_count" \
              >&2; return 1 ;;
    esac
  fi
  counts+=("$dc")

  sg_n="$(jq '(.storage_groups // []) | length' <<<"$profile")"
  for ((i = 0; i < sg_n; i++)); do
    dc="$(jq -r ".storage_groups[$i].disk_count // \"\"" <<<"$profile")"
    [[ -n "$dc" ]] \
      || { echo "picker_build_assignment: storage_groups[$i] needs a" \
                "disk_count" >&2; return 1; }
    counts+=("$dc")
  done

  dp_n="$(jq '(.data_pools // []) | length' <<<"$profile")"
  for ((i = 0; i < dp_n; i++)); do
    dc="$(jq -r ".data_pools[$i].disk_count // \"\"" <<<"$profile")"
    [[ -n "$dc" ]] \
      || { echo "picker_build_assignment: data_pools[$i] needs a disk_count" \
                >&2; return 1; }
    counts+=("$dc")
  done

  local sum=0 c
  for c in "${counts[@]}"; do sum=$((sum + c)); done
  if (( total != sum )); then
    echo "picker_build_assignment: expected $sum disk(s) (sum of declared" \
         "disk_count), got $total" >&2
    return 1
  fi

  # Slice the flat list into per-group JSON in the same declared order.
  local off=0
  local os_json sg_json="[]" dp_json="[]" slice
  c="${counts[0]}"
  os_json="$(_picker_slice_json "${disks[@]:off:c}")"
  off=$((off + c))
  for ((i = 0; i < sg_n; i++)); do
    c="${counts[1 + i]}"
    slice="$(_picker_slice_json "${disks[@]:off:c}")"
    sg_json="$(jq --argjson s "$slice" '. + [$s]' <<<"$sg_json")"
    off=$((off + c))
  done
  for ((i = 0; i < dp_n; i++)); do
    c="${counts[1 + sg_n + i]}"
    slice="$(_picker_slice_json "${disks[@]:off:c}")"
    dp_json="$(jq --argjson s "$slice" '. + [$s]' <<<"$dp_json")"
    off=$((off + c))
  done

  jq -n --argjson os "$os_json" --argjson sg "$sg_json" \
        --argjson dp "$dp_json" \
    '{ mode: "multi", os_pool: $os, storage_groups: $sg, data_pools: $dp }'
}

# picker_format_disk_preview <by_id_path>
#   Returns a multi-line preview block for the given /dev/disk/by-id/* path,
#   intended for fzf --preview in the disk picker. Sections:
#     ── Disk ──          lsblk -dno NAME,SIZE,MODEL,SERIAL,TRAN
#     ── SMART ──         smartctl -i (omitted when smartctl -i exits non-zero)
#     ── Partitions ──    lsblk -no NAME,SIZE,FSTYPE,LABEL,PARTLABEL
#   Deterministic given the same inputs; safe for snapshot tests.
picker_format_disk_preview() {
  local by_id="$1" dev
  if [[ ! -e "$by_id" ]]; then
    echo "by-id path not found: $by_id" >&2
    return 1
  fi
  dev="$(readlink -f "$by_id")"
  echo "── Disk ──"
  lsblk -dno NAME,SIZE,MODEL,SERIAL,TRAN "$dev"
  local smart
  if smart="$(smartctl -i "$dev" 2>/dev/null)"; then
    echo
    echo "── SMART ──"
    printf '%s
' "$smart"
  fi
  echo
  echo "── Partitions ──"
  lsblk -no NAME,SIZE,FSTYPE,LABEL,PARTLABEL "$dev"
}


# picker_parse_choice <char>
#   Maps the four-way review-screen keypress to an action keyword on stdout.
#   Unrecognised input → non-zero, no stdout.
#     i → write_install   w → write_only   e → edit   a → abort
picker_parse_choice() {
  case "$1" in
    i) echo write_install ;;
    w) echo write_only ;;
    e) echo edit ;;
    a) echo abort ;;
    *) return 1 ;;
  esac
}

# picker_render_review <jsonc_text> <existing_path>
#   Renders the review block printed before the four-way prompt.
#   When <existing_path> is non-empty and the file exists, prints a unified
#   diff against it (operator-readable, not pretty). Otherwise prints the
#   JSONC text verbatim. Always returns 0 — `diff` exit 1 (differences
#   present) is a successful render, not a failure.
picker_render_review() {
  local jsonc="$1" existing="$2"
  if [[ -n "$existing" && -f "$existing" ]]; then
    diff -u "$existing" <(printf '%s\n' "$jsonc") || true
  else
    printf '%s' "$jsonc"
  fi
}
