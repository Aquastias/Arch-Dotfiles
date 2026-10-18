#!/usr/bin/env bash
# =============================================================================
# lib/guided/controller-list.sh — list rendering (fzf reload)
# =============================================================================
# Part of the guided controller (lib/guided/controller.sh, ADR 0042).
#
# Used by: lib/guided/controller.sh (sources it).
# =============================================================================

# ── list rendering (for fzf reload) ──────────────────────────────────────────
# guided_controller_list — the current screen's item list on stdout.
guided_controller_list() {
  _controller_autocommit \
      # snapshot any edit for undo/redo (single choke point)
  local navigation state base screen
  navigation="$(_controller_navigation)"; state="$(_controller_state)"; \
    base="$(_controller_baseline)"
  screen="$(navigation_screen "$navigation")"
  case "$screen" in
  top) _controller_list_top ;;
  profiles) _controller_list_profiles ;;
  newhost) _controller_list_new_host ;;
  category) _controller_list_category ;;
  pkgcat) _controller_list_package_category ;;
  pkgs) _controller_list_packages ;;
  pkgbrowse) _controller_list_package_browse ;;
  pkgderived) _controller_list_package_derived ;;
  pkgderivedsrc) _controller_list_package_derived_source ;;
  values) _controller_list_values ;;
  text) _controller_list_text ;;
  swapedit) _controller_list_swap_edit ;;
  manualparts) _controller_list_manual_partitions ;;
  partedit) _controller_list_partition_edit ;;
  encryption) _controller_list_encryption ;;
  impermanence) _controller_list_impermanence ;;
  datapools) _controller_list_data_pools ;;
  pooledit) _controller_list_pool_edit ;;
  pooldisks) _controller_list_pool_disks ;;
  rootdisk) _controller_list_root_disk ;;
  rooteditor) _controller_list_root_editor ;;
  useredit) _controller_list_user_edit ;;
  userfield) _controller_list_user_field ;;
  secret) _controller_list_secret ;;
  esac
}

# _controller_list_top — the `top` screen's rows (reads the
# caller's navigation/state/base).
_controller_list_top() {
  # Profiles picker (ADR 0055/0063): a `Profiles ▸` row leads the screen, set
  # off by its own divider above the categories. Unconditional now — even a
  # fresh repo with no committed profiles shows it, because the picker leads
  # with `+ New host (start blank)`, so it is always a first-class entry.
  printf '%s\n' "Profiles ▸ start from a saved machine"
  printf '%s\n' "$_CONTROLLER_DIVIDER"
  # Secrets are never a gate (ADR 0055): root, every user, and the encryption
  # passphrase default to 12345, so Proceed always installs. The per-secret
  # source is surfaced (default 12345 / custom / from age) on the Users
  # screen,
  # not as a top-row block. Save/Export are likewise never gated.
  # A blank spacer below the Profiles divider, right above the first category —
  # an inert row for a clear gap between the rule and the categories.
  printf '\n'
  menu_top_lines "$state" "$base"
  # A blank spacer sets the terminal-action block off from the categories —
  # an inert row (skipped like the inter-bucket spacers), so a clear gap sits
  # above the Proceed / Save / Export / Abort divider.
  printf '\n'
  printf '%s\n' "$_CONTROLLER_DIVIDER"
  printf '%s\n' "Proceed ▸ review & install"
  # Manual Partitioning is Proceed-only (ADR 0073): a hand-drawn partition
  # table cannot be replayed from a committed file, so Save and Export are
  # withheld while it is active.
  if ! manual_partition_kind_active "$state"; then
    printf '%s\n' \
      "Save profile ▸ write a device-less profile" \
      "Export config ▸ write a device-baked config"
  fi
  # Abort is always available (Esc-equivalent): a pre-destructive clean exit
  # so install.sh skips the back-end. Unconditional, unlike Save/Export which
  # are withheld under Manual Partitioning (ADR 0077).
  printf '%s\n' "Abort ▸ quit without installing"
}

# _controller_list_profiles — the `profiles` screen's rows (reads the
# caller's navigation/state/base).
_controller_list_profiles() {
  # The picker leads with `↺ Reset to blank` (a confirm-gated full session
  # reset, ADR 0063), then the installable Host Profiles (ADR 0055) one row
  # each, then Back. The deep profile tree previews in the pane; picking a
  # profile seeds the menu. On a fresh repo only the reset row + Back show — a
  # consistent entry point.
  printf '%s\n' "↺ Reset to blank"
  profiles_list "$(_controller_hosts_root)"
  _controller_action_row "← Back"
}

# _controller_list_new_host — the `newhost` screen's rows (reads the
# caller's navigation/state/base).
_controller_list_new_host() {
  # The `+ New host` confirmation (ADR 0063): a full session reset discards
  # ALL session work, so it is confirm-gated. Enter on the confirm row resets;
  # Back cancels. Broader than Reset-all (which clears Config State only).
  printf '%s\n' "Yes — discard session work and start blank"
  _controller_action_row "← Back"
}

# _controller_list_category — the `category` screen's rows (reads the
# caller's navigation/state/base).
_controller_list_category() {
  local category; category="$(navigation_get "$navigation" category)"
  # Live ESP budget warning (ADR 0078): surfaced on the Kernels + Disks
  # screens where kernels / esp_size are picked, not only at Proceed.
  if [[ "$category" == "Disks" || "$category" == "Kernels" ]]; then
    _controller_esp_budget_warn "$(_controller_effective "$state" "$base")"
  fi
  [[ "$category" == "Disks" ]] && _controller_list_disk_rows
  [[ "$category" == "Packages" ]] && _controller_list_package_slot_rows
  _controller_list_field_rows "$category"
  _controller_action_row "← Back"
}

# _controller_list_disk_rows — Disks leads with the layout row (the headline
# storage choice), then fields.
_controller_list_disk_rows() {
  if manual_partition_kind_active "$state"; then
    # Manual Partitioning (ADR 0073): the pool layout / root-disk / swap rows
    # are replaced by a single Partitions row that launches cfdisk and shows
    # how many partitions the operator has assigned so far.
    local partition_count
    partition_count="$(jq '(.disk_config.partitions // []) | length' \
      <<<"$state")"
    printf 'Partitions ▸ %s assigned (run cfdisk)\n' "$partition_count"
    return 0
  fi
  local effective override_mark=""
  effective="$(_controller_effective "$state" "$base")"
  jq -e '.os_pool or .mode or .storage_groups or .data_pools' \
    <<<"$state" >/dev/null 2>&1 && override_mark="  ●"
  printf '%s: %s%s\n' "$(display_label layout)" \
    "$(_controller_layout_label "$effective")" "$override_mark"
  # Single-disk root binds in-menu on-target: a device-mode single-disk
  # layout gets a root disk row (ADR 0047). Multi layouts bind per pool;
  # off-target (count-mode) the single disk is resolved post-menu as before.
  if _controller_device_mode \
    && [[ "$(jq -r '.mode // "single"' <<<"$effective")" != "multi" ]]; then
    local root_disk; root_disk="$(jq -r '.root_disk // ""' <<<"$effective")"
    printf '%s: %s   (Enter to pick)\n' "$(display_label "root disk")" \
      "$([[ -n "$root_disk" ]] && _controller_disk_label "$root_disk" \
        || echo "(none)")"
  fi
  override_mark=""
  jq -e '.options.swap != null or .options.swap_size != null' \
    <<<"$state" >/dev/null 2>&1 && override_mark="  ●"
  printf '%s: %s%s\n' "$(display_label swap)" \
    "$(_controller_swap_label "$effective")" "$override_mark"
}

# _controller_list_package_slot_rows — Packages leads with the slot
# drill-downs (ADR 0058). packages.repo/aur had no menu representation at all:
# seeding a profile carried its whole package payload into Config State where
# the operator could neither see nor deselect it. `derived` is read-only — it
# reports what the Environment, Security and Backup choices pull in.
_controller_list_package_slot_rows() {
  local effective slot count override_mark derived_total
  effective="$(_controller_effective "$state" "$base")"
  for slot in repo aur; do
    count="$(_controller_package_slot_count "$effective" "$slot")"
    override_mark=""
    jq -e --arg s "$slot" \
      '(.packages[$s] != null) or (.packages.exclude != null)' \
      <<<"$state" >/dev/null 2>&1 && override_mark="  ●"
    printf '%s ▸ %s package%s%s\n' "$slot" "$count" \
      "$([[ "$count" == 1 ]] || echo s)" "$override_mark"
  done
  derived_total="$(_controller_package_derived_total "$effective")"
  printf 'derived ▸ %s package%s (read-only)\n' \
    "$derived_total" "$([[ "$derived_total" == 1 ]] || echo s)"
}

# _controller_list_field_rows <category> — one row per menu field. Unit-
# separator (\x1f), not @tsv: a tab IFS is whitespace, so read collapses the
# double delimiter of an EMPTY value field and shifts the columns. \x1f is
# non-whitespace, so empty fields are preserved.
_controller_list_field_rows() {
  local category="$1" field label value overridden locked
  while IFS=$'\x1f' read -r field label value overridden locked; do
    _controller_list_special_field_row && continue
    printf '%s: %s%s\n' "$(display_label "$label")" \
      "$(_controller_display_value_string "$field" "$value")" \
      "$([[ "$overridden" == "true" ]] && printf '  ●')"
  done < <(menu_category_rows "$category" "$state" "$base" | jq -r \
    '.[] | [.field, .label, (.value // ""), (.overridden // false | tostring),
             (.locked // false | tostring)]
           | join("\u001f")')
}

# _controller_list_special_field_row — print the row for a field that does not
# render as `label: value`, rc 1 for a plain field. Reads the caller's
# category/field/label/value/overridden/locked (dynamic scope).
_controller_list_special_field_row() {
  local mark=""
  [[ "$overridden" == "true" ]] && mark="  ●"
  # No ZFS anywhere: zfs snapshots is forced off (ADR 0041).
  if [[ "$field" == "post_install.backup.zfs_auto_snapshot" \
        && "$locked" == "true" ]]; then
    printf '%s: off (no ZFS)\n' "$(display_label "$label")"
    return 0
  fi
  [[ "$category" == "Disks" ]] || return 1
  case "$field" in
  options.encryption) _controller_list_encryption_row "$mark" ;;
  options.impermanence.enabled) _controller_list_impermanence_row "$mark" ;;
  disk_config.kind)
    # Manual Partitioning is an on/off toggle (ADR 0073): the stored kind is
    # auto/manual, but the operator sees on/off. Enter flips it in place.
    local manual=off
    [[ "$value" == "manual" ]] && manual=on
    printf 'Manual partitioning: %s%s\n' "$manual" "$mark" ;;
  *) return 1 ;;
  esac
}

# Disks encryption collapses to ONE drill-down row (ADR 0059): the toggle +
# passphrase live in the Encryption Editor, not on a bool row plus a
# passphrase sub-row. The row still carries options.encryption's override dot
# so it reads like every other field. Manual Partitioning forces it off (ADR
# 0073); show that, not the retained-but-locked override the operator can no
# longer edit.
_controller_list_encryption_row() {
  local mark="$1"
  if manual_partition_kind_active "$state"; then
    printf 'Encryption ▸ off (manual)\n'
    return 0
  fi
  printf 'Encryption ▸ %s%s\n' \
    "$(_controller_encryption_label \
      "$(_controller_effective "$state" "$base")" \
      "$(_controller_secret_tag enc)")" "$mark"
}

# Impermanence collapses to ONE drill-down row (ADR 0066): the toggle +
# persist-directory management live in the Impermanence Editor, not on a bool
# row plus a separate Add-persist action. Carries the override dot.
_controller_list_impermanence_row() {
  local mark="$1" impermanence=off
  if manual_partition_kind_active "$state"; then
    printf 'Impermanence ▸ off (manual)\n'   # forced off (ADR 0073)
    return 0
  fi
  [[ "$(config_state_get "$(_controller_effective "$state" "$base")" \
    options.impermanence.enabled)" == "true" ]] && impermanence=on
  printf 'Impermanence ▸ %s%s\n' "$impermanence" "$mark"
}

# _controller_list_package_category — the `pkgcat` screen's rows (reads the
# caller's navigation/state/base).
_controller_list_package_category() {
  # The categories inside one slot, each with its package count — mirroring
  # the Categorized List shape so the screen matches the file.
  local slot; slot="$(navigation_get "$navigation" slot)"
  local effective; effective="$(_controller_effective "$state" "$base")"
  local package_category package_count
  while IFS= read -r package_category; do
    [[ -n "$package_category" ]] || continue
    package_count="$(_controller_package_union "$effective" "$slot" \
      "$package_category" | grep -c .)"
    printf '%s ▸ %s\n' "$package_category" "$package_count"
  done < <(_controller_package_categories "$effective" "$slot")
  # Both slots open the in-place browser (ADR 0086): repo from the local sync
  # DB, aur from the fetched packages.gz list.
  if [[ "$slot" == "aur" ]]; then
    _controller_action_row "+ Add package ▸ browse all aur packages"
  else
    _controller_action_row "+ Add package ▸ browse all repo packages"
  fi
  _controller_action_row "← Back"
}

# _controller_list_packages — the `pkgs` screen's rows (reads the
# caller's navigation/state/base).
_controller_list_packages() {
  # Package toggles with three-state provenance. An inherited entry renders
  # checked WITHOUT a dot; anything this profile or session touched carries
  # one, whether it was added or excluded.
  local slot package_category effective
  slot="$(navigation_get "$navigation" slot)"; \
    package_category="$(navigation_get "$navigation" pkgcat)"
  effective="$(_controller_effective "$state" "$base")"
  local package mark override_mark
  while IFS= read -r package; do
    [[ -n "$package" ]] || continue
    if _controller_package_excluded "$effective" "$package"; then
      mark="[ ]"; override_mark="  ●"          # excluded by this profile
    else
      mark="[x]"
      if _controller_package_in_baseline "$slot" "$package_category" \
        "$package"; then
        override_mark=""                        # inherited from the baseline
      else
        override_mark="  ●"                     # added here
      fi
    fi
    printf '%s %s%s\n' "$mark" "$package" "$override_mark"
  done < <(_controller_package_union "$effective" "$slot" "$package_category")
  _controller_action_row "← Back"
}

# _controller_list_package_browse — the `pkgbrowse` screen's rows (reads the
# caller's navigation/state/base).
_controller_list_package_browse() {
  # Every package in the slot as toggle rows IN this fzf (ADR 0086) — no
  # execute() hand-off, so no bare-tty flash. repo reads the local prewarm
  # cache (pacman -Slq); aur lazily fetches packages.gz. Back leads (the list
  # runs to ~15k/~100k rows, so trailing Back is unreachable; Esc backs too).
  _controller_action_row "← Back"
  local slot package_list
  slot="$(navigation_get "$navigation" slot)"
  if [[ "$slot" == "aur" ]]; then
    package_list="$(_controller_aur_list)"
  else
    package_list="$(cat "${GUIDED_PKGLIST_FILE:-/dev/null}" 2>/dev/null)"
    [[ -n "$package_list" ]] || package_list="$(pacman -Slq 2>/dev/null)"
  fi
  if [[ -z "$package_list" ]]; then
    if [[ "$slot" == "aur" ]]; then
      printf '%s\n' \
        "(no AUR list — offline? type a package name and press Enter to add)"
    else
      printf '%s\n' "(no repo packages — run 'pacman -Sy' first, then retry)"
    fi
  else
    # Mark the ~15k rows in one awk pass off precomputed sets (a per-row jq
    # would fork per package). `●` flags a session/profile-touched row; `⟲`
    # a package another choice already pulls in (derived, read-only here).
    local effective _bbase _bextra _bexcl _bderiv
    effective="$(_controller_effective "$state" "$base")"
    _bbase="$(jq -rn --argjson c "$(_controller_baseline)" --arg s "$slot" \
      '($c.packages[$s] // {}) | [ .[] | .[]? ] | unique | .[]')"
    _bextra="$(jq -rn --argjson e "$effective" --arg s "$slot" \
      '($e.packages[$s].extra // []) | .[]')"
    _bexcl="$(jq -rn --argjson e "$effective" \
      '($e.packages.exclude // [])|.[]')"
    _bderiv="$(_controller_package_derived_names "$effective")"
    awk -v base="$_bbase" -v extra="$_bextra" -v excl="$_bexcl" \
        -v deriv="$_bderiv" -v dot='  ●' -v der='  ⟲ derived' '
      BEGIN{ n=split(base,a,"\n"); for(i=1;i<=n;i++) if(a[i]!="") C[a[i]]=1
             n=split(extra,b,"\n"); for(i=1;i<=n;i++) if(b[i]!="") X[b[i]]=1
             n=split(excl,d,"\n"); for(i=1;i<=n;i++) if(d[i]!="") E[d[i]]=1
             n=split(deriv,g,"\n"); for(i=1;i<=n;i++) if(g[i]!="") D[g[i]]=1 }
      { p=$0
        if      (E[p]) print "[ ] " p dot   # baseline, excluded here
        else if (C[p]) print "[x] " p       # inherited from the baseline
        else if (X[p]) print "[x] " p dot   # added here
        else if (D[p]) print "[x] " p der   # derived by another choice
        else           print "[ ] " p }     # available to add
    ' <<<"$package_list"
  fi
}

# _controller_list_package_derived — the `pkgderived` screen's rows (reads the
# caller's navigation/state/base).
_controller_list_package_derived() {
  # Read-only (ADR 0021 keeps the DE adapter owning its own package set).
  # Each row names the category that drives it, so the operator knows where
  # to go to change it.
  # Resolve ONCE, then count per source — the resolver is the expensive part
  # of this render and the loop used to re-run it for every source.
  local derived_rows
  derived_rows="$(_controller_package_derived "$(_controller_effective \
    "$state" "$base")")"
  local source_name derived_count
  while IFS= read -r source_name; do
    [[ -n "$source_name" ]] || continue
    derived_count="$(awk -F'\t' -v s="$source_name" '$1 == s { print $3 }' \
      <<<"$derived_rows" \
      | sort -u | grep -c .)"
    [[ "$derived_count" -gt 0 ]] || continue
    printf '%s ▸ %s   (from %s)\n' "$source_name" "$derived_count" \
      "$(package_resolver_source_origin "$source_name")"
  done < <(package_resolver_sources 2>/dev/null)
  _controller_action_row "← Back"
}

# _controller_list_package_derived_source — the `pkgderivedsrc` screen's rows
# (reads the caller's nav/state/base).
_controller_list_package_derived_source() {
  # One derived source's package list. Not toggleable — these are
  # consequences of choices made elsewhere in the menu.
  local _dsrc2; _dsrc2="$(navigation_get "$navigation" source)"
  _controller_package_derived "$(_controller_effective "$state" "$base")" \
    | awk -F'\t' -v s="$_dsrc2" '$1 == s { print "    " $3 }' | sort -u
  _controller_action_row "← Back"
}

# _controller_list_values — the `values` screen's rows (reads the
# caller's navigation/state/base).
_controller_list_values() {
  local field; field="$(navigation_get "$navigation" field)"
  if [[ "$field" == "sysctl" ]]; then
    _controller_sysctl_lines "$state" "$base"
    _controller_action_row "+ Add sysctl (key=value)"
  elif [[ "$field" == "options.mirror_servers" ]]; then
    # Custom mirror Server= URLs (ADR 0072): one per line + an Add action.
    jq -r '(.options.mirror_servers // [])[]' \
      <<<"$(_controller_effective "$state" "$base")"
    _controller_action_row "+ Add server (URL)"
  elif [[ "$field" == "options.custom_repositories" ]]; then
    # Custom repositories (ADR 0072): "name — url · <SigLevel>" + an Add
    # action.
    jq -r '(.options.custom_repositories // [])[]
      | "\(.name) — \(.url) · "
        + "\(.sign_check // "Required") \(.sign_option // "TrustedOnly")"' \
      <<<"$(_controller_effective "$state" "$base")"
    _controller_action_row "+ Add repository (name url [check] [trust])"
  elif [[ "$field" == "users" ]]; then
    _controller_list_user_rows
  elif [[ "$(_controller_field_kind "$field")" == "biglist" ]]; then
    _controller_big_list_options "$field"
  elif [[ "$(_controller_field_kind "$field")" == "toggle" ]]; then
    if _controller_display_values "$field"; then
      local marked_option; while IFS= read -r marked_option; do
        printf '%s %s\n' "${marked_option:0:3}" \
          "$(display_label "${marked_option:4}")"
      done < <(_controller_marked_options "$field" "$state" "$base")
    else
      _controller_marked_options "$field" "$state" "$base"
    fi
  else
    if _controller_display_values "$field"; then
      local option; while IFS= read -r option; do display_label \
        "$option"; done \
        < <(_controller_enum_options "$field")
    else
      _controller_enum_options "$field"
    fi
  fi
  _controller_action_row "← Back"
}

# _controller_list_user_rows — the Users values screen (reads the caller's
# state/base).
_controller_list_user_rows() {
  # Flattened Users screen — the account override surface. One merged root
  # row (ADR 0063) symmetric with a user row, then one row per user, each
  # tagged with its password source (default 12345 / custom / from age).
  # Never the value. Enter on the root row opens the Root Editor (password +
  # shell); Enter on a user row opens its User Editor. The disk passphrase
  # lives on the Disks Encryption Editor, not here (ADR 0059).
  local root_shell; root_shell="$(_controller_root_shell)"
  printf 'root — %s · pw %s\n' "$root_shell" "$(_controller_secret_tag root)"
  local marked_user user user_shell password_tag
  while IFS= read -r marked_user; do
    user="${marked_user:4}"
    if [[ "${marked_user:0:3}" == "[x]" ]]; then
      user_shell="$(_controller_user_shell "$user")"
      password_tag="$(_controller_secret_tag user "$user")"
      printf '%s — %s · pw %s\n' "$user" "$user_shell" "$password_tag"
      printf '      password (%s): %s\n' "$user" "$password_tag"
    else
      printf '%s — disabled\n' "$user"
    fi
  done < <(_controller_user_marked "$state" "$base")
  _controller_action_row "+ Create user (name)"
}
