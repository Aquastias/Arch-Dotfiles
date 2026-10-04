#!/usr/bin/env bash
# =============================================================================
# vm/vm-agent.sh — host-side VM Agent Control CLI (ADR 0117)
# =============================================================================
# Drives a persistent-flow Agent-Controllable VM over the harness SSH key so an
# agent can log in to any session, run/screenshot/lock things, and reboot —
# without rediscovering the plumbing each time. Sibling of vm.sh; selects the VM
# the same way (--profile <cat>/<name>) or by domain name (--vm <name>).
#
#   vm-agent.sh [--profile <cat>/<name> | --vm <name>] <verb> [args…]
#
# Verbs (ADR 0117):
#   exec <cmd…>              run a command in the guest with the running
#                            session's env auto-sourced (WAYLAND_DISPLAY, DBUS…)
#   launch <app…>            launch a GUI app detached (never holds the channel)
#   ssh [cmd…]               interactive guest shell (or one-off command)
#   ready [timeout]          block until the session's compositor is up
#   session <niri|hyprland|kde>   switch autologin session + reboot + wait-ready
#   greeter                  remove the CLI autologin → boot to the DM greeter
#   logout                   loginctl terminate-session (fresh re-autologin)
#   reboot                   reboot + wait-ready
#   idle <on|off>            toggle a removable idle/suspend/DPMS inhibitor
#   lock | unlock            loginctl lock-session / unlock-session
#   shot [file]              screenshot (grim on wlroots, spectacle on KDE) →host
#   pull <guest-path> <dir>  copy a guest file/dir (as root) into <dir>
#   sudo [cmd…]              run cmd (or stdin script) as root
#   push <host-path> <dir>   copy a host file/dir into a guest dir (as user)
#   net <on|off>             cut/restore guest internet (SSH stays up)
#   key <chord> [hold-ms]    press a chord as real keyboard input (QMP)
#   keydown|keyup <chord>    hold / release a chord (wraps pointer input)
#   mouse move|btn|wheel …  real pointer input (QMP, absolute 0..32767)
#
# SSH uses the harness key (vm/.vm-cache/harness_ed25519, same as the persistent
# flow). Privileged guest steps pipe the harness sudo password (default 12345,
# override VM_AGENT_SUDO_PW). virsh/ssh obey docs/agents/vm-sandbox.md: on a
# `libvirt unreachable (sandbox?)` signal, the agent retries with the sandbox
# disabled.
# =============================================================================

set -Eeuo pipefail

SELF_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
INSTALLER_DIR="${INSTALLER_DIR:-$(cd "$SELF_DIR/.." && pwd)}"
# shellcheck source=../lib/jsonc.sh
source "$INSTALLER_DIR/lib/jsonc.sh"

# CACHE_DIR + key path MUST match flow-persistent.sh so we use the SAME harness
# key it authorized on the guest.
: "${CACHE_DIR:=$SELF_DIR/.vm-cache}"
AGENT_PROFILE_DEFAULT="${VM_AGENT_PROFILE:-desktop/combined}"
AGENT_USER="${VM_AGENT_USER:-aquastias}"
AGENT_SUDO_PW="${VM_AGENT_SUDO_PW:-12345}"
AGENT_READY_TIMEOUT="${VM_AGENT_READY_TIMEOUT:-180}"
AGENT_SHUTDOWN_GRACE="${VM_AGENT_SHUTDOWN_GRACE:-240}"

die() { echo "vm-agent: $*" >&2; exit 1; }
info() { echo "vm-agent: $*" >&2; }

usage() {
  sed -n '4,37p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# ── pure helpers (unit-tested; no libvirt, no SSH) ───────────────────────────

# agent_key_path — the harness SSH key, identical to flow-persistent's.
agent_key_path() { printf '%s\n' "${CACHE_DIR}/harness_ed25519"; }

# agent_ssh_mux_opts <dir> — client ssh options that ride a shared master
# connection when one is up (else ssh connects directly). ufw's `limit ssh`
# rejects a 6th connection in 30s, and the harness runs one command per call.
# ServerAlive drops a master whose guest rebooted.
agent_ssh_mux_opts() {
  printf -- '-o\n%s\n' "ControlPath=$1/%C" ServerAliveInterval=5 \
    ServerAliveCountMax=2
}

# _agent_mux_dir — private socket dir for agent_ssh_mux_opts.
_agent_mux_dir() {
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

# agent_bake_blank_cmd — guest command that re-takes @blank on an impermanence
# guest (no-op elsewhere). Its /etc rolls back on boot, so an autologin edit
# not baked into @blank is lost on the reboot (ADR 0144).
agent_bake_blank_cmd() {
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

# agent_pull_cmd <abs-guest-path> — guest command streaming the path as a tar
# (relative to its parent) so `pull` lands it under the host dir by basename.
agent_pull_cmd() {
  local p="${1%/}"
  [[ "$p" == /* && "$p" != / ]] || return 1
  printf "tar -C '%s' -cf - '%s'\n" "${p%/*}" "${p##*/}" \
    | sed "s|-C ''|-C '/'|"
}

# agent_net_cmd <on|off> — guest (root) command cutting/restoring internet
# while host↔guest SSH stays up: drop the default route (saved) / put it back.
# A link-down would sever the very SSH channel driving the guest.
agent_net_cmd() {
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

# _remote_env_fn — a guest-side bash fragment defining _agent_load_env, which
# finds the running compositor and exports its session environment (read from
# /proc/<pid>/environ) so exec/launch/shot reach the live session.
_remote_env_fn() {
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

# ── connection (libvirt + ssh) ───────────────────────────────────────────────

_vm_ip() {
  virsh domifaddr "$VM_NAME" 2>/dev/null \
    | awk 'NR>2 { split($4,a,"/"); if (a[1] ~ /^[0-9]/) print a[1] }' | head -1
}

# _preflight — confirm libvirt is reachable and the VM is running, emitting the
# vm-sandbox.md signal so the agent knows to retry with the sandbox disabled.
_preflight() {
  if ! virsh version >/dev/null 2>&1; then
    die "libvirt unreachable (sandbox?) — retry with the sandbox disabled"
  fi
  virsh domstate "$VM_NAME" 2>/dev/null | grep -qx running \
    || die "VM '$VM_NAME' is not running (virsh start it, or check the name)"
}

_ssh() {
  local ip; ip="$(_vm_ip)"
  [[ -n "$ip" ]] || die "no DHCP lease for '$VM_NAME' yet"
  local -a mux; mapfile -t mux < <(agent_ssh_mux_opts "$(_agent_mux_dir)")
  # The master is started detached with stdio on /dev/null: one forked by a
  # client (ControlMaster=auto) keeps the caller's stderr open and hangs $(…).
  ssh "${mux[@]}" -O check "$AGENT_USER@$ip" >/dev/null 2>&1 \
    || ssh -i "$(agent_key_path)" "${mux[@]}" -fN -o ControlMaster=yes \
      -o ControlPersist=60 -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o LogLevel=ERROR \
      "$AGENT_USER@$ip" </dev/null >/dev/null 2>&1 || true
  ssh -i "$(agent_key_path)" "${mux[@]}" -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o LogLevel=ERROR \
    "$AGENT_USER@$ip" "$@"
}

# _ssh_tty — interactive (allocate a TTY).
_ssh_tty() {
  local ip; ip="$(_vm_ip)"
  [[ -n "$ip" ]] || die "no DHCP lease for '$VM_NAME' yet"
  ssh -t -i "$(agent_key_path)" -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR "$AGENT_USER@$ip" "$@"
}

# _sudo <cmd…> — run a privileged guest command, piping the harness pw from the
# host (kept out of the remote argv/process list).
_sudo() {
  printf '%s\n' "$AGENT_SUDO_PW" | _ssh "sudo -S -p '' $*"
}

# _stage <guest-path> — write this function's stdin to a user-writable guest
# path, for staging a file we then install as root.
_stage() { _ssh "cat > '$1'"; }

# _in_session <cmd…> — run a command on the guest inside the live session env.
_in_session() {
  _ssh "bash -s" <<REMOTE
set -e
$(_remote_env_fn)
_agent_load_env || { echo 'vm-agent: no live session on guest' >&2; exit 3; }
$*
REMOTE
}

# ── guest DM detection (for session control) ─────────────────────────────────
_guest_dm() {
  _ssh 'readlink -f /etc/systemd/system/display-manager.service 2>/dev/null' \
    | grep -oE 'sddm|greetd' | head -1
}

# ── verbs ────────────────────────────────────────────────────────────────────

# agent_ready_check <user> — guest shell test for a usable session: the
# user's compositor runs AND serves its Wayland socket. A bare process can
# predate its VT takeover; input sent then lands on the text console, where
# Ctrl+Alt+Del reboots the box. The user filter skips an SDDM greeter's kwin.
agent_ready_check() {
  printf '%s' "pgrep -u $1 -x 'niri|Hyprland|kwin_wayland' >/dev/null 2>&1 \
&& ls /run/user/\$(id -u $1)/wayland-[0-9] >/dev/null 2>&1"
}

verb_ready() {
  local timeout="${1:-$AGENT_READY_TIMEOUT}" elapsed=0
  info "waiting for a session on '$VM_NAME' (≤${timeout}s)…"
  while ((elapsed < timeout)); do
    if _ssh "$(agent_ready_check "$AGENT_USER")" 2>/dev/null
    then info "session up."; return 0; fi
    sleep 5; elapsed=$((elapsed + 5))
  done
  die "timed out waiting for a session on '$VM_NAME'"
}

verb_exec() {
  (($#)) || die "exec needs a command"
  _in_session "$*"
}

verb_launch() {
  (($#)) || die "launch needs an app"
  # A missing app fails here, not as a silent no-op the caller screenshots.
  _in_session "command -v $1 >/dev/null \
    || { echo 'vm-agent: $1 not installed' >&2; exit 5; }
    setsid -f $* </dev/null >/dev/null 2>&1" || die "cannot launch $1"
  info "launched: $*"
}

verb_ssh() {
  if (($#)); then _ssh_tty "$@"; else _ssh_tty; fi
}

verb_reboot() {
  local boot=/proc/sys/kernel/random/boot_id old id elapsed=0
  old="$(_ssh "cat $boot" 2>/dev/null)" || old=""
  info "rebooting '$VM_NAME'…"
  _sudo systemctl reboot || true
  # Wait for the NEW boot: a fixed sleep could still see the old session. A
  # virgl GPU stall can wedge shutdown (D-state GPU clients): past the grace,
  # hard-reset the domain once.
  while ((elapsed < AGENT_READY_TIMEOUT + AGENT_SHUTDOWN_GRACE)); do
    id="$(_ssh "cat $boot" 2>/dev/null)" || id=""
    [[ -n "$id" && "$id" != "$old" ]] && break
    if ((elapsed == AGENT_SHUTDOWN_GRACE)); then
      info "shutdown wedged ${elapsed}s (virgl stall?) — resetting the VM…"
      virsh reset "$VM_NAME" >/dev/null 2>&1 || true
    fi
    sleep 5; elapsed=$((elapsed + 5))
  done
  verb_ready
}

verb_logout() {
  # Terminate ONLY the graphical (seat0) session — never the agent's own SSH
  # session (which has no seat). Relogin autologins a fresh graphical session.
  info "logging out (terminating the graphical session)…"
  local gid
  gid="$(_ssh "loginctl list-sessions --no-legend \
    | awk '\$4==\"seat0\"{print \$1; exit}'")"
  [[ -n "$gid" ]] || die "no graphical (seat0) session to terminate"
  _sudo "loginctl terminate-session $gid" || true
  sleep 6
  verb_ready
}

verb_session() {
  local target="${1:-}"
  agent_session_desktop "$target" >/dev/null \
    || die "session must be niri|hyprland|kde"
  local dm; dm="$(_guest_dm)"
  [[ -n "$dm" ]] || die "could not detect the guest display manager"
  local cfg; cfg="$(agent_autologin_config "$dm" "$target" "$AGENT_USER")"
  info "setting $dm autologin → $target, then rebooting…"
  case "$dm" in
    sddm)
      # A CLI-owned drop-in, named to sort LAST in /etc/sddm.conf.d so it wins:
      # sddm merges alphabetically (last wins), and the seeded kde_settings.conf
      # (empty Autologin) sorts after a 99-* name ('9' < 'k'), so use zz-*.
      printf '%s\n' "$cfg" | _stage /tmp/vm-agent-autologin.conf
      _sudo "install -Dm0644 /tmp/vm-agent-autologin.conf \
        /etc/sddm.conf.d/zz-agent-autologin.conf"
      _ssh "rm -f /tmp/vm-agent-autologin.conf" || true ;;
    greetd)
      # Rewrite greetd's [initial_session] table, keeping the rest of the file.
      # No python (repo policy): a staged bash+awk script splices the block in at
      # the table's position, or appends it when the table is absent.
      { printf '%s\n' "$cfg"; } | _stage /tmp/vm-agent-greetd-block
      _stage /tmp/vm-agent-greetd.sh <<'SH'
#!/usr/bin/env bash
set -euo pipefail
cfg=/etc/greetd/config.toml
blk=/tmp/vm-agent-greetd-block
if grep -q '^\[initial_session\]' "$cfg"; then
  awk -v b="$blk" '
    BEGIN { while ((getline l < b) > 0) B = B l ORS }
    /^\[initial_session\]/ { printf "%s", B; skip = 1; next }
    skip && /^\[/          { skip = 0 }
    skip                  { next }
    { print }' "$cfg" > "$cfg.n"
else
  { cat "$cfg"; printf '\n'; cat "$blk"; } > "$cfg.n"
fi
install -Dm644 "$cfg.n" "$cfg"
rm -f "$cfg.n"
SH
      _sudo "bash /tmp/vm-agent-greetd.sh"
      _ssh "rm -f /tmp/vm-agent-greetd.sh /tmp/vm-agent-greetd-block" || true ;;
  esac
  _sudo "$(agent_bake_blank_cmd)"
  verb_reboot
}

# Remove the CLI-owned autologin so the box boots to its DM greeter (for testing
# greeter bugs) — the inverse of `session`. Does NOT wait-ready afterwards: with
# autologin gone there is no graphical session to become ready, so it restarts
# the display manager and returns. `session <de>` re-arms autologin.
verb_greeter() {
  local dm; dm="$(_guest_dm)"
  [[ -n "$dm" ]] || die "could not detect the guest display manager"
  info "removing $dm autologin → greeter…"
  case "$dm" in
    # sddm reads EVERY file in .conf.d (not just *.conf), so delete the drop-in
    # outright — renaming it would leave it active.
    sddm) _sudo "rm -f /etc/sddm.conf.d/zz-agent-autologin.conf" ;;
    greetd)
      _stage /tmp/vm-agent-greetd-degreet.sh <<'SH'
#!/usr/bin/env bash
set -euo pipefail
cfg=/etc/greetd/config.toml
awk '
  /^\[initial_session\]/ { skip = 1; next }
  skip && /^\[/          { skip = 0 }
  skip                  { next }
  { print }' "$cfg" > "$cfg.n"
install -Dm644 "$cfg.n" "$cfg"; rm -f "$cfg.n"
SH
      _sudo "bash /tmp/vm-agent-greetd-degreet.sh"
      _ssh "rm -f /tmp/vm-agent-greetd-degreet.sh" || true ;;
  esac
  _sudo "$(agent_bake_blank_cmd)"
  _sudo "systemctl restart display-manager" || _sudo "systemctl reboot" || true
  info "$dm greeter shown — log in at the console (agent desktop control needs \
'session <de>' to re-arm autologin)."
}

verb_idle() {
  local state="${1:-}"
  case "$state" in
    off)
      # Removable inhibitor: a detached logind idle/sleep hold (covers
      # suspend/DPMS) + Noctalia caffeine (covers the wlroots compositor lock,
      # ADR 0100). Both are reversible by `idle on` — nothing is provisioned off.
      _in_session "setsid -f systemd-inhibit \
        --what=idle:sleep:handle-lid-switch --who=vm-agent \
        --why=agent-driving --mode=block sleep infinity \
        </dev/null >/dev/null 2>&1 || true; \
        command -v noctalia >/dev/null 2>&1 && noctalia msg caffeine-enable \
        >/dev/null 2>&1 || true"
      info "idle inhibited (reversible)." ;;
    on)
      _in_session "pkill -f 'systemd-inhibit .*who=vm-agent' 2>/dev/null; \
        command -v noctalia >/dev/null 2>&1 && noctalia msg caffeine-disable \
        >/dev/null 2>&1 || true"
      info "idle restored." ;;
    *) die "idle needs on|off" ;;
  esac
}


# pull <abs-guest-path> <host-dir> — copy a guest file/dir (read as root, so
# root-only logs work) into <host-dir>/<basename> (Feature Audit, ADR 0152).
verb_pull() {
  local src="${1:-}" dest="${2:-}" cmd
  cmd="$(agent_pull_cmd "$src")" || die "pull needs an absolute guest path"
  [[ -n "$dest" ]] || die "pull needs a host dir"
  mkdir -p "$dest"
  _sudo "$cmd" | tar -C "$dest" -xf - || die "pull failed: $src"
}

# sudo [cmd…] — run a command as root; with no args, run stdin as a root bash
# script (staged, since stdin also carries the sudo password).
verb_sudo() {
  if (($#)); then _sudo "$*"; return; fi
  local s="/tmp/vm-agent-sudo.$$.sh"
  _stage "$s"
  _sudo "bash $s"; local rc=$?
  _ssh "rm -f $s" || true
  return "$rc"
}

# push <host-path> <guest-dir> — copy a host file/dir into a user-writable
# guest dir (as the agent user); the inverse of pull.
verb_push() {
  local src="${1:-}" dest="${2:-}"
  [[ -e "$src" && -n "$dest" ]] || die "push needs <host-path> <guest-dir>"
  tar -C "$(dirname "$src")" -cf - "$(basename "$src")" \
    | _ssh "mkdir -p '$dest' && tar -C '$dest' -xf -" \
    || die "push failed: $src"
}

# net <on|off> — cut/restore the guest's internet, keeping SSH (Feature
# Audit offline probes, ADR 0152).
verb_net() {
  local cmd; cmd="$(agent_net_cmd "${1:-}")" || die "net needs on|off"
  _sudo "$cmd"
  info "network ${1}."
}

# key <chord> [hold-ms] — press a chord as real keyboard input (QMP
# input-send-event: modifiers held around the key), so compositor binds see
# exactly what a human's keyboard sends (Feature Audit keybinds, ADR 0152).
verb_key() {
  local codes
  codes="$(agent_key_qcodes "${1:-}")" \
    || die "key: '${1:-}' is not injectable by QEMU"
  virsh qemu-monitor-command "$VM_NAME" "$(agent_key_qmp down "$codes")" \
    >/dev/null || die "key press failed"
  sleep "$(awk -v m="${2:-120}" 'BEGIN { printf "%.3f", m / 1000 }')"
  virsh qemu-monitor-command "$VM_NAME" "$(agent_key_qmp up "$codes")" \
    >/dev/null || die "key release failed"
}

# mouse move <x> <y> | btn <b> <down|up> | wheel <up|down> — real pointer
# input via QMP (absolute coordinates 0..32767).
verb_mouse() {
  local j; j="$(agent_mouse_qmp "$@")" || die "mouse: bad arguments"
  virsh qemu-monitor-command "$VM_NAME" "$j" >/dev/null \
    || die "mouse event failed"
}

# keydown <chord> / keyup <chord> — hold / release a chord, to wrap pointer
# input (Super+drag, Super+wheel binds).
verb_keydown() {
  local c; c="$(agent_key_qcodes "${1:-}")" || die "keydown: not injectable"
  virsh qemu-monitor-command "$VM_NAME" "$(agent_key_qmp down "$c")" \
    >/dev/null || die "keydown failed"
}
verb_keyup() {
  local c; c="$(agent_key_qcodes "${1:-}")" || die "keyup: not injectable"
  virsh qemu-monitor-command "$VM_NAME" "$(agent_key_qmp up "$c")" \
    >/dev/null || die "keyup failed"
}
verb_lock()   { _sudo "loginctl lock-sessions";   info "locked."; }
verb_unlock() { _sudo "loginctl unlock-sessions"; info "unlocked."; }

verb_shot() {
  local out="${1:-vm-agent-shot.png}"
  local guest_png="/tmp/vm-agent-shot.$$.png"
  # Shell-less wlroots hosts ship no grim; it is our capture tool, not the
  # product's, so bring it (the host screendump has no surface under GL).
  _ssh "command -v grim >/dev/null" \
    || _sudo "pacman -S --noconfirm --needed grim" >/dev/null 2>&1 || true
  # Detect compositor, wake the display, capture with the right tool.
  _in_session "
    (command -v noctalia >/dev/null && noctalia msg dpms-on) 2>/dev/null || true
    tool=\$(case \"\$AGENT_COMPOSITOR\" in
      kwin_wayland) echo spectacle;; niri|Hyprland) echo grim;; esac)
    case \"\$tool\" in
      grim)      timeout 12 grim '$guest_png' ;;
      spectacle) timeout 15 spectacle -bnf -o '$guest_png' ;;
      *) echo 'vm-agent: unknown compositor, cannot screenshot' >&2; exit 4 ;;
    esac" || die "screenshot failed (display asleep or render stalled?)"
  local ip; ip="$(_vm_ip)"
  scp -i "$(agent_key_path)" -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
    "$AGENT_USER@$ip:$guest_png" "$out" >/dev/null \
    || die "failed to pull screenshot"
  _ssh "rm -f '$guest_png'" || true
  info "screenshot → $out"
}

# ── main ─────────────────────────────────────────────────────────────────────

main() {
  local sel_kind=profile sel_ref="$AGENT_PROFILE_DEFAULT"
  while (($#)); do
    case "$1" in
      --profile) sel_kind=profile; sel_ref="${2:-}"; shift 2 ;;
      --profile=*) sel_kind=profile; sel_ref="${1#*=}"; shift ;;
      --vm) sel_kind=vm; sel_ref="${2:-}"; shift 2 ;;
      --vm=*) sel_kind=vm; sel_ref="${1#*=}"; shift ;;
      --user) AGENT_USER="${2:-}"; shift 2 ;;
      --help|-h) usage; return 0 ;;
      --) shift; break ;;
      -*) usage >&2; die "unknown option '$1'" ;;
      *) break ;;
    esac
  done

  local verb="${1:-}"; shift || true
  [[ -n "$verb" ]] || { usage >&2; die "a verb is required"; }

  VM_NAME="$(agent_resolve_name "$sel_kind" "$sel_ref")"

  case "$verb" in
    exec|launch|ssh|ready|session|greeter|logout|reboot|idle|lock|unlock|shot\
    |pull|push|sudo|net|key|keydown|keyup|mouse) ;;
    *) usage >&2; die "unknown verb '$verb'" ;;
  esac

  _preflight
  "verb_${verb}" "$@"
}

# Source-guard so the bats suite can source and call the pure helpers.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then main "$@"; fi
