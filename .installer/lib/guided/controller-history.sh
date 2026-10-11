#!/usr/bin/env bash
# =============================================================================
# lib/guided/controller-history.sh — undo/redo/reset history + key dispatch
# =============================================================================
# Part of the guided controller (lib/guided/controller.sh, ADR 0042).
#
# Used by: lib/guided/controller.sh (sources it).
# =============================================================================

# ── undo / redo / reset history (slice 03) ───────────────────────────────────
# Snapshots live in $GUIDED_HIST_FILE; _controller_autocommit pushes one whenever the
# Config State changed since the last snapshot. It runs from guided_controller_list —
# the single choke point every edit funnels through on its render — so toggles,
# value picks, text, and even one-shot edits are all captured as one undo step
# without sprinkling commits across the dispatch.
_controller_autocommit() {
  [[ -f "${GUIDED_HIST_FILE:-/nonexistent}" ]] || return 0
  local hist now prev
  hist="$(<"$GUIDED_HIST_FILE")"
  now="$(_controller_state | jq -cS .)"
  prev="$(history_present "$hist" | jq -cS .)"
  [[ "$now" == "$prev" ]] && return 0
  history_commit "$hist" "$(_controller_state)" >"$GUIDED_HIST_FILE"
  # A fresh edit voids the `+ New host` reset-undo stash: its side-state no
  # longer matches the current session, so a later undo must not resurrect it.
  rm -f "${GUIDED_SESSION_UNDO_FILE:-/nonexistent}"
}

# _controller_navigation_reconcile <nav> <state> → a nav still valid for <state>. A history op
# (reset/undo/redo) can invalidate the screen the nav sits on: it can delete the
# pool a pooledit/pooldisks nav addresses (rendering "?" for the gone group), or
# drop the layout back to single-disk while the multi-only datapools editor is
# open (the OS pool row vanishes). Reset from inside the custom editor was the
# reported case. When the current screen no longer fits the state, this backs
# the
# nav out to its category; any other nav is returned unchanged.
_controller_navigation_reconcile() {
  local nav="$1" state="$2" screen kind i exists
  screen="$(navigation_screen "$nav")"
  case "$screen" in
  datapools)
    # The unified layout editor only makes sense for a multi layout; after a
    # reset to the single-disk default it would show only the add rows, so back
    # out to the category (which shows the default "layout: single disk").
    if [[ "$(jq -r '.mode // "single"' <<<"$state")" == "multi" ]]; then
      printf '%s' "$nav"
    else navigation_to_category "$(navigation_get "$nav" category)"; fi
    return ;;
  pooledit | pooldisks) ;;
  *) printf '%s' "$nav"; return ;;
  esac
  kind="$(_controller_pool_kind "$nav")"; i="$(navigation_get "$nav" index)"; i="${i:-0}"
  case "$kind" in
  os)      exists="$(jq -r 'if .os_pool then 1 else 0 end' <<<"$state")" ;;
  storage) exists="$(jq -r --argjson i "$i" \
             'if (.storage_groups[$i] // null) then 1 else 0 end' \
             <<<"$state")" ;;
  *)       exists="$(jq -r --argjson i "$i" \
             'if (.data_pools[$i] // null) then 1 else 0 end' <<<"$state")" ;;
  esac
  if [[ "$exists" == "1" ]]; then printf '%s' "$nav"
  else navigation_to_category "$(navigation_get "$nav" category)"; fi
}

# guided_controller_key <ctrl-z|ctrl-y|ctrl-r> — the global toolbar keys. ^Z undoes /
# ^Y redoes over the snapshot stack; ^R resets every override back to the seeded
# launch state (itself undoable — ^Z brings it back, so no confirm is needed).
# Each restores the Config State from the stack and re-renders in place; the nav
# is reconciled so a pool editor left pointing at a now-deleted pool backs out
# to
# its category instead of rendering "?" everywhere.
guided_controller_key() {
  local k="$1" hist state
  [[ -f "${GUIDED_HIST_FILE:-/nonexistent}" ]] || { echo noop; return; }
  hist="$(<"$GUIDED_HIST_FILE")"
  case "$k" in
  ctrl-z) hist="$(history_undo "$hist")"
          # The first undo after a `+ New host` reset also restores the stashed
          # userforms + secrets (the side-state the Config-State stack omits).
          _controller_session_unstash ;;
  ctrl-y) hist="$(history_redo "$hist")" ;;
  ctrl-r) hist="$(history_commit "$hist" '{}')" ;;
  *)      echo noop; return ;;
  esac
  printf '%s\n' "$hist" >"$GUIDED_HIST_FILE"
  state="$(history_present "$hist")"
  _controller_write_state "$state"
  _controller_write_navigation "$(_controller_navigation_reconcile "$(_controller_navigation)" "$state")"
  echo render
}

# _controller_directive_to_action <directive> <entry> — map a controller directive
# to the fzf action string a `transform` bind executes. <entry> is the absolute
# path of the bind entry script. A `render` re-lists AND re-headers/re-prompts
# the (post-mutation) screen so the toolbar always reflects "how to go back";
# a terminal action writes the verb to $GUIDED_RESULT_FILE then accepts; an
# edit-oneshot hands the tty to the existing helper then re-lists.
# _controller_reload_command <entry> — the reload command for a re-render. Fast path
# (ticket 04): precompute the current screen's list into GUIDED_LIST_FILE and
# `cat` it — one cheap fork instead of a second bash that re-sources the whole
# controller. Falls back to the bash re-render when no list file is wired (bats
# / non-persistent contexts), so behaviour is identical either way.
_controller_reload_command() {
  local entry="$1"
  if [[ -n "${GUIDED_LIST_FILE:-}" ]]; then
    guided_controller_list >"$GUIDED_LIST_FILE" 2>/dev/null
    printf 'cat %q' "$GUIDED_LIST_FILE"
  else
    printf 'bash %q list' "$entry"
  fi
}

# _controller_focus_position <focus> — the 1-based line index of the row <focus> names in the
# CURRENT screen's list, for a back-nav cursor restore (fzf `pos`). <focus> is a
# category name ("Disks — …") or a field label ("Filesystem: …" / "Swap ▸ …");
# the row is matched by literal prefix at a token boundary (space / colon), so no
# regex-escaping and no false hit on a longer name. Empty when <focus> is unset
# or unmatched — the caller then omits `pos` and fzf keeps its default landing.
_controller_focus_position() {
  local focus="$1" i=0 line
  [[ -n "$focus" ]] || return 0
  while IFS= read -r line; do
    i=$((i + 1))
    case "$line" in
    "$focus" | "$focus "* | "$focus:"*) printf '%s' "$i"; return 0 ;;
    esac
  done < <(guided_controller_list)
}

_controller_directive_to_action() {
  local d="$1" entry="$2" nav
  case "$d" in
  render)
    # clear-query first: fzf keeps the filter text across reload, so a leftover
    # filter would hide the next screen's items (e.g. typing "disk" then opening
    # the preset picker would hide every preset). Each screen starts unfiltered.
    # The Disk-layout screen turns on a preview (the ASCII layout graph); every
    # other screen swaps the preview to a cheap no-op and hides the pane, so the
    # graph command only runs where it's shown.
    nav="$(_controller_navigation)"
    local pv _showpv=0
    case "$(navigation_screen "$nav")" in
    top | category | values | text)   # the always-on master-detail pane (0071)
      _showpv=1 ;;
    datapools | pooledit) _showpv=1 ;;   # the live layout graph
    profiles) _showpv=1 ;;               # the profile's header comment
    pkgbrowse) _showpv=1 ;;              # the highlighted package's pacman -Si
    esac
    if ((_showpv)); then
      pv="$(printf \
      '+change-preview(bash %q preview {})+change-preview-window(right,45%%)' \
        "$entry")"
    else
      pv='+change-preview(echo)+change-preview-window(hidden)'
    fi
    # Rich chrome (fzf ≥ 0.62): a live footer (context actions + summary) and a
    # breadcrumb on the list-label. Legacy fzf gets neither (actions stay in the
    # list, header carries the keys) — the features are identical either way.
    local chrome=''
    if _controller_rich_chrome; then
      chrome="$(printf '+change-footer(%s)+change-list-label(%s)' \
        "$(_controller_footer "$nav")" "$(_controller_breadcrumb "$nav")")"
    fi
    # Inline masking (ADR 0051): the password screen turns the change→mask bind
    # on
    # and disables query-cursor movement so the buffer diff can never desync;
    # every
    # other screen turns masking off and restores the cursor keys. rebind/unbind
    # of
    # an already-(un)bound key/event is harmless, so this is safe on all
    # renders.
    local mask
    if [[ "$(navigation_screen "$nav")" == "secret" ]]; then
      mask='+rebind(change)+unbind(left)+unbind(right)+unbind(home)+unbind(end)'
    else
      mask='+unbind(change)+rebind(left)+rebind(right)+rebind(home)+rebind(end)'
    fi
    # Cursor restore (position memory): a back nav carries a `focus` hint naming
    # the row it returned onto. Resolve it to a 1-based line and stash it in
    # GUIDED_POS_FILE for the `load` bind's one-shot `pos`. The write happens HERE
    # — inside the transform command, before the returned reload runs — so it
    # lands before `load` fires. A `+pos(N)` in this action string instead would
    # target the PRE-reload (child) list and clamp onto a spacer (fzf pty-proven).
    local _fpos
    _fpos="$(_controller_focus_position "$(navigation_get "$nav" focus)")"
    [[ -n "$_fpos" && -n "${GUIDED_POS_FILE:-}" ]] \
      && printf '%s' "$_fpos" >"$GUIDED_POS_FILE"
    printf 'clear-query+reload(%s)+change-header(%s)+change-prompt(%s)%s%s%s' \
      "$(_controller_reload_command "$entry")" "$(_controller_navigation_header "$nav")" \
      "$(_controller_navigation_prompt "$nav")" "$pv" "$chrome" "$mask" ;;
  refresh)
    # same screen, just re-mark the list: reload-sync avoids the flicker a plain
    # reload shows, and keeps the query + header (no clear-query/change-*).
    # refresh-preview re-renders the live layout graph after a pool/disk edit;
    # a no-op where the preview pane is hidden. Rich chrome ALSO re-emits the
    # footer so its live summary (e.g. "2 bound") tracks a bind/add without a
    # full
    # render — change-footer leaves the typed query untouched.
    local rfoot=''
    _controller_rich_chrome && rfoot="$(printf '+change-footer(%s)' \
      "$(_controller_footer "$(_controller_navigation)")")"
    printf 'reload-sync(%s)+refresh-preview%s' "$(_controller_reload_command "$entry")" \
      "$rfoot" ;;
  abort)            printf 'abort' ;;
  noop)             printf 'ignore' ;;
  "terminal "*)     printf 'execute-silent(printf %%s %q > %q)+accept' \
                      "${d#terminal }" "${GUIDED_RESULT_FILE:-/dev/null}" ;;
  "secret-root")
    printf 'execute(bash %q secret root)+clear-query+reload(bash %q list)' \
      "$entry" "$entry" ;;
  "secret-user "*)
    printf 'execute(bash %q secret user %q)+clear-query+reload(bash %q list)' \
      "$entry" "${d#secret-user }" "$entry" ;;
  "secret-enc")
    printf 'execute(bash %q secret enc)+clear-query+reload(bash %q list)' \
      "$entry" "$entry" ;;
  "notice "*)       printf 'change-header(%s)+bell' "${d#notice }" ;;
  manual-on)
    # Reload the Disks screen (locked fields greyed, Partitions row shown) and
    # point the operator at the cfdisk hand-off (ADR 0073).
    printf 'reload(%s)+change-header(%s)+bell' "$(_controller_reload_command "$entry")" \
      'Manual: pool features off — open Partitions ▸ to run cfdisk' ;;
  cfdisk)
    # Suspend fzf, run cfdisk on the target disk, scan + store the assignment,
    # then reload so the Partitions row shows the new count (ADR 0073).
    printf 'execute(bash %q cfdisk)+clear-query+reload(%s)' \
      "$entry" "$(_controller_reload_command "$entry")" ;;
  "secret-mismatch")
    # Re-render the (now entry-phase) masked screen with a warning header, query
    # cleared, masking + cursor-lock kept on. Distinct from `render` only in the
    # header text and the bell.
    printf 'clear-query+reload(%s)+change-header(%s)+change-prompt(password> )'\
'+rebind(change)+unbind(left)+unbind(right)+unbind(home)+unbind(end)+bell' \
      "$(_controller_reload_command "$entry")" \
      '⚠ passwords did not match — type it again   ·   Esc cancels' ;;
  *)                printf 'ignore' ;;
  esac
}
