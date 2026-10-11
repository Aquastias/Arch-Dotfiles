#!/usr/bin/env bash
# =============================================================================
# lib/guided/controller-detail.sh — master-detail pane, preview, profiles picker
# =============================================================================
# Part of the guided controller (lib/guided/controller.sh, ADR 0042).
#
# Used by: lib/guided/controller.sh (sources it).
# =============================================================================

# ── always-on master-detail pane (ADR 0071) ──────────────────────────────────
# On the top + category screens the preview pane is a live detail column: a
# parent column (the siblings, current item marked "▶", the rest dimmed) above
# the highlighted item's detail. Pure: reads state + nav from files like
# guided_controller_list, so it is asserted headless (tests/guided/detail.bats).
_CONTROLLER_DIM=$'\033[2m'; _CONTROLLER_BOLD=$'\033[1m'; _CONTROLLER_RESET=$'\033[0m'

# _controller_detail_column <current> < "name\toverridden"-lines — the parent column:
# each name a row, the one equal to <current> marked "▶", the rest dimmed, and a
# "●" appended to any overridden sibling (user story 14).
_controller_detail_column() {
  local current="$1" n ov dot
  while IFS=$'\t' read -r n ov; do
    dot=""; [[ "$ov" == true ]] && dot="  ●"
    if [[ -n "$current" && "$n" == "$current" ]]; then
      printf '  %s▶ %s%s%s\n' "$_CONTROLLER_BOLD" "$n" "$dot" "$_CONTROLLER_RESET"
    else
      printf '%s    %s%s%s\n' "$_CONTROLLER_DIM" "$n" "$dot" "$_CONTROLLER_RESET"
    fi
  done
}

# _controller_detail_leaf <field> <state> <base> — one field's leaf detail, shared by
# the category-screen field row and the field editor screens: its label, current
# value (● when overridden), then either its option set (enumerable) or a
# free-text hint (a text field). Pure.
_controller_detail_leaf() {
  local field="$1" state="$2" base="$3" row label val ov dot opts
  row="$(menu_rows "$state" "$base" \
    | jq -c --arg p "$field" 'first(.[] | select(.field == $p)) // {}')"
  label="$(jq -r '.label // ""' <<<"$row")"
  val="$(jq -r '.value // ""' <<<"$row")"
  ov="$(jq -r '.overridden // false' <<<"$row")"
  dot=""; [[ "$ov" == true ]] && dot="  ●"
  printf '%s%s%s\n  %s: %s%s\n' "$_CONTROLLER_BOLD" "$label" "$_CONTROLLER_RESET" \
    "$label" "${val:-(none)}" "$dot"
  if [[ "$(_controller_field_kind "$field")" == text ]]; then
    printf '%s  (free text — type a value)%s\n' "$_CONTROLLER_DIM" "$_CONTROLLER_RESET"
    return 0
  fi
  # A Cycle Field has no menu_enum_options list; render its two values with the
  # current one marked so Enter-flips-here stays discoverable (ADR 0075).
  if _controller_is_cycle_field "$field"; then
    printf '%sCycle:%s\n' "$_CONTROLLER_DIM" "$_CONTROLLER_RESET"
    local o
    for o in true false; do
      if [[ "$o" == "$val" ]]; then printf '  ● %s\n' "$o"
      else printf '    %s\n' "$o"; fi
    done
    return 0
  fi
  opts="$(menu_enum_options "$field")"
  [[ -n "$opts" ]] || return 0
  printf '%sOptions:%s\n' "$_CONTROLLER_DIM" "$_CONTROLLER_RESET"
  printf '%s\n' "  ${opts//$'\n'/$'\n'  }"
}

# _controller_detail_reflector_note <category> — the reflector consumer line, shown
# only under Mirrors & Repositories: the countries feed reflector's ranking.
_controller_detail_reflector_note() {
  [[ "$1" == "Mirrors & Repositories" ]] || return 0
  printf '%s  countries → reflector --country --latest 10 --sort rate%s\n' \
    "$_CONTROLLER_DIM" "$_CONTROLLER_RESET"
}

# _controller_detail_user_table <state> <base> — the Users account table for the detail
# pane (ticket 03): root's row plus each user's shell/sudo/groups panel, reusing
# the existing _controller_user_panel builder (no new render). Disabled users show as
# such. Mirrors the flattened Users screen's rows.
_controller_detail_user_table() {
  local state="$1" base="$2" um un
  printf '\n%sAccounts%s\n' "$_CONTROLLER_BOLD" "$_CONTROLLER_RESET"
  printf 'root — %s · pw %s\n' "$(_controller_root_shell)" "$(_controller_secret_tag root)"
  while IFS= read -r um; do
    un="${um:4}"
    [[ -n "$un" ]] || continue
    if [[ "${um:0:3}" == "[x]" ]]; then _controller_user_panel "$un"
    else printf '%s — disabled\n' "$un"; fi
  done < <(_controller_user_marked "$state" "$base")
}

# _controller_detail_top <line> <state> <base> — top-screen preview: the highlighted
# category's OWN detail only. The category parent column is gone (ADR 0082) —
# the
# current selection is marked by the fzf triangle pointer in the main list, so
# the pane no longer duplicates the category list. Users shows its table (ticket
# 03); every other category shows its fields as "label: value" (● on overrides).
# A non-category row (Profiles/Proceed/a bucket header/…) previews nothing.
_controller_detail_top() {
  local line="$1" state="$2" base="$3" cur rows
  cur="${line%% — *}"
  if [[ "$cur" == "Users" ]]; then
    _controller_detail_user_table "$state" "$base"; return 0
  fi
  rows="$(menu_category_rows "$cur" "$state" "$base" 2>/dev/null)"
  [[ -n "$rows" && "$rows" != "[]" ]] || return 0
  printf '%s%s%s\n' "$_CONTROLLER_BOLD" "$cur" "$_CONTROLLER_RESET"
  jq -r '.[] | "  \(.label): \(.value // "")"
               + (if .overridden then "  ●" else "" end)' <<<"$rows"
  _controller_detail_reflector_note "$cur"
}

# _controller_detail_category <line> <state> <base> <cat> — category-screen preview:
# the sibling-field parent column + the highlighted leaf's value and options.
_controller_detail_category() {
  local line="$1" state="$2" base="$3" cat="$4" label rows cur_field cur_label
  label="${line%%:*}"; label="${label%% ▸*}"
  cur_field="$(_controller_field_for_label "$cat" "$label")"
  rows="$(menu_category_rows "$cat" "$state" "$base")"
  cur_label=""
  [[ -n "$cur_field" ]] && cur_label="$(jq -r --arg p "$cur_field" \
    'first(.[] | select(.field == $p) | .label) // ""' <<<"$rows")"
  printf '%s%s%s\n' "$_CONTROLLER_BOLD" "$cat" "$_CONTROLLER_RESET"
  jq -r '.[] | "\(.label)\t\(.overridden)"' <<<"$rows" \
    | _controller_detail_column "$cur_label"
  _controller_detail_reflector_note "$cat"
  # The Disks Layout row is a synthetic leaf: preview the live ZFS pool tree,
  # reusing the layout-graph builder (ticket 03).
  if [[ "$cat" == "Disks" && "$label" == "$(display_label layout)" ]]; then
    printf '\n%sLayout%s\n' "$_CONTROLLER_BOLD" "$_CONTROLLER_RESET"
    _controller_layout_graph "$(_controller_effective "$state" "$base")"
    return 0
  fi
  [[ -n "$cur_field" ]] || return 0
  printf '\n'
  _controller_detail_leaf "$cur_field" "$state" "$base"
}

# _controller_detail_pane <line> — the master-detail preview for the top / category
# screens (ADR 0071); empty on any other screen (they keep their own preview).
_controller_detail_pane() {
  local line="$1" nav state base
  nav="$(_controller_navigation)"; state="$(_controller_state)"; base="$(_controller_baseline)"
  case "$(navigation_screen "$nav")" in
  top)      _controller_detail_top "$line" "$state" "$base" ;;
  category) _controller_detail_category "$line" "$state" "$base" \
              "$(navigation_get "$nav" category)" ;;
  esac
}

# guided_controller_preview <line> — the fzf preview body. On the top + category +
# field screens it is the always-on master-detail pane (ADR 0071); on the
# layout / profiles / users screens it is that screen's own rich preview (the
# layout graph, profile tree, per-user panel); empty elsewhere.
guided_controller_preview() {
  local line="$1" navigation
  navigation="$(_controller_navigation)"
  case "$(navigation_screen "$navigation")" in
  top | category) _controller_detail_pane "$line" ;;
  # The data-pools editor screens graph the LIVE state (not a preset line) so
  # the tree reflects pools/disks as you add and cycle them.
  datapools | pooledit) _controller_live_layout_graph ;;
  profiles) _controller_preview_profile "$line" ;;
  text)
    # The free-text editor screen (hostname / URL / size / package name): the
    # shared leaf detail so the pane is populated here too (ADR 0071).
    _controller_detail_leaf "$(navigation_get "$navigation" field)" \
      "$(_controller_state)" "$(_controller_baseline)" ;;
  pkgbrowse) _controller_preview_package "$line" "$navigation" ;;
  values) _controller_preview_value "$line" "$navigation"; return ;;
  esac
  return 0
}

# _controller_live_layout_graph — the layout graph of the live effective state.
_controller_live_layout_graph() {
  _controller_layout_graph \
    "$(_controller_effective "$(_controller_state)" "$(_controller_baseline)")"
}

# _controller_preview_profile <line> — a deep ASCII tree of the resolved
# (Host-Core-merged) profile (ADR 0063), down to its leaves — replacing the
# header-comment-only preview. The Reset-to-blank / Back rows preview nothing.
_controller_preview_profile() {
  local line="$1" profile_file profile
  [[ "$line" == "← Back" || "$line" == "↺ Reset to blank"* || -z "$line" ]] \
    && return 0
  profile_file="$(_controller_hosts_root)/${line}/profile.jsonc"
  if profile="$(_program_registry_parse "$profile_file" 2>/dev/null)"; then
    _controller_profile_tree "$(layer_resolver_resolve host \
      "$(config_state_host_core)" "$profile")"
  else
    printf '\033[2m(no profile — hosts/%s/profile.jsonc)\033[0m\n' "$line"
  fi
}

# _controller_preview_package <line> <navigation> — the highlighted package's
# detail (ADR 0086): the browser keeps the master-detail pane the rest of the
# menu shows. repo uses pacman -Si; aur queries the RPC info endpoint (cached
# per package).
_controller_preview_package() {
  local line="$1" navigation="$2" package
  [[ "$line" == "← Back" || "${line:0:1}" != "[" ]] && return 0
  package="${line:4}"; package="${package%%  *}"
  [[ -n "$package" ]] || return 0
  if [[ "$(navigation_get "$navigation" slot)" == "aur" ]]; then
    _controller_aur_preview "$package"
  else
    pacman -Si "$package" 2>/dev/null
  fi
  return 0
}

# _controller_preview_value <line> <navigation> — the values screen's pane.
# A field with no dedicated selection panel (kernel, bootloader, gpu, a bool)
# gets the shared leaf detail, so every field screen shows a populated pane.
_controller_preview_value() {
  local line="$1" navigation="$2" field
  field="$(navigation_get "$navigation" field)"
  if ! _controller_field_has_preview "$field"; then
    _controller_detail_leaf "$field" "$(_controller_state)" \
      "$(_controller_baseline)"
    return 0
  fi
  case "$field" in
  users) _controller_preview_account "$line" ;;
  __layout__) _controller_preview_layout "$line" ;;
  system.keymap)
    # multi: the selected keymap array (+ the highlighted candidate, mark
    # stripped)
    local selected; selected="$(jq -r \
      '.system.keymap // [] | if type == "array" then . else [.] end | .[]' \
      <<<"$(_controller_effective "$(_controller_state)" \
        "$(_controller_baseline)")")"
    printf 'Selected keymaps:\n'
    if [[ -n "$selected" ]]; then printf '%s\n' "  ${selected//$'\n'/$'\n'  }"
    else printf '  (none)\n'; fi
    printf '\nHighlighted:\n  %s\n' "${line:4}" ;;
  system.locale | system.timezone)
    local current
    current="$(_controller_field_display "$field" "$(_controller_state)" \
      "$(_controller_baseline)")"
    printf 'Selected %s:\n  %s\n\nHighlighted:\n  %s\n' \
      "$(navigation_get "$navigation" label)" "${current:-(none)}" "$line" ;;
  esac
}

# _controller_preview_account <line> — the hovered account's detail panel (ADR
# 0063). The root row shows its shell + password source; a user row shows the
# effective (core-merged, override-applied) User Profile — shell, sudo,
# groups, programs, git, ssh.
_controller_preview_account() {
  local line="$1" user
  [[ "$line" == "+ Create"* || "$line" == "← Back" || -z "$line" ]] \
    && return 0
  if [[ "$line" == "root — "* ]]; then
    printf 'root\n'
    printf '  shell:    %s\n' "$(_controller_root_shell)"
    printf '  password: %s\n' "$(_controller_secret_tag root)"
    return 0
  fi
  # "name — shell · pw tag" (enabled) or "name — disabled": name before " — ".
  user="${line%% — *}"
  [[ -n "$user" ]] && _controller_user_panel "$user"
}

# _controller_preview_layout <line> — a destructive preset row previews THAT
# preset ("what you'd get"). The data-pools row is additive (it opens the
# editor, keeping your pools) and ← Back is no choice at all — both graph the
# LIVE state so edits stay visible.
_controller_preview_layout() {
  local line="$1" skeleton
  if [[ "$line" == "data-pools" || "$line" == "← Back" ]]; then
    _controller_live_layout_graph
  elif skeleton="$(skeleton_preset "$line" 2>/dev/null)"; then
    _controller_layout_graph "$skeleton"
  else
    _controller_live_layout_graph
  fi
}

# ── Profiles picker (ADR 0055) ───────────────────────────────────────────────
# _controller_hosts_root — the hosts/ tree the Profiles picker enumerates.
_controller_hosts_root() { printf '%s' "${INSTALLER_DIR:-.}/hosts"; }

# _controller_profiles_available — rc 0 when at least one installable Host Profile
# exists (so the top-screen `Profiles ▸` row is shown), rc 1 otherwise.
_controller_profiles_available() {
  [[ -n "$(profiles_list "$(_controller_hosts_root)" 2>/dev/null)" ]]
}
