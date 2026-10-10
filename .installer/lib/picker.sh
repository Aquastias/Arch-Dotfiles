#!/usr/bin/env bash
# =============================================================================
# lib/picker.sh — Pre-Install Picker deep modules
# =============================================================================
# Pure disk-resolution functions for the `install.sh --profile` front-end and
# the VM harness. No TTY, no fzf, no side effects beyond reading files and
# writing to stdout/stderr.
#
# Sourced by lib/config/profile.sh, install.sh, vm/lib/profile.sh, and
# tests/picker.bats.
# =============================================================================

# shellcheck source=./jsonc.sh
source "${BASH_SOURCE[0]%/*}/jsonc.sh"

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

# _picker_is_partition <kernel-base>
#   rc 0 when the kernel node is a partition (sda1, vdb2, nvme0n1p1, mmcblk0p1,
#   loop0p1) rather than a whole disk — partitions are never install targets.
_picker_is_partition() {
  local kernel_name="$1"
  [[ "$kernel_name" =~ ^(sd|vd|hd|xvd)[a-z]+[0-9]+$ ]] && return 0
  [[ "$kernel_name" =~ ^(nvme[0-9]+n[0-9]+|mmcblk[0-9]+|loop[0-9]+)p[0-9]+$ ]] \
    && return 0
  return 1
}

# _picker_alias_rank <by-id-name>
#   Preference for the canonical alias when one physical disk carries several
#   by-id names; lower wins. A readable model+serial name (ata-/nvme-/scsi-/
#   mmc-/usb-) beats the opaque globally-unique ids (wwn-/nvme-eui.). The
#   nvme-eui. case is listed before nvme- so it isn't caught by the readable arm.
_picker_alias_rank() {
  case "$1" in
    nvme-eui.*)                      echo 3 ;;
    wwn-*)                           echo 2 ;;
    ata-*|nvme-*|scsi-*|mmc-*|usb-*) echo 0 ;;
    *)                               echo 1 ;;
  esac
}

# picker_enum_disks <live_set>
#   Emits, one per line, sorted /dev/disk/by-id/* paths — ONE canonical link per
#   physical disk. Partition links (…-partN) and partition kernel nodes are
#   dropped, and the many by-id aliases of a single disk (ata-/wwn-/nvme-eui.)
#   collapse to the most readable one, so the operator sees each disk exactly
#   once. <live_set> is the Live-Medium Detector's output: zero or more
#   whole-disk paths such as `/dev/sdz`, one per line (empty = no exclusion).
#   PICKER_BY_ID_DIR overrides /dev/disk/by-id for tests.
picker_enum_disks() {
  local live_set="$1"
  local by_id="${PICKER_BY_ID_DIR:-/dev/disk/by-id}"
  [[ -d "$by_id" ]] || return 0

  # Whole-disk kernel bases to exclude (e.g. sdz), one per live-medium disk.
  local live_bases=() live_disk
  while IFS= read -r live_disk; do
    [[ -n "$live_disk" ]] && live_bases+=("${live_disk##*/}")
  done <<<"$live_set"

  # Keep the best (lowest-rank) alias per resolved kernel base; ties break on the
  # lexically smaller name so the choice is deterministic.
  local link name target_base live_base skip rank
  local -A best=() best_rank=()
  for link in "$by_id"/*; do
    [[ -L "$link" ]] || continue
    name="${link##*/}"
    # Partition aliases carry a -partN suffix (udev convention) — never a disk.
    [[ "$name" =~ -part[0-9]+$ ]] && continue
    target_base="$(readlink -f "$link")"; target_base="${target_base##*/}"
    _picker_is_partition "$target_base" && continue

    skip=""
    for live_base in "${live_bases[@]}"; do
      [[ "$target_base" == "$live_base" ]] && { skip=1; break; }
    done
    [[ -n "$skip" ]] && continue

    rank="$(_picker_alias_rank "$name")"
    if [[ -z "${best[$target_base]:-}" ]] \
       || (( rank < best_rank[$target_base] )) \
       || { (( rank == best_rank[$target_base] )) \
            && [[ "$name" < "${best[$target_base]##*/}" ]]; }; then
      best[$target_base]="$link"
      best_rank[$target_base]="$rank"
    fi
  done

  local kernel_base
  for kernel_base in "${!best[@]}"; do
    printf '%s\n' "${best[$kernel_base]}"
  done | sort
}

# picker_disk_label <by-id-path>
#   A compact one-line label led by the kernel name the operator recognises:
#   "/dev/sda <size> <model> · <tail>" when lsblk can read the disk,
#   "/dev/sda · <tail>" when only the kernel node resolves, else just the by-id
#   <tail>. The by-id tail is always the segment after the last " · " so callers
#   can parse the stable key back out of the label.
picker_disk_label() {
  local by_id_path="$1" tail dev size_and_model
  tail="${by_id_path##*/}"
  dev="$(readlink -f "$by_id_path" 2>/dev/null)"
  [[ "$dev" == /dev/* ]] || dev=""
  if [[ -n "$dev" ]] \
     && size_and_model="$(lsblk -dno SIZE,MODEL "$dev" 2>/dev/null \
                          | awk 'NR == 1')" \
     && [[ -n "${size_and_model//[[:space:]]/}" ]]; then
    printf '%s %s · %s' "$dev" \
      "$(awk '{ gsub(/ +/, " "); print }' <<<"$size_and_model")" "$tail"
  elif [[ -n "$dev" ]]; then
    printf '%s · %s' "$dev" "$tail"
  else
    printf '%s' "$tail"
  fi
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
    single) _picker_assign_single "$profile" "$assignment" ;;
    multi)
      # Validate every declared group's picked-disk count up front (fail fast,
      # naming the offending group), then merge devices into the skeleton.
      _picker_validate_all_groups "$profile" "$assignment" || return 1
      _picker_merge_multi "$profile" "$assignment"
      ;;
    *)
      echo "picker_assign_disks: unknown mode '$mode'" >&2
      return 1
      ;;
  esac
}

_picker_assign_single() {
  local profile="$1" assignment="$2"
  local -a disks
  mapfile -t disks < <(jq -r '
    if .disk then .disk elif .os_pool then .os_pool[]? else empty end
  ' <<<"$assignment")
  picker_validate_layout single "${#disks[@]}" || return 1
  jq -n --argjson profile "$profile" --arg disk "${disks[0]}" '
    $profile | .mode = "single" | .disk = $disk
  '
}

_picker_validate_all_groups() {
  local profile="$1" assignment="$2" topology count
  topology="$(jq -r '.os_pool.topology // "stripe"' <<<"$profile")"
  count="$(jq '(.os_pool // []) | length' <<<"$assignment")"
  _picker_validate_group os_pool "$topology" "$count" || return 1
  _picker_validate_group_list storage_groups "$profile" "$assignment" \
    || return 1
  _picker_validate_group_list data_pools "$profile" "$assignment"
}

# _picker_validate_group_list <key> <profile> <assignment> — every group of
# the profile's <key> array against its picked-disk count.
_picker_validate_group_list() {
  local key="$1" profile="$2" assignment="$3" group_count i topology count
  group_count="$(jq --arg key "$key" '(.[$key] // []) | length' <<<"$profile")"
  for ((i = 0; i < group_count; i++)); do
    topology="$(jq -r ".${key}[$i].topology // \"stripe\"" <<<"$profile")"
    count="$(jq "(.${key}[$i] // []) | length" <<<"$assignment")"
    _picker_validate_group "${key}[$i]" "$topology" "$count" || return 1
  done
}

# All groups valid — write each group's disks into the skeleton by index.
_picker_merge_multi() {
  jq -n --argjson profile "$1" --argjson assignment "$2" '
    def assign($key):
      if (.[$key] | type) == "array"
      then .[$key] = [ .[$key] | to_entries[]
                       | .value + { disks: ($assignment[$key][.key] // []) } ]
      else . end;
    $profile
    | .mode = "multi"
    | .os_pool = (.os_pool // {}) + { disks: ($assignment.os_pool // []) }
    | assign("storage_groups")
    | assign("data_pools")
  '
}

# _picker_group_min <topology> <count>
#   Assignment-path per-group min-disk check (ADR 0037), distinct from
#   picker_validate_layout (the interactive OS-pool *mode* prompt, where `none`
#   = 1 OS disk + folded leftovers). Aligns with the layout's real min-disk
#   rules: stripe/independent >=1, mirror >=2, raidz1 >=3, raidz2 >=4;
#   none/single = exactly 1 (the single OS disk). Silent + returns 0 on ok;
#   human-readable message on stderr + non-zero otherwise.
_picker_group_min() {
  local topology="$1" count="$2" min
  case "$topology" in
    single | none)
      if (( count != 1 )); then
        echo "$topology requires exactly 1 disk (got $count)" >&2
        return 1
      fi
      return 0
      ;;
    stripe | independent) min=1 ;;
    mirror)               min=2 ;;
    raidz | raidz1)       min=3 ;;
    raidz2)               min=4 ;;
    # btrfs native profiles (ADR 0043) — a non-zfs data pool's topology;
    # validation.sh gates which filesystem may use which. raid0/raid1 ≥2,
    # raid10 ≥4 (btrfs single rides the single=1 case above).
    raid0 | raid1)        min=2 ;;
    raid10)               min=4 ;;
    *)
      echo "unknown topology '$topology' (expected: single, none, stripe," \
           "independent, mirror, raidz, raidz1, raidz2, raid0, raid1," \
           "raid10)" >&2
      return 1
      ;;
  esac
  if (( count < min )); then
    echo "$topology requires at least $min disk(s) (got $count)" >&2
    return 1
  fi
}

# _picker_validate_group <label> <topology> <count>
#   Validate one group's disk count against the assignment-path min table
#   (_picker_group_min), prefixing the group label so an under-populated group
#   is named in the error.
_picker_validate_group() {
  local label="$1" topology="$2" count="$3" message
  if ! message="$(_picker_group_min "$topology" "$count" 2>&1)"; then
    echo "${label}: ${message}" >&2
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
  local -a disks=("$@") counts=()
  local counts_text storage_group_count data_pool_count
  counts_text="$(_picker_declared_disk_counts "$profile")" || return 1
  mapfile -t counts <<<"$counts_text"
  _picker_check_disk_total "${#disks[@]}" "${counts[@]}" || return 1
  storage_group_count="$(jq '(.storage_groups // []) | length' <<<"$profile")"
  data_pool_count="$(jq '(.data_pools // []) | length' <<<"$profile")"

  # Slice the flat list into per-group JSON in the same declared order.
  local offset=0 os_json storage_json="[]" data_json="[]" slice i count
  count="${counts[0]}"
  os_json="$(_picker_slice_json "${disks[@]:offset:count}")"
  offset=$((offset + count))
  for ((i = 0; i < storage_group_count; i++)); do
    count="${counts[1 + i]}"
    slice="$(_picker_slice_json "${disks[@]:offset:count}")"
    storage_json="$(jq --argjson s "$slice" '. + [$s]' <<<"$storage_json")"
    offset=$((offset + count))
  done
  for ((i = 0; i < data_pool_count; i++)); do
    count="${counts[1 + storage_group_count + i]}"
    slice="$(_picker_slice_json "${disks[@]:offset:count}")"
    data_json="$(jq --argjson s "$slice" '. + [$s]' <<<"$data_json")"
    offset=$((offset + count))
  done

  jq -n --argjson os "$os_json" --argjson storage "$storage_json" \
        --argjson data "$data_json" \
    '{ mode: "multi", os_pool: $os, storage_groups: $storage,
       data_pools: $data }'
}

# _picker_declared_disk_counts <profile> — each group's disk_count, one per
# line, in declared order: os_pool, storage_groups[], data_pools[]. A missing
# count aborts naming its group; os_pool topology none/single defaults to 1.
_picker_declared_disk_counts() {
  local profile="$1" topology disk_count
  topology="$(jq -r '.os_pool.topology // "stripe"' <<<"$profile")"
  disk_count="$(jq -r '.os_pool.disk_count // ""' <<<"$profile")"
  if [[ -z "$disk_count" ]]; then
    case "$topology" in
      none | single) disk_count=1 ;;
      *) echo "picker_build_assignment: os_pool ('$topology') needs a" \
              "disk_count" >&2; return 1 ;;
    esac
  fi
  echo "$disk_count"
  _picker_group_disk_counts storage_groups "$profile" || return 1
  _picker_group_disk_counts data_pools "$profile"
}

_picker_group_disk_counts() {
  local key="$1" profile="$2" group_count i disk_count
  group_count="$(jq --arg key "$key" '(.[$key] // []) | length' <<<"$profile")"
  for ((i = 0; i < group_count; i++)); do
    disk_count="$(jq -r ".${key}[$i].disk_count // \"\"" <<<"$profile")"
    [[ -n "$disk_count" ]] \
      || { echo "picker_build_assignment: ${key}[$i] needs a disk_count" >&2
           return 1; }
    echo "$disk_count"
  done
}

# _picker_check_disk_total <picked> <count>... — the picked disks must equal
# the sum of the declared disk_counts.
_picker_check_disk_total() {
  local picked="$1" sum=0 count; shift
  for count in "$@"; do sum=$((sum + count)); done
  if (( picked != sum )); then
    echo "picker_build_assignment: expected $sum disk(s) (sum of declared" \
         "disk_count), got $picked" >&2
    return 1
  fi
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


