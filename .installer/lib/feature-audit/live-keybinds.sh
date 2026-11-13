#!/usr/bin/env bash
# =============================================================================
# lib/feature-audit/live-keybinds.sh — keybind phase
# =============================================================================
# Part of the live Audit Run (lib/feature-audit/live.sh, ADR 0152).
#
# Used by: lib/feature-audit/live.sh (sources it).
# =============================================================================

# ── keybinds (feature-audit/11+) ─────────────────────────────────────────────

# feature_audit_push_binds_lib — stage binds-guest.sh (the guest half of the
# keybind engine) where feature_audit_guest_execute sources it.
# The jq programs held in single-quoted variables use jq's $names.
# shellcheck disable=SC2016

feature_audit_push_binds_lib() {
  feature_audit_agent push "$INSTALLER_DIR/lib/feature-audit/binds-guest.sh" \
    /tmp/fa-binds >/dev/null 2>&1
}

# feature_audit_guest_execute <fn> [args…] — run a binds-guest.sh function in
# the live session.
feature_audit_guest_execute() {
  # vm-agent exec runs under set -e; the guest helpers branch on tests
  local command="set +e; source /tmp/fa-binds/binds-guest.sh;" argument
  for argument in "$@"; do command+=" $(printf '%q' "$argument")"; done
  feature_audit_agent exec "$command" 2>/dev/null
}

_live_compositor_process() {
  case "$1" in niri) echo niri ;; hyprland) echo Hyprland ;;
    umbriel) echo umbriel ;; kde) echo kwin_wayland ;; esac
}

# _live_send <chord | click:x,y> — one step of a bind's `pre`/`then` list.
_live_send() {
  case "$1" in
    click:*)
      local x y
      # The x and y after "click:" (6 characters), comma-separated.
      x="$(printf '%s\n' "${1:6}" | cut -d, -f1)"
      y="$(printf '%s\n' "${1:6}" | cut -d, -f2)"
      feature_audit_agent mouse move "$x" "$y" >/dev/null 2>&1
      feature_audit_agent mouse btn left down >/dev/null 2>&1
      feature_audit_agent mouse btn left up >/dev/null 2>&1 ;;
    *) feature_audit_agent key "$1" >/dev/null 2>&1 ;;
  esac
}

# _live_bind_recover <recovery> <chord> <desktop>
_live_bind_recover() {
  case "$1" in
    escape)  feature_audit_agent key Escape >/dev/null 2>&1 ;;
    toggle)  feature_audit_agent key "$2" >/dev/null 2>&1 ;;
    # the key after "key:"
    key:*)   feature_audit_agent key "${1:4}" >/dev/null 2>&1 ;;
    unlock)  feature_audit_agent unlock >/dev/null 2>&1 ;;
    session) feature_audit_agent session "$3" >/dev/null 2>&1
             feature_audit_agent idle off >/dev/null 2>&1
             feature_audit_push_binds_lib
             feature_audit_guest_execute feature_audit_binds_baseline \
               >/dev/null ;;
  esac
  sleep 1
}

# _live_mouse_chord <Mods+mouse_down|mouse_up|mouse:272|mouse:273> — hold the
# modifiers, then wheel (mouse_down/up) or drag from screen centre with the
# left (272) / right (273) button: real pointer input, like a hand would.
_live_mouse_chord() {
  local chord="$1" modifiers button
  local all_but_last='$c | split("+") | .[:-1] | join("+")'
  # The keys before the last "+" (none for a bare button), and the last one.
  modifiers="$(jq -r -n --arg c "$chord" "$all_but_last")"
  button="$(jq -r -n --arg c "$chord" '$c | split("+") | .[-1]')"
  feature_audit_agent mouse move 16384 16384 >/dev/null 2>&1
  if [[ -n "$modifiers" ]]; then
    feature_audit_agent keydown "$modifiers" >/dev/null 2>&1 || return 1
    sleep 0.3   # the compositor must see the modifier held first
  fi
  case "$button" in
    mouse_down) feature_audit_agent mouse wheel down ;;
    mouse_up)   feature_audit_agent mouse wheel up ;;
    mouse:272|mouse:273)
      local button_side=left; [[ "$button" == mouse:273 ]] && button_side=right
      _live_mouse_drag "$button_side" ;;
    *) [[ -n "$modifiers" ]] \
      && feature_audit_agent keyup "$modifiers" >/dev/null 2>&1
       return 1 ;;
  esac >/dev/null 2>&1
  [[ -n "$modifiers" ]] \
    && feature_audit_agent keyup "$modifiers" >/dev/null 2>&1
  return 0
}

# _live_mouse_drag <left|right> — press the button at screen centre, drag it
# down-right in two steps, release; stops at the first step that fails.
_live_mouse_drag() {
  feature_audit_agent mouse move 16384 16384 || return 1
  sleep 0.2
  feature_audit_agent mouse btn "$1" down || return 1
  sleep 0.2
  feature_audit_agent mouse move 18000 17500 || return 1
  sleep 0.2
  feature_audit_agent mouse move 20000 19000 || return 1
  sleep 0.2
  feature_audit_agent mouse btn "$1" up
}

# _live_row_field <row-json> <filter> — one field of a plan row, as text.
_live_row_field() {
  # The filter's value in the row.
  printf '%s\n' "$1" | jq -r "$2"
}

# _live_bind_one <plan-row-json> <desktop> — one bind as real input; prints its
# PASS/FAIL/SKIP line.
_live_bind_one() {
  local row="$1" desktop="$2" chord effect argument needs recovery settle id
  local before after rc screenshot_directory pid=""
  chord="$(_live_row_field "$row" .chord)"
  effect="$(_live_row_field "$row" .effect)"
  argument="$(_live_row_field "$row" '.arg // ""')"
  needs="$(_live_row_field "$row" '.needs // ""')"
  recovery="$(_live_row_field "$row" '.recovery // ""')"
  settle="$(_live_row_field "$row" '.settle // 1.5')"
  id="bind-$(_live_row_field "$row" .source)-$chord"
  if [[ "$effect" == unverifiable ]]; then
    echo "SKIP $id unverifiable:" \
      "$(_live_row_field "$row" '.reason // "no reason"')"
    return
  fi
  screenshot_directory="Pictures/Screenshots"
  [[ "$effect" == file-created ]] && screenshot_directory="$argument"
  feature_audit_guest_execute feature_audit_binds_setup "$needs" "$effect" \
    "$argument" >/dev/null
  _live_send_steps "$row" pre send-then-wait
  before="$(feature_audit_guest_execute feature_audit_binds_state \
    "$screenshot_directory")"
  [[ "$effect" == session-ends ]] && pid="$(_live_compositor_pid "$desktop")"
  if [[ "$chord" == *mouse* ]]; then
    _live_mouse_chord "$chord" \
      || { echo "SKIP $id mouse chord not injectable"; return; }
  elif ! feature_audit_agent key "$chord" >/dev/null 2>&1; then
    echo "SKIP $id key not injectable by QEMU"
    feature_audit_guest_execute feature_audit_binds_teardown; return
  fi
  _live_send_steps "$row" "then" wait-then-send
  if [[ "$effect" == session-ends ]]; then
    _live_bind_session_end "$row" "$id" "$chord" "$desktop" "$recovery" \
      "$pid"
    return
  fi
  sleep "$settle"
  after="$(feature_audit_guest_execute feature_audit_binds_state \
    "$screenshot_directory")"
  rc=0
  feature_audit_guest_execute feature_audit_binds_evaluate "$effect" \
    "$argument" \
    "$before" "$after" >/dev/null || rc=$?
  _live_bind_verdict "$rc" "$id" "$row" "$effect" "$argument"
  [[ -n "$recovery" ]] && _live_bind_recover "$recovery" "$chord" "$desktop"
  feature_audit_guest_execute feature_audit_binds_teardown >/dev/null
}

# _live_bind_verdict <rc> <id> <row> <effect> <argument> — the bind's result
# line from feature_audit_binds_evaluate's exit code.
_live_bind_verdict() {
  local rc="$1" id="$2" row="$3" effect="$4" argument="$5"
  case "$rc" in
    0) echo "PASS $id $effect" ;;
    3) echo "SKIP $id $effect not observable here (no audio device)" ;;
    *) echo "FAIL $id ($(_live_row_field "$row" .action)) expected" \
         "$effect${argument:+ $argument}, not observed" ;;
  esac
}

# _live_send_steps <row> <pre|then> <send-then-wait|wait-then-send> — type the
# row's pre-chord or post-chord steps into the guest, a second apart.
_live_send_steps() {
  local row="$1" field="$2" order="$3" step
  while IFS= read -r step; do
    [[ -n "$step" ]] || continue
    if [[ "$order" == send-then-wait ]]; then
      _live_send "$step"; sleep 1
    else
      sleep 1; _live_send "$step"
    fi
  done < <(_live_row_field "$row" ".${field}[]?")
}

# _live_compositor_pid <desktop> — the running compositor's PID (the oldest, so
# not a CLI client of the same name).
_live_compositor_pid() {
  feature_audit_agent sudo "pgrep -ox $(_live_compositor_process "$1")" \
    2>/dev/null
}

# _live_bind_session_end <row> <id> <chord> <desktop> <recovery> <pid> — a
# session-ends bind passes when the compositor <pid> it was sent to is gone
# within 10s (a DM relogin may already run a new one); then recover.
_live_bind_session_end() {
  local row="$1" id="$2" chord="$3" desktop="$4" recovery="$5" pid="$6"
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    feature_audit_agent sudo "test -d /proc/$pid" >/dev/null 2>&1 || break
    sleep 1
  done
  if feature_audit_agent sudo "test -d /proc/$pid" >/dev/null 2>&1; then
    echo "FAIL $id ($(_live_row_field "$row" .action)) did not end the session"
  else echo "PASS $id session ended"; fi
  _live_bind_recover "${recovery:-session}" "$chord" "$desktop"
}

# feature_audit_phase_keybinds <variant-dir> <cfg> — per compositor of the set,
# every shipped bind as real keyboard input; session-ending binds last.
feature_audit_phase_keybinds() {
  local variant_directory="$1" config="$2" desktop source_name directory \
    since out row first="" why
  local skipped='select(.effect != null)'
  skipped+=' | "SKIP bind-\(.source)-\(.chord) \($w)"'
  local session_ending_last='sort_by(.session_ending // false) | .[]'
  first="$(feature_audit_desktops "$config" | head -n 1)"
  while IFS= read -r desktop; do
    [[ -n "$desktop" ]] || continue
    directory="$variant_directory/keybinds-$desktop"; mkdir -p "$directory"
    since="$(feature_audit_guest_now)"
    feature_audit_agent session "$desktop" > "$directory/agent.txt" 2>&1 || {
      echo "keybinds: session $desktop not ready" >> \
        "$directory/session-start.lines"
      continue; }
    feature_audit_agent idle off >/dev/null 2>&1 || true
    feature_audit_push_binds_lib
    feature_audit_guest_execute feature_audit_binds_baseline >/dev/null
    for source_name in $(feature_audit_binds_sources); do
      # app sources (session `*`) run once, in the first session
      case "$(feature_audit_binds_session "$source_name")" in
        "$desktop") ;;  "*") [[ "$desktop" == "$first" ]] \
          || continue ;;  *) continue ;;
      esac
      out="$directory/probe-binds-$source_name@$FA_USER.probe"
      # Probe Gate: binds this variant does not deploy are SKIPped, not judged
      if why="$(feature_audit_bind_gate "$desktop" "$config")"; then
        # A SKIP line, with the gate's reason, per testable bind.
        feature_audit_binds_plan "$source_name" \
          | jq -r --arg w "$why" "$skipped" >> "$out"
        continue
      fi
      while IFS= read -r row; do
        _live_bind_one "$row" "$desktop" >> "$out"
      # The plan's testable binds, the session-ending ones last.
      done < <(feature_audit_binds_plan "$source_name" \
        | jq -c 'select(.effect != null)' | jq -s -c "$session_ending_last")
    done
    feature_audit_collect "$directory" "$since"
  done < <(feature_audit_desktops "$config")
}
