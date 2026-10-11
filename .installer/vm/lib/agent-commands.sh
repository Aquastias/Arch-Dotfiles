#!/usr/bin/env bash
# =============================================================================
# vm/lib/agent-commands.sh — VM Agent Control pure helpers (ADR 0117)
# =============================================================================
# The decisions vm-agent.sh makes without libvirt or SSH: VM name resolution,
# session/autologin/screenshot/pull/network guest commands, and the QMP key and
# pointer payloads. Unit-tested by tests/vm/vm-agent.bats via vm-agent.sh.
#
# Used by: vm/vm-agent.sh (sources it; supplies CACHE_DIR, INSTALLER_DIR and
# the AGENT_* settings).
# =============================================================================

# agent_key_path — the harness SSH key, identical to flow-persistent's.
agent_key_path() { printf '%s\n' "${CACHE_DIR}/harness_ed25519"; }

# agent_ssh_mux_options <dir> — client ssh options that ride a shared master
# connection when one is up (else ssh connects directly). ufw's `limit ssh`
# rejects a 6th connection in 30s, and the harness runs one command per call.
# ServerAlive drops a master whose guest rebooted.
agent_ssh_mux_options() {
  printf -- '-o\n%s\n' "ControlPath=$1/%C" ServerAliveInterval=5 \
    ServerAliveCountMax=2
}

# _agent_mux_directory — private socket dir for agent_ssh_mux_options.
_agent_mux_directory() {
  local d="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/vm-agent-mux"
  mkdir -p "$d" && chmod 700 "$d" && printf '%s\n' "$d"
}

# agent_resolve_name <selector> — VM domain name from a --profile ref (read
# .name from the profile jsonc) or a bare --vm name (verbatim).
agent_resolve_name() {
  local kind="$1" ref="$2"
  if [[ "$kind" == vm ]]; then printf '%s\n' "$ref"; return 0; fi
  local file
  if [[ "$ref" == /* && -f "$ref" ]]; then file="$ref"
  else file="$INSTALLER_DIR/vm/profiles/$ref.jsonc"; fi
  [[ -f "$file" ]] || die "profile not found: $file"
  jsonc_strip "$file" | jq -er '.name' \
    || die "profile has no .name: $file"
}

# agent_session_desktop <niri|hyprland|kde> — the DM Session= .desktop id.
agent_session_desktop() {
  case "$1" in
    niri)     printf 'niri.desktop\n' ;;
    hyprland) printf 'hyprland.desktop\n' ;;
    kde)      printf 'plasma.desktop\n' ;;
    *)        return 1 ;;
  esac
}

# agent_session_command <niri|hyprland|kde> — the greetd initial_session command
# (its session launcher; hyprland via start-hyprland, ADR 0070).
agent_session_command() {
  case "$1" in
    niri)     printf 'niri-session\n' ;;
    hyprland) printf 'start-hyprland\n' ;;
    kde)      printf 'startplasma-wayland\n' ;;
    *)        return 1 ;;
  esac
}

# agent_autologin_config <sddm|greetd> <session> <user> — the autologin config
# body for the resolved greeter (ADR 0069/0091). sddm → a drop-in [Autologin]
# block; greetd → an [initial_session] table.
agent_autologin_config() {
  local dm="$1" session="$2" user="$3"
  case "$dm" in
    sddm)
      printf '[Autologin]\nUser=%s\nSession=%s\nRelogin=true\n' \
        "$user" "$(agent_session_desktop "$session")" ;;
    greetd)
      printf '[initial_session]\ncommand = "%s"\nuser = "%s"\n' \
        "$(agent_session_command "$session")" "$user" ;;
    *) return 1 ;;
  esac
}

# agent_bake_blank_command — guest command that re-takes @blank on an
# impermanence guest (no-op elsewhere). Its /etc rolls back on boot, so an
# autologin edit not baked into @blank is lost on the reboot (ADR 0144).
agent_bake_blank_command() {
  local h=/usr/lib/impermanence/resnapshot.sh
  printf "sh -c '[ ! -x %s ] || %s'\n" "$h" "$h"
}

# agent_shot_tool <compositor> — screenshot tool for the running compositor.
agent_shot_tool() {
  case "$1" in
    kwin_wayland) printf 'spectacle\n' ;;
    niri|Hyprland) printf 'grim\n' ;;
    *) return 1 ;;
  esac
}

# agent_pull_command <abs-guest-path> — guest command streaming the path as a
# tar (relative to its parent) so `pull` lands it under the host dir by
# basename.
agent_pull_command() {
  local path="${1%/}" parent
  [[ "$path" == /* && "$path" != / ]] || return 1
  parent="${path%/*}"
  printf "tar -C '%s' -cf - '%s'\n" "${parent:-/}" "${path##*/}"
}

# agent_network_command <on|off> — guest (root) command cutting/restoring
# internet while host↔guest SSH stays up: drop the default route (saved) / put
# it back. A link-down would sever the very SSH channel driving the guest.
agent_network_command() {
  local s=/run/vm-agent-default-route
  case "$1" in
    off) printf '%s' "sh -c '[ -s $s ] || ip route show default > $s;" \
           " ip route del default 2>/dev/null; true'" ;;
    on)  printf '%s' "sh -c '[ -s $s ] && while read -r r;" \
           " do ip route replace \$r; done < $s; rm -f $s; true'" ;;
    *) return 1 ;;
  esac
  printf '\n'
}

# agent_key_qcodes <chord> — xkb-style chord (Mod+Shift+Return) → QEMU qcodes
# in press order. Mod/Super/Meta/Win are the logo key. Fails on a key QEMU
# cannot inject (brightness, mic-mute, ...), so a caller can mark it SKIP.
agent_key_qcodes() {
  local tok q; local -a qs=()
  local IFS=+
  for tok in $1; do
    tok="${tok// /}"
    case "${tok,,}" in
      mod|super|meta|win|logo) q=meta_l ;;
      ctrl|control) q=ctrl ;;  shift) q="shift" ;;  alt) q=alt ;;
      return|enter) q=ret ;;  escape|esc) q=esc ;;  space) q=spc ;;
      tab) q=tab ;;  backspace) q=backspace ;;  delete) q=delete ;;
      left|right|up|down|home|end|insert) q="${tok,,}" ;;
      page_up|prior|pageup|pgup) q=pgup ;;
      page_down|next|pagedown|pgdown|pgdn) q=pgdn ;;
      print) q=print ;;  minus) q=minus ;;  equal) q=equal ;;
      bracketleft) q=bracket_left ;;  bracketright) q=bracket_right ;;
      comma) q=comma ;;  period) q="dot" ;;  slash) q=slash ;;
      backslash) q=backslash ;;  semicolon) q=semicolon ;;
      apostrophe) q=apostrophe ;;  grave) q=grave_accent ;;
      xf86audioraisevolume|volumeup) q=volumeup ;;
      xf86audiolowervolume|volumedown) q=volumedown ;;
      xf86audiomute|volumemute) q=audiomute ;;
      xf86audioplay|mediaplay) q=audioplay ;;
      xf86audionext|medianext) q=audionext ;;
      xf86audioprev|mediaprevious) q=audioprev ;;
      xf86audiostop|mediastop) q=audiostop ;;
      plus) q="shift equal" ;;  '~'|asciitilde) q="shift grave_accent" ;;
      '`') q=grave_accent ;;  '=') q=equal ;;  '-') q=minus ;;
      [a-z0-9]) q="${tok,,}" ;;
      f[0-9]|f1[0-2]) q="${tok,,}" ;;
      *) return 1 ;;
    esac
    qs+=("$q")
  done
  local IFS=' '
  printf '%s\n' "${qs[*]}"
}

# agent_key_qmp <down|up> "<qcodes>" — the QMP input-send-event batch;
# releases go in reverse so modifiers are held around the key.
agent_key_qmp() {
  local dir="$1" codes="$2"
  jq -cn --arg d "$dir" --arg c "$codes" '
    ($c | split(" ") | if $d == "up" then reverse else . end) as $k
    | { execute: "input-send-event",
        arguments: { events: [ $k[] | { type: "key",
          data: { down: ($d == "down"),
                  key: { type: "qcode", data: . } } } ] } }'
}

# agent_mouse_qmp move <x> <y> | btn <left|right|middle> <down|up>
#   | wheel <up|down> — QMP pointer events (absolute tablet, 0..32767).
agent_mouse_qmp() {
  case "$1" in
    move)
      jq -cn --argjson x "$2" --argjson y "$3" '{ execute: "input-send-event",
        arguments: { events: [
          { type: "abs", data: { axis: "x", value: $x } },
          { type: "abs", data: { axis: "y", value: $y } } ] } }' ;;
    btn)
      [[ "$2" =~ ^(left|right|middle)$ && "$3" =~ ^(down|up)$ ]] || return 1
      jq -cn --arg b "$2" --arg d "$3" '{ execute: "input-send-event",
        arguments: { events: [ { type: "btn",
          data: { down: ($d == "down"), button: $b } } ] } }' ;;
    wheel)
      [[ "$2" =~ ^(up|down)$ ]] || return 1
      jq -cn --arg b "wheel-$2" '{ execute: "input-send-event",
        arguments: { events: [
          { type: "btn", data: { down: true, button: $b } },
          { type: "btn", data: { down: false, button: $b } } ] } }' ;;
    *) return 1 ;;
  esac
}

# _agent_remote_environment_function — a guest-side bash fragment defining
# _agent_load_env, which finds the running compositor and exports its session
# environment (read from /proc/<pid>/environ) so exec/launch/shot reach the
# live session.
_agent_remote_environment_function() {
  cat <<'SH'
_agent_load_env() {
  local c comp="" cpid="" client clpid="" src kv sock
  # Identify the running compositor (for tool selection + Qt theme).
  for c in niri Hyprland kwin_wayland; do
    cpid="$(pgrep -x "$c" 2>/dev/null | head -1)"
    if [ -n "$cpid" ]; then comp="$c"; break; fi
  done
  [ -n "$comp" ] || return 1
  AGENT_COMPOSITOR="$comp"
  # Source the session env from a real CLIENT — the compositor *server* has no
  # WAYLAND_DISPLAY of its own. noctalia (wlroots) / plasmashell (KDE).
  # XDG_SESSION_TYPE comes from the client (=wayland), NOT our SSH pty (=tty):
  # a leaked `tty` makes browsers/Electron skip the ScreenCast portal and fall
  # back to internal window-capture (no full-screen), faking a portal failure.
  for client in noctalia plasmashell waybar; do
    clpid="$(pgrep -x "$client" 2>/dev/null | head -1)"
    [ -n "$clpid" ] && break
  done
  src="${clpid:-$cpid}"
  while IFS= read -r -d '' kv; do
    case "$kv" in
      XDG_RUNTIME_DIR=*|WAYLAND_DISPLAY=*|DBUS_SESSION_BUS_ADDRESS=*|\
DISPLAY=*|XAUTHORITY=*|XDG_CURRENT_DESKTOP=*|\
XDG_SESSION_TYPE=*|NIRI_SOCKET=*|HYPRLAND_INSTANCE_SIGNATURE=*|\
LANG=*|LANGUAGE=*|LC_*=*) export "$kv" ;;
    esac
  done < "/proc/$src/environ" 2>/dev/null || true
  # Fallbacks so a server-only source still yields a usable env.
  : "${XDG_RUNTIME_DIR:=/run/user/$(id -u)}"; export XDG_RUNTIME_DIR
  if [ -z "${WAYLAND_DISPLAY:-}" ]; then
    sock="$(ls "$XDG_RUNTIME_DIR"/wayland-* 2>/dev/null \
      | grep -v '\.lock$' | head -1)"
    [ -n "$sock" ] && export WAYLAND_DISPLAY="${sock##*/}"
  fi
  : "${DBUS_SESSION_BUS_ADDRESS:=unix:path=$XDG_RUNTIME_DIR/bus}"
  # the system locale when the client carried none (Qt falls back to C)
  if [ -z "${LANG:-}" ] && [ -r /etc/locale.conf ]; then
    set -a; . /etc/locale.conf; set +a
  fi
  export DBUS_SESSION_BUS_ADDRESS GDK_BACKEND=wayland
  # Qt platform theme is fleet-set per-compositor for wlroots (ADR 0102); KDE
  # uses its own (plasma-integration), so only default it under niri/Hyprland.
  case "$comp" in niri|Hyprland) : "${QT_QPA_PLATFORMTHEME:=qt6ct}";
    export QT_QPA_PLATFORMTHEME ;; esac
  return 0
}
SH
}
