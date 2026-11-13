#!/usr/bin/env bash
# =============================================================================
# lib/feature-audit/binds-guest.sh — guest-side keybind state + effects
# =============================================================================
# Staged into the guest and sourced inside the live session (VM Agent Control
# `exec`). The host sends each bind as real input between a
# `feature_audit_binds_state` before/after pair, then
# `feature_audit_binds_evaluate` judges the declared effect from the two
# snapshots (ADR 0152). Compositor-aware: niri (`niri msg`), Hyprland
# (`hyprctl`), Umbriel (`umbriel msg`, ADR 0159), KDE (KWin D-Bus + spectacle).
#
# Effects: window-opens <app-re> | window-closes | workspace <n> |
#   workspace-changes | focus-changes | layout-changes | window-changes
#   (focus or layout) | screen-changes | file-created <dir> | audio-changes |
#   session-ends
#
# The file is sourced alone in the guest, so its jq programs live here, in
# named variables, rather than in separate .jq files.
#
# Used by: pushed into the guest session by lib/feature-audit/live-keybinds.sh
# (feature_audit_push_binds_lib); run via feature_audit_guest_execute.
# =============================================================================
# The jq programs held in single-quoted variables use jq's $names.
# shellcheck disable=SC2016

FA_BIND_CLASS=fa-bind

_binds_guest_compositor() {
  local compositor
  for compositor in niri Hyprland umbriel kwin_wayland; do
    pgrep -x "$compositor" >/dev/null 2>&1 && { echo "$compositor"; return; }
  done
  echo none
}

# The normalized window list, per compositor: [{id, app, ws, focused, geo}].
_BINDS_GUEST_NIRI_WINDOWS='map({id, app: .app_id, ws: .workspace_id,
  focused: .is_focused, geo: {f: .is_floating, l: .layout}})'
# $a is the active window's address.
_BINDS_GUEST_HYPRLAND_WINDOWS='map({id: .address, app: .class,
  ws: .workspace.id, focused: (.address == $a),
  geo: {at, size, floating, fullscreen}})'
# `active` is seat focus; Umbriel's `focused` is per-workspace memory.
_BINDS_GUEST_UMBRIEL_WINDOWS='map({id, app: .app_id, ws: .workspace,
  focused: .active, geo: {x, y, w, h, floating, fullscreen,
  maximized_to_edges, pinned, column, row, tabbed, scratchpad, visible}})'

# _binds_guest_windows — normalized window list JSON: [{id, app, ws, focused,
# geo}].
_binds_guest_windows() {
  local active
  case "$(_binds_guest_compositor)" in
    niri)
      # The windows, normalized.
      niri msg -j windows 2>/dev/null | jq -c "$_BINDS_GUEST_NIRI_WINDOWS" ;;
    Hyprland)
      # The active window's address, then the windows, normalized.
      active="$(hyprctl -j activewindow 2>/dev/null | jq -r '.address // ""')"
      hyprctl -j clients 2>/dev/null \
        | jq -c --arg a "$active" "$_BINDS_GUEST_HYPRLAND_WINDOWS" ;;
    umbriel)
      # The windows, normalized.
      umbriel windows --json 2>/dev/null \
        | jq -c "$_BINDS_GUEST_UMBRIEL_WINDOWS" ;;
    kwin_wayland) _binds_guest_kwin_windows ;;
    *) echo '[]' ;;
  esac
}

# _binds_guest_kwin_windows — KWin has no JSON IPC; a one-shot KWin script
# prints the window list to the journal, read back by a marker.
_binds_guest_kwin_windows() {
  local marker="fa-kwin-$$-$RANDOM" script
  script="$(mktemp --suffix=.js)"
  cat > "$script" <<JS
var out = [];
workspace.windowList().forEach(function (w) {
  if (!w.normalWindow) return;
  out.push({id: w.internalId.toString(), app: w.resourceClass,
            ws: w.desktops.length ? w.desktops[0].x11DesktopNumber : 0,
            focused: w === workspace.activeWindow,
            geo: {x: w.frameGeometry.x, y: w.frameGeometry.y,
                  w: w.frameGeometry.width, h: w.frameGeometry.height,
                  full: w.fullScreen, max: w.maximizeMode,
                  min: w.minimized}});
});
print("$marker" + JSON.stringify(out));
JS
  local id
  id="$(qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript \
    "$script" "$marker" 2>/dev/null)"
  qdbus6 org.kde.KWin "/Scripting/Script${id}" \
    org.kde.kwin.Script.run >/dev/null 2>&1
  sleep 0.5
  qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript "$marker" \
    >/dev/null 2>&1
  rm -f "$script"
  local line last=""
  while IFS= read -r line; do
    [[ "$line" == *"$marker"* ]] || continue
    # The text after the marker: this line's window list.
    last="$(jq -r -n --arg l "$line" --arg m "$marker" '$l | split($m)[1]')"
  done < <(journalctl --user -q -o cat --since "-10s" 2>/dev/null)
  printf '%s\n' "${last:-[]}"
}

# The focused output's active workspace, per compositor: {idx, id, count}.
_BINDS_GUEST_NIRI_WORKSPACE='(map(select(.is_focused))[0]) as $f
  | {idx: $f.idx, id: $f.id,
     count: (map(select(.output == $f.output)) | length)}'
_BINDS_GUEST_UMBRIEL_WORKSPACE='(map(select(.focused))[0]) as $f
  | {idx: $f.index, id: $f.id,
     count: (map(select(.output == $f.output)) | length)}'

# _binds_guest_workspace — {idx, id, count} of the focused output's active
# workspace.
_binds_guest_workspace() {
  case "$(_binds_guest_compositor)" in
    niri)
      # The focused workspace and how many its output has.
      niri msg -j workspaces 2>/dev/null \
        | jq -c "$_BINDS_GUEST_NIRI_WORKSPACE" ;;
    # Hyprland creates a numbered workspace on demand: no clamp
    Hyprland) hyprctl -j activeworkspace 2>/dev/null \
            | jq -c '{idx: .id, id: .id, count: 99}' ;;
    umbriel)
      # The focused workspace and how many its output has.
      umbriel workspaces --json 2>/dev/null \
        | jq -c "$_BINDS_GUEST_UMBRIEL_WORKSPACE" ;;
    kwin_wayland)
      local compositor number
      compositor="$(qdbus6 org.kde.KWin /KWin org.kde.KWin.currentDesktop \
        2>/dev/null)"
      number="$(qdbus6 org.kde.KWin /VirtualDesktopManager \
        org.freedesktop.DBus.Properties.Get org.kde.KWin.VirtualDesktopManager \
        count 2>/dev/null)"
      # The current desktop and the desktop count.
      jq -cn --argjson c "${compositor:-0}" --argjson n "${number:-0}" \
        '{idx: $c, id: $c, count: $n}' ;;
    *) echo '{}' ;;
  esac
}

_binds_guest_shot_hash() {
  local shot_file; shot_file="$(mktemp --suffix=.png)"
  case "$(_binds_guest_compositor)" in
    kwin_wayland) timeout 15 spectacle -bnf -o "$shot_file" >/dev/null 2>&1 ;;
    *) timeout 10 grim "$shot_file" >/dev/null 2>&1 ;;
  esac
  # The first 12 characters of the screenshot's checksum.
  sha1sum "$shot_file" 2>/dev/null | cut -c1-12
  rm -f "$shot_file"
}

_binds_guest_audio() {
  # The sink's and the source's volume lines, space-joined.
  { wpctl get-volume @DEFAULT_AUDIO_SINK@
    wpctl get-volume @DEFAULT_AUDIO_SOURCE@; } 2>/dev/null | paste -sd' ' -
}

# The keybind snapshot: everything an effect can observe.
_BINDS_GUEST_STATE='{comp: $comp, windows: $w, ws: $ws, shot: $shot,
  audio: $audio, files: ($files | tonumber),
  focused: ([$w[] | select(.focused)][0].id // null),
  layout: ($w | map({id, ws, geo}) | tostring)}'

# feature_audit_binds_state [home-rel-dir] — snapshot JSON of everything an
# effect can observe (the dir is where file-created counts new files).
feature_audit_binds_state() {
  local directory="$HOME/${1:-Pictures/Screenshots}" files
  # How many files the directory holds.
  files="$(find "$directory" -type f 2>/dev/null | grep -c .)"
  # The snapshot.
  jq -cn --arg comp "$(_binds_guest_compositor)" \
    --argjson w "$(_binds_guest_windows)" \
    --argjson ws "$(_binds_guest_workspace)" \
    --arg shot "$(_binds_guest_shot_hash)" \
    --arg audio "$(_binds_guest_audio)" \
    --arg files "$files" "$_BINDS_GUEST_STATE"
}

# feature_audit_binds_setup <needs> <effect> <arg> — reset to a known scene
# before a bind: test windows on the first workspace (+ a stack / floating / 2nd
# workspace when the bind needs one). Best-effort; the effect check is the
# judge. _binds_guest_hyprland <lua> — a Hyprland dispatch. The shipped config
# is Lua, where `hyprctl dispatch` evaluates Lua: legacy dispatcher names fail.
_binds_guest_hyprland() { hyprctl dispatch "$1" >/dev/null 2>&1; }

feature_audit_binds_setup() {
  local needs="$1" effect="$2" argument="${3:-}" compositor want=2 direction=""
  local token
  compositor="$(_binds_guest_compositor)"
  # windows:<n> (how many test windows) and dir:<direction> (focus target).
  for token in $needs; do
    case "$token" in
      windows:*) want="${token:8}" ;;    # after "windows:"
      dir:*)     direction="${token:4}" ;;   # after "dir:"
    esac
  done
  # Hyprland's dwindle needs a third window for a vertical neighbour
  [[ -n "$direction" && "$compositor" == Hyprland && "$want" -lt 3 ]] \
    && want=3
  _binds_guest_go_to_workspace "$compositor" 1
  _binds_guest_open_test_windows "$want"
  _binds_guest_arrange "$compositor" "$needs"
  _binds_guest_apply_need_tokens "$compositor" "$needs"
  [[ -n "$direction" ]] \
    && _binds_guest_focus_for_directory "$compositor" "$direction"
  # a workspace-N bind must start somewhere else to prove it moved (niri
  # clamps N to the last workspace, so only `1` needs to start further down)
  if [[ "$effect" == workspace && "$argument" == 1 ]]; then
    case "$compositor" in
      niri) _binds_guest_niri focus-workspace-down ;;
      umbriel) _binds_guest_umbriel workspace-next ;;
      Hyprland) _binds_guest_hyprland "hl.dsp.focus({ workspace = 10 })" ;;
      kwin_wayland) qdbus6 org.kde.KWin /KWin \
        org.kde.KWin.setCurrentDesktop 2 >/dev/null 2>&1 ;;
    esac
  fi
  sleep 0.5
}

# _binds_guest_niri <action…> — a niri `msg action`.
_binds_guest_niri() { niri msg action "$@" >/dev/null 2>&1; }

# _binds_guest_umbriel <action> [arg…] — an Umbriel `msg` action, arguments as
# separate words (upstream syntax since late Oct 2026; ADR 0159).
_binds_guest_umbriel() { umbriel msg "$@" >/dev/null 2>&1; }

# _binds_guest_go_to_workspace <compositor> <n> — focus workspace / desktop n.
_binds_guest_go_to_workspace() {
  case "$1" in
    niri) _binds_guest_niri focus-workspace "$2" ;;
    umbriel) _binds_guest_umbriel workspace-switch "$2" ;;
    Hyprland) _binds_guest_hyprland "hl.dsp.focus({ workspace = $2 })" ;;
    kwin_wayland) qdbus6 org.kde.KWin /KWin \
      org.kde.KWin.setCurrentDesktop "$2" >/dev/null 2>&1 ;;
  esac
}

# _binds_guest_open_test_windows <want> — open test kitty windows until the
# first (current) workspace holds <want> of them.
_binds_guest_open_test_windows() {
  local want="$1" count workspace
  local on_workspace='[.[] | select(.app == $c and .ws == $w)] | length'
  # The current workspace's id, then how many test windows it holds.
  workspace="$(_binds_guest_workspace | jq .id)"
  count="$(_binds_guest_windows \
    | jq --arg c "$FA_BIND_CLASS" --argjson w "$workspace" "$on_workspace")"
  while ((count < want)); do
    setsid -f kitty --class "$FA_BIND_CLASS" >/dev/null 2>&1
    sleep 1.5; count=$((count + 1))
  done
}

# _binds_guest_arrange <compositor> <needs> — the window layout a bind needs:
# stacked, floating, a test window on workspace 2, or starting on workspace 2.
_binds_guest_arrange() {
  local compositor="$1" needs="$2"
  # the focused window joins the left column
  if [[ "$needs" == *stack* ]]; then
    case "$compositor" in
      niri) _binds_guest_niri consume-or-expel-window-left ;;
      umbriel) _binds_guest_umbriel window-consume-or-expel-left ;;
    esac
  fi
  if [[ "$needs" == *floating* ]]; then
    case "$compositor" in
      niri) _binds_guest_niri toggle-window-floating ;;
      umbriel) _binds_guest_umbriel window-toggle-floating ;;
      Hyprland) _binds_guest_hyprland \
        'hl.dsp.window.float({ action = "toggle" })' ;;
    esac
  fi
  # ws2win: one test window on workspace 2, focus back on 1
  if [[ "$needs" == *ws2win* ]]; then
    case "$compositor" in
      niri) _binds_guest_niri move-column-to-workspace 2
            _binds_guest_niri focus-workspace 1 ;;
      umbriel) _binds_guest_umbriel column-move-to-workspace 2
               _binds_guest_umbriel workspace-switch 1 ;;
      Hyprland)
        _binds_guest_hyprland \
          "hl.dsp.window.move({ workspace = 2, silent = true })"
        _binds_guest_hyprland "hl.dsp.focus({ workspace = 1 })" ;;
    esac
  fi
  [[ "$needs" == *workspace2* ]] \
    && _binds_guest_go_to_workspace "$compositor" 2
  return 0
}

# _binds_guest_apply_need_tokens <compositor> <needs> — the per-token needs:
# desktop:N, maximized, launch:<app>, clip:<text>.
_binds_guest_apply_need_tokens() {
  local compositor="$1" needs="$2" token
  for token in $needs; do
    case "$token" in
      desktop:*)          # start on workspace/desktop N (grid navigation)
        _binds_guest_go_to_workspace "$compositor" "${token:8}" ;;
      maximized)
        [[ "$compositor" == kwin_wayland ]] && _binds_guest_kwin_run \
          "workspace.activeWindow.setMaximize(true, true);" ;;
      # the app after "launch:", the text after "clip:"
      launch:*) setsid -f "${token:7}" >/dev/null 2>&1; sleep 4 ;;
      clip:*) printf '%s' "${token:5}" | wl-copy >/dev/null 2>&1 ;;
    esac
  done
}

# The test window to focus on Hyprland's dwindle (A left half, B top-right,
# C bottom-right) so a bind in direction $d has a neighbour.
_BINDS_GUEST_HYPRLAND_PICK='[.[] | select(.class == $c and .workspace.id == 1)]
  | (map(.size[1]) | max) as $H
  | (if $d == "right" then min_by(.at[0])
     elif $d == "left" then max_by(.at[0])
     elif $d == "up" then max_by(.at[1])
     else (map(select(.size[1] < $H)) | min_by(.at[1])) end)
  | .address // empty'

# _binds_guest_focus_for_directory <comp> <dir> — focus a test window that HAS a
# neighbour in <dir>, so a directional focus/move bind can prove it did
# something.
_binds_guest_focus_for_directory() {
  local compositor="$1" direction="$2" pick
  case "$compositor" in
    niri)
      case "$direction" in
        right) _binds_guest_niri focus-column-first ;;
        left)  _binds_guest_niri focus-column-last ;;
        up)    _binds_guest_niri focus-window-bottom ;;
        down)  _binds_guest_niri focus-window-top ;;
      esac ;;
    # a stack is two rows: one step reaches the row with a neighbour
    umbriel)
      case "$direction" in
        right) _binds_guest_umbriel column-focus-first ;;
        left)  _binds_guest_umbriel column-focus-last ;;
        up)    _binds_guest_umbriel window-focus-down ;;
        down)  _binds_guest_umbriel window-focus-up ;;
      esac ;;
    Hyprland)
      # The address of the window with a neighbour in that direction.
      pick="$(hyprctl -j clients 2>/dev/null | jq -r --arg c "$FA_BIND_CLASS" \
        --arg d "$direction" "$_BINDS_GUEST_HYPRLAND_PICK")"
      [[ -n "$pick" ]] \
        && _binds_guest_hyprland \
        "hl.dsp.focus({ window = \"address:$pick\" })" ;;
    kwin_wayland) _binds_guest_kwin_arrange "$direction" ;;
  esac
}

# _binds_guest_kwin_run <js> — run a one-shot KWin script (no JSON IPC on KDE).
_binds_guest_kwin_run() {
  local script id name="fa-kwin-$$-$RANDOM"
  script="$(mktemp --suffix=.js)"
  printf '%s\n' "$1" > "$script"
  id="$(qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript \
    "$script" "$name" 2>/dev/null)"
  qdbus6 org.kde.KWin "/Scripting/Script${id}" org.kde.kwin.Script.run \
    >/dev/null 2>&1
  sleep 0.5
  qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript \
    "$name" >/dev/null 2>&1
  rm -f "$script"
}

# _binds_guest_kwin_arrange <dir> — tile the two test windows side by side
# (left/ right) or stacked (up/down) and focus the one with a neighbour in
# <dir>.
_binds_guest_kwin_arrange() {
  _binds_guest_kwin_run "
var ws = workspace.windowList().filter(function (w) {
  return w.resourceClass == '$FA_BIND_CLASS'; });
if (ws.length >= 2) {
  var a = workspace.clientArea(KWin.MaximizeArea, workspace.activeScreen,
                               workspace.currentDesktop);
  var d = '$1', h = (d == 'left' || d == 'right');
  ws[0].frameGeometry = {x: a.x, y: a.y,
    width: h ? a.width / 2 : a.width, height: h ? a.height : a.height / 2};
  ws[1].frameGeometry = {x: h ? a.x + a.width / 2 : a.x,
    y: h ? a.y : a.y + a.height / 2,
    width: h ? a.width / 2 : a.width, height: h ? a.height : a.height / 2};
  workspace.activeWindow = (d == 'right' || d == 'down') ? ws[0] : ws[1];
}"
}

# feature_audit_binds_baseline — remember the windows open before the keybind
# phase, so teardown can close whatever a bind opened (launchers, task entries,
# …).
feature_audit_binds_baseline() {
  mkdir -p /tmp/fa-binds
  # The open windows' ids, one per line.
  _binds_guest_windows | jq -r '.[].id | tostring' > /tmp/fa-binds/baseline
}

# feature_audit_binds_teardown — drop the scene: the test windows (recreated per
# bind) and every window a bind opened since the baseline.
feature_audit_binds_teardown() {
  local compositor id
  local -A in_baseline=()
  pkill -f -- "--class $FA_BIND_CLASS" >/dev/null 2>&1 || true
  compositor="$(_binds_guest_compositor)"
  [[ -f /tmp/fa-binds/baseline ]] || { sleep 0.5; return 0; }
  while IFS= read -r id; do
    [[ -n "$id" ]] && in_baseline["$id"]=1
  done < /tmp/fa-binds/baseline
  while IFS= read -r id; do
    [[ -n "$id" && -z "${in_baseline["$id"]:-}" ]] || continue
    case "$compositor" in
      niri) niri msg action close-window --id "$id" >/dev/null 2>&1 ;;
      umbriel) _binds_guest_umbriel window-close "$id" ;;
      Hyprland) _binds_guest_hyprland \
        "hl.dsp.window.close({ window = \"address:$id\" })" ;;
      kwin_wayland) _binds_guest_kwin_run "workspace.windowList().forEach(
        function (w) { if (w.internalId.toString() == '$id')
          w.closeWindow(); });" ;;
    esac
  # The open windows' ids, one per line.
  done < <(_binds_guest_windows | jq -r '.[].id | tostring')
  sleep 0.5
}

# feature_audit_binds_evaluate <effect> <arg> <before-json> <after-json> — exit
# 0 iff observed.
feature_audit_binds_evaluate() {
  local effect="$1" argument="$2" before="$3" after="$4" observed
  case "$effect" in
    window-opens)
      observed='([$a.windows[] | select(.app | test($r; "i"))] | length)'
      observed+=' > ([$b.windows[] | select(.app | test($r; "i"))] | length)' ;;
    window-closes) observed='($a.windows | length) < ($b.windows | length)' ;;
    workspace)
      observed='$a.ws.idx == ([($r | tonumber), $b.ws.count] | min)' ;;
    workspace-changes)
      observed='$a.ws.id != $b.ws.id or $a.ws.idx != $b.ws.idx' ;;
    focus-changes) observed='$a.focused != $b.focused' ;;
    window-changes)
      observed='$a.layout != $b.layout or $a.focused != $b.focused' ;;
    layout-changes) observed='$a.layout != $b.layout' ;;
    screen-changes) observed='$a.shot != $b.shot and $a.shot != ""' ;;
    file-created) observed='$a.files > $b.files' ;;
    audio-changes)
      # no sink: can't tell
      local audio
      # The audio volumes before the bind.
      audio="$(printf '%s\n' "$before" | jq -r .audio)"
      [[ -n "$audio" ]] || return 3
      observed='$a.audio != $b.audio' ;;
    *) return 2 ;;
  esac
  # Whether the before/after snapshots show the effect.
  jq -e -n --argjson b "$before" --argjson a "$after" --arg r "$argument" \
    "$observed" >/dev/null
}
