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
#   Pure rule check. Slice 1 supports only `single`, which requires exactly
#   one disk. Returns 0 with empty output on ok; non-zero with a
#   human-readable error on stderr+stdout otherwise.
picker_validate_layout() {
  local mode="$1" count="$2"
  case "$mode" in
    single)
      if (( count != 1 )); then
        echo "single mode requires exactly 1 disk (got $count)" >&2
        return 1
      fi
      ;;
    *)
      echo "unknown mode '$mode' (expected: single)" >&2
      return 1
      ;;
  esac
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

# picker_enum_disks <live_dev>
#   Emits, one per line, sorted /dev/disk/by-id/* paths excluding the live
#   medium whole-disk and its partitions. <live_dev> is a whole-disk path
#   such as `/dev/sdz` (empty string = no exclusion).
#   PICKER_BY_ID_DIR overrides /dev/disk/by-id for tests.
picker_enum_disks() {
  local live_dev="$1"
  local by_id="${PICKER_BY_ID_DIR:-/dev/disk/by-id}"
  [[ -d "$by_id" ]] || return 0

  local live_base=""
  [[ -n "$live_dev" ]] && live_base="$(basename "$live_dev")"

  local link target_base
  for link in "$by_id"/*; do
    [[ -L "$link" ]] || continue
    target_base="$(basename "$(readlink -f "$link")")"
    if [[ -n "$live_base" ]]; then
      [[ "$target_base" == "$live_base" ]] && continue
      [[ "$target_base" =~ ^${live_base}p?[0-9]+$ ]] && continue
    fi
    printf '%s\n' "$link"
  done | sort
}

# picker_assemble_config <template_json> <hostname> <mode> <disk> [<disk>...]
#   Returns full install.jsonc text on stdout. The template provides every
#   per-machine field; hostname overrides .system.hostname; layout fields
#   (.mode, .disk for single) are written fresh.
picker_assemble_config() {
  local template="$1" hostname="$2" mode="$3"
  shift 3
  local disk="$1"
  jq -n --argjson tpl "$template" \
        --arg hostname "$hostname" \
        --arg mode "$mode" \
        --arg disk "$disk" '
    $tpl
    | .system.hostname = $hostname
    | .mode = $mode
    | .disk = $disk
  '
}
