#!/usr/bin/env bash
# =============================================================================
# lib/guided/controller-screen-data.sh — packages, disks, user panel, profile tree data
# =============================================================================
# Part of the guided controller (lib/guided/controller.sh, ADR 0042).
#
# Used by: lib/guided/controller.sh (sources it).
# =============================================================================

# ── Packages screen helpers (ADR 0058) ───────────────────────────────────────
# Provenance is three-state, reusing the existing override dot rather than
# inventing glyphs, and is measured against the SESSION BASELINE — Host Core
# for a blank session, the picked profile after a pick (ADR 0157):
#   checked, no dot   — inherited from the baseline
#   checked, with dot — added this session
#   unchecked, with dot — excluded this session
#
# The toggle list can only offer the DECLARED UNION across the baseline and the
# session: the universe of Arch packages is not enumerable, so adding a
# brand-new package stays a free-text entry (the `+ Add package` row).

# _controller_package_union <effective> <slot> <cat> — the package names
# offerable in one category: everything the effective view carries plus
# everything the baseline declares there plus anything currently excluded (so
# it can be re-checked).
# The jq programs held in single-quoted variables use jq's $names.
# shellcheck disable=SC2016

_controller_package_union() {
  local effective="$1" slot="$2" cat="$3" baseline
  baseline="$(_controller_baseline)"
  jq -r -n --argjson e "$effective" --argjson b "$baseline" \
    --arg s "$slot" --arg k "$cat" \
    -f "${BASH_SOURCE[0]%/*}/controller-package-union.jq"
}

# _controller_package_categories <effective> <slot> — the categories to list,
# unioned across the effective view and the baseline so a baseline-only
# category still shows.
_controller_package_categories() {
  local effective="$1" slot="$2" baseline
  local categories='($e.packages[$s] // {}) + ($b.packages[$s] // {})'
  categories+=' | keys | .[]'
  baseline="$(_controller_baseline)"
  # The category names of both configs' slot, sorted, each once.
  jq -r -n --argjson e "$effective" --argjson b "$baseline" --arg s "$slot" \
    "$categories"
}

# _controller_package_slot_count <effective> <slot> — how many packages the slot
# resolves to right now (post-exclusion), for the category row summary.
_controller_package_slot_count() {
  local slot_count='[(.packages[$s] // {})[] | select(type == "array")'
  slot_count+=' | .[]]'
  slot_count+=' | unique | length'
  # The number of distinct packages across the slot's category lists.
  printf '%s\n' "$1" | jq -r --arg s "$2" "$slot_count"
}

# _controller_package_excluded <state> <pkg> — rc 0 when <pkg> is in
# packages.exclude.
_controller_package_excluded() {
  # The package's position in the exclude list (null when absent).
  printf '%s\n' "$1" \
    | jq -e --arg p "$2" '(.packages.exclude // []) | index($p)' >/dev/null 2>&1
}

# _controller_package_in_baseline <slot> <cat> <pkg> — rc 0 when the session
# baseline declares it there.
_controller_package_in_baseline() {
  # The package's position in the baseline's category (null when absent).
  _controller_baseline | jq -e --arg s "$1" --arg k "$2" --arg p "$3" \
    '(.packages[$s][$k] // []) | index($p)' >/dev/null 2>&1
}

# _controller_package_derived <effective> — the Package Resolver's derived rows
# for this config (TSV: source, layer, package). The SAME resolver the CLI
# inspector calls, so the menu's derived section and `explain-packages` cannot
# drift.
_controller_package_derived() {
  local source_name layer package
  while IFS=$'\t' read -r source_name layer package; do
    if [[ "$layer" == derived ]]; then
      printf '%s\t%s\t%s\n' "$source_name" "$layer" "$package"
    fi
  done < <(package_resolver_resolve "$1" 2>/dev/null)
}

# _controller_derived_packages_of <rows> <source> — the packages <source>
# derives, each once, from _controller_package_derived's rows.
_controller_derived_packages_of() {
  local source_name layer package
  while IFS=$'\t' read -r source_name layer package; do
    if [[ "$source_name" == "$2" ]]; then printf '%s\n' "$package"; fi
  done < <(printf '%s\n' "$1") | sort -u
}

# _controller_package_derived_total <effective> — unique derived package count.
_controller_package_derived_total() {
  local names total
  # The derived package names, each once.
  names="$(_controller_package_derived "$1" | cut -f3 | sort -u)"
  total="$(printf '%s\n' "$names" | grep -c .)"
  printf '%s' "${total:-0}"
}

# _controller_package_derived_names <effective> — the sorted-unique derived
# package names, cached across a browser session (ADR 0086). Resolving is
# expensive and the set does not change while extras are toggled, so the cache
# is keyed by the config with the browse-add buckets stripped: an add hits it, a
# derivation change (GPU/DE/kernel/…) misses and recomputes. Falls back to a
# live resolve when no cache file is wired (tests, non-menu callers).
_controller_package_derived_names() {
  local effective="$1" key cache_file names unbrowsed
  cache_file="${GUIDED_PKGDERIV_FILE:-}"
  local without_added='del(.packages.repo.extra, .packages.aur.extra)'
  # The config without the browse-add buckets.
  unbrowsed="$(printf '%s\n' "$effective" | jq -c "$without_added")"
  # The cache key: that config's checksum.
  key="$(printf '%s\n' "$unbrowsed" | cksum | cut -d' ' -f1)"
  if [[ -n "$cache_file" && -s "$cache_file" \
        && "$(head -n 1 "$cache_file" 2>/dev/null)" == "$key" ]]; then
    # The cached names, after the key line.
    tail -n +2 "$cache_file"; return 0
  fi
  # The derived package names, each once.
  names="$(_controller_package_derived "$effective" | cut -f3 | sort -u)"
  [[ -n "$cache_file" ]] \
    && { printf '%s\n' "$key"; printf '%s' "$names"; } >"$cache_file"
  printf '%s\n' "$names"
}

# _controller_aur_list — every AUR package name for the browser (ADR 0086). AUR
# has no local DB and no helper at menu time, so the names come from the
# published packages.gz. Lazy + session-cached: filled on first open, reused
# after; a failed/offline fetch yields nothing (the render then shows the
# type-to-add notice). Bounded curl so offline does not hang the menu. Network
# path is UNVERIFIED by bats; tests seed GUIDED_AURLIST_FILE to exercise the
# cache read.
_controller_aur_list() {
  local list_file="${GUIDED_AURLIST_FILE:-}" list
  if [[ -n "$list_file" \
    && -s "$list_file" ]]; then cat "$list_file"; return 0; fi
  # Every AUR package name: the published list, unpacked, comments dropped.
  list="$(curl -fsSL --connect-timeout 2 --max-time 8 \
    https://aur.archlinux.org/packages.gz 2>/dev/null \
    | gunzip 2>/dev/null | grep -v '^#')"
  if [[ -n "$list" ]]; then
    [[ -n "$list_file" ]] && printf '%s\n' "$list" >"$list_file"
    printf '%s\n' "$list"
  fi
}

# _controller_aur_preview <pkg> — the browser's preview for an AUR row: the RPC
# info (ADR 0086), formatted, cached one file per package under
# GUIDED_AURINFO_DIR so re-hovering never re-hits the network. Only a good fetch
# is cached, so a transient timeout retries next hover. curl -g keeps the
# literal arg[] query.
_controller_aur_preview() {
  local package="$1" cache_directory="${GUIDED_AURINFO_DIR:-}" cache_file
  local json out=""
  if [[ -n "$cache_directory" ]]; then
    # One cache file per package; a / in the name becomes _.
    cache_file="$cache_directory/$(printf '%s' "$package" | tr / _)"
    [[ -s "$cache_file" ]] && { cat "$cache_file"; return 0; }
  fi
  json="$(curl -fsSL -g --connect-timeout 2 --max-time 2 \
    "https://aur.archlinux.org/rpc/v5/info?arg[]=${package}" 2>/dev/null)"
  if [[ -n "$json" ]]; then
    out="$(printf '%s\n' "$json" \
      | jq -r -f "${BASH_SOURCE[0]%/*}/controller-aur-info.jq" 2>/dev/null)"
  fi
  if [[ -n "$out" ]]; then
    [[ -n "$cache_directory" ]] && printf '%s\n' "$out" >"$cache_file"
    printf '%s\n' "$out"
  else
    printf '%s\n' "(no AUR info — offline, timed out, or not found)"
  fi
}

# The source → driving-category mapping lives with the source table in
# package-resolver.sh (package_resolver_source_origin), so a new derived source
# cannot render here with a missing origin.

# _controller_bound_disks <state> — every by-id path already bound to ANY group
# (os + storage + data pools, plus the single-disk root), one per line, so a
# disk lives in exactly one place ("disappears everywhere" — ADR 0047).
_controller_bound_disks() {
  local bound='(.os_pool.devices // [])[],'
  bound+=' ((.storage_groups // [])[].devices // [])[],'
  bound+=' ((.data_pools // [])[].devices // [])[],'
  bound+=' (.root_disk // empty)'
  # Each pool's bound devices, then the root disk.
  printf '%s\n' "$1" | jq -r "$bound"
}

# _controller_free_disks <state> — the Free Set: enumerated candidates (live
# medium excluded) minus every already-bound disk, one per line.
_controller_free_disks() {
  local -A is_bound=()
  local disk
  while IFS= read -r disk; do
    [[ -n "$disk" ]] && is_bound["$disk"]=1
  done < <(_controller_bound_disks "$1")
  while IFS= read -r disk; do
    [[ -n "${is_bound["$disk"]:-}" ]] || printf '%s\n' "$disk"
  done < <(picker_enum_disks "$(_controller_live_set)")
}

# _controller_disk_label <by-id-path> — the disk row label; delegates to the
# shared picker_disk_label ("/dev/sda <size> <model> · <tail>", tail parseable
# back out).
_controller_disk_label() { picker_disk_label "$1"; }

# _controller_pool_toggle_disk <group> <by-id-path> — flip the disk's membership
# in the group's devices[], then re-derive disk_count as the number bound.
_controller_pool_toggle_disk() {
  local group="$1" disk="$2" devices
  local toggled='(.devices // []) | if index($d)'
  toggled+=' then . - [$d] else . + [$d] end'
  local with_devices='.devices = $new | .disk_count = ($new | length)'
  # The group's devices, the disk removed when bound and added when not.
  devices="$(printf '%s\n' "$group" | jq -c --arg d "$disk" "$toggled")"
  # The group with those devices and their count.
  printf '%s\n' "$group" | jq -c --argjson new "$devices" "$with_devices"
}

# _controller_disks_row <group-json> <count-editable 0|1> — the pooledit
# "disks:" row. Device-mode shows the bound count and opens the sub-screen;
# count-mode shows the 1-8 cycle when editable (OS pool, data pool, storage
# group) or a plain count when not.
_controller_disks_row() {
  local pool="$1" editable="$2" bound count
  # The number of bound devices, and the declared disk count ("?" if unset).
  bound="$(printf '%s\n' "$pool" | jq -r '(.devices // []) | length')"
  count="$(printf '%s\n' "$pool" | jq -r '.disk_count // "?"')"
  if _controller_device_mode; then
    printf 'disks: %s bound   (Enter to edit)\n' "$bound"
  elif [[ "$editable" == "1" ]]; then
    printf 'disks: %s   (Enter cycles 1-8)\n' "$count"
  else
    printf 'disks: %s\n' "$count"
  fi
}

# _controller_user_panel <name> — the hovered user's detail panel (ADR 0063):
# the effective (committed-core-merged, session-override-applied) User Profile a
# session-created user shows its in-progress editor-form state, since
# _controller_user_effective folds the userforms file. Pure over the effective
# view.
_controller_user_panel() {
  local user="$1" effective shell sudo groups programs git_name git_email keys
  effective="$(_controller_user_effective "$user")"
  local sudo_onoff='if .sudo then "on" else "off" end'
  local groups_text='(.groups // []) | join(", ")'
  local programs_text='(.programs // [])'
  programs_text+=' | if length == 0 then ""'
  programs_text+=' else "\(length) · \(join(", "))" end'
  # The panel's values, each with its default.
  shell="$(printf '%s\n' "$effective" | jq -r '.shell // "/bin/zsh"')"
  sudo="$(printf '%s\n' "$effective" | jq -r "$sudo_onoff")"
  groups="$(printf '%s\n' "$effective" | jq -r "$groups_text")"
  programs="$(printf '%s\n' "$effective" | jq -r "$programs_text")"
  git_name="$(printf '%s\n' "$effective" | jq -r '.git.name // ""')"
  git_email="$(printf '%s\n' "$effective" | jq -r '.git.email // ""')"
  keys="$(printf '%s\n' "$effective" \
    | jq -r '(.ssh_authorized_keys // []) | length')"
  printf '%s\n' "$user"
  printf '  shell:    %s\n' "$shell"
  printf '  sudo:     %s\n' "$sudo"
  printf '  groups:   %s\n' "${groups:-(none)}"
  printf '  programs: %s\n' "${programs:-(none)}"
  [[ -n "$git_name" || -n "$git_email" ]] \
    && printf '  git:      %s <%s>\n' "$git_name" "$git_email"
  printf '  ssh keys: %s\n' "$keys"
}


# _controller_profile_tree <resolved-profile-json> — a deep ASCII tree of a
# machine for the Profiles preview (ADR 0063): hostname; users expanded to
# shell·groups; options (kernel, bootloader, encryption, impermanence, swap,
# ssh); environment (desktop/gpu); security; backup; and the disk skeleton
# (reusing the layout graph). Input is the RESOLVED profile (merged over Host
# Core) so it shows what selecting it installs, not the raw on-disk delta. Uses
# the same ▸ / └─ tree style as _controller_layout_graph so previews feel
# consistent.
_controller_profile_tree() {
  local profile="$1" user user_profile shell groups defaults any_zfs
  # The host name.
  printf '%s\n' "$profile" \
    | jq -r '.system.hostname // "(unnamed host)"'  # raw-config-ok
  printf '  ▸ users\n'
  while IFS= read -r user; do
    [[ -n "$user" ]] || continue
    user_profile="$(profile_loader_load_user "$user" 2>/dev/null \
      || printf '{}')"
    [[ -n "$user_profile" ]] || user_profile='{}'
    # The user's shell and groups.
    shell="$(printf '%s\n' "$user_profile" | jq -r '.shell // "/bin/zsh"')"
    groups="$(printf '%s\n' "$user_profile" \
      | jq -r '(.groups // []) | join(", ")')"
    printf '      └─ %s  (%s · %s)\n' "$user" "$shell" "${groups:--}"
  # The profile's users, one per line.
  done < <(printf '%s\n' "$profile" | jq -r '(.users // [])[]')
  defaults="$(install_config_default_object kernels bootloader swap_size gpu)"
  any_zfs="$(install_config_from_json "$profile" any_zfs)"
  printf '%s\n' "$profile" \
    | jq -r --argjson defaults "$defaults" --argjson any_zfs "$any_zfs" \
      -f "${BASH_SOURCE[0]%/*}/controller-profile-tree.jq"
  printf '  ▸ disks\n'
  _controller_layout_graph "$profile" | _controller_tree_indent
}

# _controller_tree_indent — stdin's lines, each indented under a tree branch.
_controller_tree_indent() {
  local line
  while IFS= read -r line; do printf '      %s\n' "$line"; done
}
