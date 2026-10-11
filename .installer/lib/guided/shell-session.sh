#!/usr/bin/env bash
# =============================================================================
# lib/guided/shell-session.sh — Guided shell persistent-fzf front-end (ADR 0042)
# =============================================================================
# Part of the Guided Installer fzf shell (lib/guided/shell.sh, ADR 0039).
#
# Used by: lib/guided/shell.sh (sources it).
# =============================================================================

# =============================================================================
# PERSISTENT-FZF FRONT-END (ADR 0042) — the interactive front-end
# =============================================================================
# The single-long-lived-fzf path: guided_build's only interactive route (the
# legacy one-fzf-per-pick menu loop was removed at the ADR-0042 cutover). The
# functions below are the live glue — UNVERIFIED by bats (they need fzf + a
# tty); the LOGIC they lean on (controller, setters, nav, translation) is
# unit-tested in tests/config/guided-*.bats.

# guided_run_persistent — the ADR-0042 single-fzf front-end. Sets up the tmpfs
# state files (mktemp under ${TMPDIR:-/tmp}, cleaned on RETURN), launches ONE
# fzf whose enter/esc binds call lib/guided/fzf-entry.sh, then picks up the
# operator's edits + chosen terminal action. Returns 0 on a terminal action
# (sets _GUIDED_ACTION), 1 on abort. Single + multi disks resolve post-menu in
# _guided_shell_resolve_assignment, so the menu carries no disk screen.
guided_run_persistent() {
  _guided_shell_create_session_files
  local -a _guided_tmpfiles=(
    "$GUIDED_STATE_FILE" "$GUIDED_NAV_FILE" "$GUIDED_BASELINE_FILE"
    "$GUIDED_RESULT_FILE" "$GUIDED_HIST_FILE" "$GUIDED_SECRETS_FILE"
    "$GUIDED_LIST_FILE" "$GUIDED_USERFORMS_FILE" "$GUIDED_PWBUF_FILE"
    "$GUIDED_PWPENDING_FILE" "$GUIDED_SESSION_UNDO_FILE" "$GUIDED_SKIP_FILE"
    "$GUIDED_POS_FILE"
    "$GUIDED_PKGLIST_FILE" "$GUIDED_PKGDERIV_FILE" "$GUIDED_AURLIST_FILE"
    "$GUIDED_AURINFO_DIR"
  )
  # rm -rf, not -f: GUIDED_AURINFO_DIR is a directory (per-package RPC cache).
  trap 'rm -rf "${_guided_tmpfiles[@]}"' RETURN

  _guided_shell_detect_session_mode

  config_store_write_baseline "$_GUIDED_BASELINE"
  config_store_write_state "$_GUIDED_STATE"
  config_store_write_navigation "$(navigation_new)"
  : >"$GUIDED_RESULT_FILE"
  history_new "$_GUIDED_STATE" >"$GUIDED_HIST_FILE"   # undo/redo seed

  _guided_shell_launch_fzf

  _GUIDED_STATE="$(config_store_state)"
  # Load the in-menu credentials captured via execute() into the held-aside vars
  # so the existing manifest path (_guided_shell_secrets_manifest) is unchanged.
  # The Proceed gate guaranteed root + every enabled user is set before accept.
  _guided_shell_load_secrets_file "$GUIDED_SECRETS_FILE"
  # Hold the User Editor deltas aside before the tmpfiles are reaped on RETURN,
  # so Proceed's materialize (which runs after this function) can merge them.
  [[ -s "$GUIDED_USERFORMS_FILE" ]] \
    && _GUIDED_USERFORMS_JSON="$(<"$GUIDED_USERFORMS_FILE")"
  local action; action="$(<"$GUIDED_RESULT_FILE")"
  [[ -n "$action" ]] || return 1
  _GUIDED_ACTION="$action"
}

# _guided_shell_create_session_files — create + export the tmpfs session
# files every fzf-entry subprocess shares (removed by the caller's RETURN
# trap).
_guided_shell_create_session_files() {
  export GUIDED_STATE_FILE GUIDED_NAV_FILE GUIDED_BASELINE_FILE \
    GUIDED_RESULT_FILE GUIDED_HIST_FILE GUIDED_SECRETS_FILE GUIDED_LIST_FILE \
    GUIDED_USERFORMS_FILE GUIDED_PWBUF_FILE GUIDED_PWPENDING_FILE \
    GUIDED_SESSION_UNDO_FILE GUIDED_SKIP_FILE GUIDED_POS_FILE
  GUIDED_STATE_FILE="$(mktemp "${TMPDIR:-/tmp}/guided-state.XXXXXX.json")"
  GUIDED_NAV_FILE="$(mktemp "${TMPDIR:-/tmp}/guided-nav.XXXXXX.json")"
  GUIDED_BASELINE_FILE="$(mktemp "${TMPDIR:-/tmp}/guided-base.XXXXXX.json")"
  GUIDED_RESULT_FILE="$(mktemp "${TMPDIR:-/tmp}/guided-result.XXXXXX")"
  GUIDED_HIST_FILE="$(mktemp "${TMPDIR:-/tmp}/guided-hist.XXXXXX.json")"
  # In-menu credential handoff (ticket 03): the masked execute() prompt writes
  # here; the parent loads it into the held-aside vars. Never the Config State.
  GUIDED_SECRETS_FILE="$(mktemp "${TMPDIR:-/tmp}/guided-secrets.XXXXXX.json")"
  printf '{}\n' >"$GUIDED_SECRETS_FILE"
  # Latency fast-path (ticket 04): a nav dispatch precomputes the next screen's
  # list here so fzf can reload(cat …) it — one cheap fork, not a controller
  # re-source. Binds run sequentially, so one reused file is race-free.
  GUIDED_LIST_FILE="$(mktemp "${TMPDIR:-/tmp}/guided-list.XXXXXX")"
  _guided_shell_create_browser_caches
  # Install-scoped User Editor deltas (ADR 0051): the editor writes per-user
  # profile deltas here; loaded into _GUIDED_USERFORMS_JSON before this file is
  # reaped, then merged onto the clone at Proceed. Never the Config State.
  GUIDED_USERFORMS_FILE="$(mktemp \
    "${TMPDIR:-/tmp}/guided-userforms.XXXXXX.json")"
  printf '{}\n' >"$GUIDED_USERFORMS_FILE"
  # Inline masked password entry (ADR 0051): the real characters typed on the
  # secret screen live in the buffer file; the first entry of a type-twice pair
  # waits in the pending file. Both tmpfs, reaped on RETURN — never the Config
  # State, never a committed file.
  GUIDED_PWBUF_FILE="$(mktemp "${TMPDIR:-/tmp}/guided-pwbuf.XXXXXX")"
  GUIDED_PWPENDING_FILE="$(mktemp "${TMPDIR:-/tmp}/guided-pwpending.XXXXXX")"
  # `+ New host` reset-undo stash (ADR 0063): the pre-reset userforms + secrets
  # so a single undo restores the whole session. Absent until a reset fires.
  GUIDED_SESSION_UNDO_FILE="${TMPDIR:-/tmp}/guided-session-undo.$$.json"
  # Focus skip direction (ADR 0083): the up/down binds record the last movement
  # here so the `focus` bind knows which way to hop past an inert row. Seeded
  # `down` so a skip before the first arrow (never happens — line 0 is a
  # selectable Profiles row — but be safe) advances rather than stalls.
  GUIDED_SKIP_FILE="$(mktemp "${TMPDIR:-/tmp}/guided-skip.XXXXXX")"
  printf 'down' >"$GUIDED_SKIP_FILE"
  # Cursor-restore target (position memory): a back nav writes the 1-based line
  # to re-focus here; the `load` bind's poshint applies it once after the reload
  # (a `pos` in the reload's own action targets the pre-reload list — proven by
  # the fzf pty harness — so it must be deferred to load). Empty = no restore.
  GUIDED_POS_FILE="$(mktemp "${TMPDIR:-/tmp}/guided-pos.XXXXXX")"
}

# _guided_shell_create_browser_caches — the package browser's session caches
# (ADR 0086), exported for the fzf-entry subprocesses.
_guided_shell_create_browser_caches() {
  # Repo package browser prewarm (ADR 0086): the in-place browser reloads the
  # pacman -Slq universe (~15k rows) into this fzf. Fill this cache in the
  # background at menu start so the browse screen renders instantly on open.
  # Empty (race / no pacman) → the pkgbrowse render falls back to a live query.
  export GUIDED_PKGLIST_FILE
  GUIDED_PKGLIST_FILE="$(mktemp "${TMPDIR:-/tmp}/guided-pkglist.XXXXXX")"
  command_exists pacman \
    && (pacman -Slq >"$GUIDED_PKGLIST_FILE" 2>/dev/null &)
  # Derived-set cache for the package browser (ADR 0086): resolving the derived
  # packages is the expensive part of that screen's render, and it is invariant
  # while only extras are toggled. Keyed by the derivation-relevant config, so a
  # browse add hits the cache and a real change (GPU/DE/…) recomputes.
  export GUIDED_PKGDERIV_FILE
  GUIDED_PKGDERIV_FILE="$(mktemp "${TMPDIR:-/tmp}/guided-pkgderiv.XXXXXX")"
  # AUR browser session caches (ADR 0086): the list file holds the fetched
  # packages.gz names (filled on first AUR-browse open, not prewarmed — it is a
  # network call, unlike the local repo list); the info dir caches one RPC-info
  # preview per package. Both tmpfs, reaped on RETURN — nothing persists (live
  # ISO /root is RAM).
  export GUIDED_AURLIST_FILE GUIDED_AURINFO_DIR
  GUIDED_AURLIST_FILE="$(mktemp "${TMPDIR:-/tmp}/guided-aurlist.XXXXXX")"
  GUIDED_AURINFO_DIR="$(mktemp -d "${TMPDIR:-/tmp}/guided-aurinfo.XXXXXX")"
}

# _guided_shell_detect_session_mode — decide + export, once, what every
# fzf-entry subprocess must agree on: the live medium, device vs count mode,
# and the rich fzf chrome.
_guided_shell_detect_session_mode() {
  # In-Menu Disk Binding (ADR 0047): resolve the live medium + whether any
  # install disk is enumerable ONCE, and export both so the fzf-entry
  # subprocesses bind real /dev/disk/by-id/* devices (device-mode) or keep the
  # abstract count cycle (count-mode). Off-target (no disks) stays device-less —
  # Save/Export still work with nothing attached.
  export GUIDED_LIVE_SET GUIDED_DEVICE_MODE
  GUIDED_LIVE_SET="$(live_medium_disks 2>/dev/null || true)"
  GUIDED_DEVICE_MODE="$(_controller_detect_device_mode)"

  # Rich chrome (ADR 0047): decide ONCE whether the installed fzf (≥ 0.62)
  # supports the footer/breadcrumb chrome; a lagging ISO's older fzf degrades to
  # the legacy action-rows layout. Cached so every fzf-entry subprocess agrees.
  export GUIDED_RICH_CHROME
  GUIDED_RICH_CHROME="$(_controller_detect_rich_chrome)"
}

# Fixed navy/blue palette (ADR 0071) so the installer looks the same on any box
# (not the operator's fzf theme, absent on the live ISO). Truecolor; degrades
# to 256 where unsupported.
_GUIDED_SHELL_FZF_COLORS='bg:#0b0f14,bg+:#1f6feb,fg:#c7d0da,fg+:#ffffff'
_GUIDED_SHELL_FZF_COLORS+=',hl:#39d0d8,hl+:#ffffff,border:#233240'
_GUIDED_SHELL_FZF_COLORS+=',label:#39d0d8,preview-bg:#0b0f14'
_GUIDED_SHELL_FZF_COLORS+=',preview-fg:#c7d0da,prompt:#39d0d8,pointer:#ffffff'
_GUIDED_SHELL_FZF_COLORS+=',marker:#f0a020,header:#5b6b7a,info:#5b6b7a'
_GUIDED_SHELL_FZF_COLORS+=',gutter:#0b0f14,spinner:#39d0d8,query:#c7d0da'

# _guided_shell_launch_fzf — the one long-lived fzf; its binds call
# lib/guided/fzf-entry.sh.
_guided_shell_launch_fzf() {
  # The header + prompt are updated per screen by the controller's `render`
  # directive (change-header/change-prompt), so they always say how to go back.
  # enter passes BOTH the selection {} and the typed query {q} (text fields read
  # {q} from fzf's own input line); esc maps to a back/abort transform; the
  # ^Z/^Y/^R keys undo/redo/reset over the snapshot stack.
  local entry="${INSTALLER_DIR}/lib/guided/fzf-entry.sh"
  # Rich chrome flags (fzf >= 0.62 only): footer + rounded list border. Passed
  # only when supported so an older fzf never chokes; the ^A/^X binds are
  # harmless on either.
  local -a rich_flags=()
  if [[ "$GUIDED_RICH_CHROME" == "1" ]]; then
    rich_flags=(--footer=' ' --footer-border=top \
      --list-border=rounded --list-label-pos=center)
  fi
  # The preview pane is the always-on master-detail column (ADR 0071), wired to
  # the entry's `preview` verb from the start so it paints on first render.
  # The current row is marked by the ▶ pointer (ADR 0082).
  guided_controller_list | fzf --reverse --prompt='guided> ' --pointer='▶' \
    --border=rounded --border-label=' Guided Installer ' \
    --border-label-pos=center \
    --header='Enter open   Esc quit   ·   ^Z undo  ^Y redo  ^R reset' \
    --header-border=bottom \
    --color="$_GUIDED_SHELL_FZF_COLORS" \
    "${rich_flags[@]}" \
    --preview="bash $entry preview {}" --preview-window='right,45%' \
    --bind "change:transform-query(bash $entry mask {q})" \
    --bind "start:unbind(change)" \
    --bind "up:execute-silent(printf up > $GUIDED_SKIP_FILE)+up" \
    --bind "ctrl-p:execute-silent(printf up > $GUIDED_SKIP_FILE)+up" \
    --bind "ctrl-k:execute-silent(printf up > $GUIDED_SKIP_FILE)+up" \
    --bind "page-up:execute-silent(printf up > $GUIDED_SKIP_FILE)+page-up" \
    --bind "down:execute-silent(printf down > $GUIDED_SKIP_FILE)+down" \
    --bind "ctrl-n:execute-silent(printf down > $GUIDED_SKIP_FILE)+down" \
    --bind "ctrl-j:execute-silent(printf down > $GUIDED_SKIP_FILE)+down" \
    --bind "page-down:execute-silent(printf down > $GUIDED_SKIP_FILE)+\
page-down" \
    --bind "focus:transform(bash $entry skip {})" \
    --bind "load:transform(bash $entry poshint)" \
    --bind "enter:transform(bash $entry dispatch enter {} {q})" \
    --bind "esc:transform(bash $entry dispatch back {})" \
    --bind "ctrl-a:transform(bash $entry key ctrl-a)" \
    --bind "ctrl-s:transform(bash $entry key ctrl-s)" \
    --bind "ctrl-x:transform(bash $entry key ctrl-x {})" \
    --bind "ctrl-z:transform(bash $entry key ctrl-z)" \
    --bind "ctrl-y:transform(bash $entry key ctrl-y)" \
    --bind "ctrl-r:transform(bash $entry key ctrl-r)" \
    >/dev/null || true
}

# _guided_shell_load_secrets_file <file> — copy the captured secrets from the
# in-menu handoff file into the held-aside vars (root pw, enc passphrase, user
# pws). No-op on a missing/empty file. The vars, not the file, feed
# _guided_shell_secrets_manifest.
_guided_shell_load_secrets_file() {
  local secrets_file="$1" root_password encryption_passphrase user password
  [[ -s "$secrets_file" ]] || return 0
  root_password="$(jq -r '.root_password // ""' "$secrets_file")"
  [[ -n "$root_password" ]] && _GUIDED_ROOT_PASSWORD="$root_password"
  encryption_passphrase="$(jq -r '.enc_passphrase // ""' "$secrets_file")"
  [[ -n "$encryption_passphrase" ]] \
    && _GUIDED_ENCRYPTION_PASSPHRASE="$encryption_passphrase"
  while IFS= read -r user; do
    [[ -n "$user" ]] || continue
    password="$(jq -r --arg n "$user" '.users[$n].password // ""' \
      "$secrets_file")"
    [[ -n "$password" ]] && _GUIDED_USER_PASSWORDS["$user"]="$password"
  done < <(jq -r '(.users // {}) | keys[]' "$secrets_file")
}

# _guided_shell_guard_post_install — the terminal-action no-user guard (M5, ADR
# 0041). The Security & Backup Extras install via the Primary User's paru pass,
# so a non-empty selection on a userless host can never run. Reads the effective
# post_install object + the effective user count and defers to the pure guard;
# returns non-zero (with the actionable error) when extras are selected but no
# user exists. Run before every terminal action (Proceed / Save / Export).
_guided_shell_guard_post_install() {
  local effective_json post_install_json count
  effective_json="$(_guided_shell_effective)"
  post_install_json="$(jq -c '.post_install // {}' <<<"$effective_json")"
  count="$(jq '(.users // []) | length' <<<"$effective_json")"
  post_install_guard_users "$post_install_json" "$count"
}

# guided_build — drive the guided menu and emit the device-baked Effective
# Config on stdout. Interactive: the re-entrant Host / Users split menu.
# Headless (--guided replay): a linear keyed collection through the SAME edit
# helpers. The typed INSTALL is the sole consent gate; non-zero (no output) if
# it is withheld. _guided_shell_resolve_assignment — the picked disks →
# per-group assignment JSON for emit_effective, branching on the chosen mode.
# single bakes the one picked disk; multi collects Σ disk_count disks, slices
# them per group (picker_build_assignment), renders the per-group summary, and
# gates on a typed ACCEPT before the layout is accepted (issue 04). Emits the
# assignment on stdout; non-zero on any failure.
_guided_shell_resolve_assignment() {
  local mode; mode="$(config_state_get "$(_guided_shell_effective)" mode)"
  if [[ "$mode" == "multi" ]]; then
    _guided_shell_resolve_multi_assignment
  else
    _guided_shell_resolve_single_disk
  fi
}

_guided_shell_resolve_multi_assignment() {
  local assignment counted
  # In-Menu Disk Binding (ADR 0047): when any group is device-bound, the disks
  # were chosen in the menu — build the assignment from devices[], with no
  # post-menu pick and no ACCEPT. A fully-bound layout picks nothing; a mixed
  # one still flat-picks only the counted groups' disks (then ACCEPTs).
  if skeleton_any_bound "$_GUIDED_STATE"; then
    counted="$(skeleton_counted_disks "$_GUIDED_STATE")"
    if [[ "$counted" == "0" ]]; then
      skeleton_build_assignment "$_GUIDED_STATE"; return
    fi
    # Mixed layout: flat-pick only the counted remainder. NOTE: this pick does
    # not yet exclude in-menu-bound disks (a follow-up guard); a fully-bound
    # on-target layout never reaches here, so it is edge-only for now.
    assignment="$(_guided_shell_pick_layout_disks skeleton_build_assignment \
      "$counted" "more disk(s)")" || return 1
  else
    # Device-less (replay / off-target-authored): flat-pick the whole layout.
    assignment="$(_guided_shell_pick_layout_disks picker_build_assignment \
      "$(skeleton_total_disks "$_GUIDED_STATE")" "disks")" || return 1
  fi
  section "Disk layout" >&2
  skeleton_assignment_summary "$_GUIDED_STATE" "$assignment" >&2
  local ok
  ok="$(guided_prompt accept_layout "Type ACCEPT to use this layout")"
  [[ "$ok" == "ACCEPT" ]] \
    || { error "guided: disk layout not accepted"; return 1; }
  printf '%s\n' "$assignment"
}

# _guided_shell_pick_layout_disks <builder> <count> <noun> — pick <count>
# disks, then print <builder>'s assignment for them; error when short.
_guided_shell_pick_layout_disks() {
  local builder="$1" count="$2" noun="$3"
  local -a disks
  mapfile -t disks < <(guided_pick_disks disks "$count")
  ((${#disks[@]} == count)) \
    || { error "guided: layout needs ${count} ${noun}, got ${#disks[@]}"
         return 1; }
  "$builder" "$_GUIDED_STATE" "${disks[@]}"
}

# Single disk: prefer the in-menu root disk pick (device-mode, ADR 0047), else
# the post-menu / replay _GUIDED_DISK path (the persistent menu has no
# install-disk row; replay sets _GUIDED_DISK via _guided_shell_edit_disk).
_guided_shell_resolve_single_disk() {
  local disk; disk="$(jq -r '.root_disk // ""' <<<"$_GUIDED_STATE")"
  if [[ -z "$disk" ]]; then
    [[ -n "$_GUIDED_DISK" ]] || _guided_shell_edit_disk
    disk="$_GUIDED_DISK"
  fi
  [[ -n "$disk" ]] || { error "guided: no disk selected"; return 1; }
  jq -n --arg d "$disk" '{mode: "single", disk: $d}'
}
