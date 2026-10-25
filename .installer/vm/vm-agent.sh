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
#   status                   VM state + IP, and any other running VM
#   start | stop             boot (one VM at a time, ADR 0155) / shut down
#   exec <cmd…>              run a command in the guest with the running
#                            session's env auto-sourced (WAYLAND_DISPLAY, DBUS…)
#   launch <app…>            launch a GUI app detached (never holds the channel)
#   ssh [cmd…]               interactive guest shell (or one-off command)
#   ready [timeout]          block until the session's compositor is up
#   session <niri|hyprland|kde|umbriel>
#                            switch autologin session + reboot + wait-ready
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
  awk 'NR >= 4 && NR <= 39 { sub(/^# ?/, ""); print }' "${BASH_SOURCE[0]}"
}

# shellcheck source=lib/agent-commands.sh
source "$SELF_DIR/lib/agent-commands.sh"
# shellcheck source=lib/agent-lifecycle.sh
source "$SELF_DIR/lib/agent-lifecycle.sh"

# ── connection (libvirt + ssh) ───────────────────────────────────────────────

_vm_ip() {
  virsh domifaddr "$VM_NAME" 2>/dev/null \
    | awk \
    'NR>2 { split($4, a, "/"); if (a[1] ~ /^[0-9]/) { print a[1]; exit } }'
}

# _preflight [any-state] — confirm libvirt is reachable and (unless any-state)
# the VM is running, emitting the vm-sandbox.md signal so the agent knows to
# retry with the sandbox disabled.
_preflight() {
  if ! virsh version >/dev/null 2>&1; then
    die "libvirt unreachable (sandbox?) — retry with the sandbox disabled"
  fi
  [[ "${1:-}" == any-state ]] && return 0
  virsh domstate "$VM_NAME" 2>/dev/null | grep -qx running \
    || die "VM '$VM_NAME' is not running (\`start\` it, or check the name)"
}

_ssh() {
  local ip; ip="$(_vm_ip)"
  [[ -n "$ip" ]] || die "no DHCP lease for '$VM_NAME' yet"
  local -a mux; mapfile -t mux < <(agent_ssh_mux_options "$(_agent_mux_directory)")
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
$(_agent_remote_environment_function)
_agent_load_env || { echo 'vm-agent: no live session on guest' >&2; exit 3; }
$*
REMOTE
}

# ── guest DM detection (for session control) ─────────────────────────────────
_guest_display_manager() {
  _ssh 'readlink -f /etc/systemd/system/display-manager.service 2>/dev/null' \
    | awk 'match($0, /sddm|greetd/) { print substr($0, RSTART, RLENGTH); exit }'
}

# ── verbs ────────────────────────────────────────────────────────────────────

# agent_ready_check <user> — guest shell test for a usable session: the
# user's compositor runs AND serves its Wayland socket. A bare process can
# predate its VT takeover; input sent then lands on the text console, where
# Ctrl+Alt+Del reboots the box. The user filter skips an SDDM greeter's kwin.
agent_ready_check() {
  printf '%s' "pgrep -u $1 -x 'niri|Hyprland|umbriel|kwin_wayland' \
>/dev/null 2>&1 && ls /run/user/\$(id -u $1)/wayland-[0-9] >/dev/null 2>&1"
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
  local app; app="$(printf '%q' "$1")"
  _in_session "command -v $app >/dev/null \
    || { echo vm-agent: $app not installed >&2; exit 5; }
    setsid -f $* </dev/null >/dev/null 2>&1" || die "cannot launch $1"
  info "launched: $*"
}

verb_ssh() {
  if (($#)); then _ssh_tty "$@"; else _ssh_tty; fi
}

verb_reboot() {
  local boot=/proc/sys/kernel/random/boot_id old id elapsed=0 down=0 reset=0
  old="$(_ssh "cat $boot" 2>/dev/null)" || old=""
  info "rebooting '$VM_NAME'…"
  _sudo systemctl reboot || true
  # Wait for the NEW boot: a fixed sleep could still see the old session (an
  # unknown old id is trusted only once the guest went down). A virgl GPU
  # stall can wedge shutdown (D-state GPU clients): past the grace, hard-reset
  # the domain once.
  while ((elapsed < AGENT_READY_TIMEOUT + AGENT_SHUTDOWN_GRACE)); do
    id="$(_ssh "cat $boot" 2>/dev/null)" || { id=""; down=1; }
    if [[ -n "$id" && "$id" != "$old" ]] && { [[ -n "$old" ]] || ((down)); }
    then break; fi
    if ((!reset && elapsed >= AGENT_SHUTDOWN_GRACE)); then
      info "shutdown wedged ${elapsed}s (virgl stall?) — resetting the VM…"
      virsh reset "$VM_NAME" >/dev/null 2>&1 || true
      reset=1
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
    || die "session must be niri|hyprland|kde|umbriel"
  local display_manager; display_manager="$(_guest_display_manager)"
  [[ -n "$display_manager" ]] \
    || die "could not detect the guest display manager"
  local autologin_config
  autologin_config="$(agent_autologin_config "$display_manager" "$target" \
    "$AGENT_USER")"
  info "setting $display_manager autologin → $target, then rebooting…"
  case "$display_manager" in
    sddm)
      # A CLI-owned drop-in, named to sort LAST in /etc/sddm.conf.d so it wins:
      # sddm merges alphabetically (last wins), and the seeded kde_settings.conf
      # (empty Autologin) sorts after a 99-* name ('9' < 'k'), so use zz-*.
      printf '%s\n' "$autologin_config" | _stage /tmp/vm-agent-autologin.conf
      _sudo "install -Dm0644 /tmp/vm-agent-autologin.conf \
        /etc/sddm.conf.d/zz-agent-autologin.conf"
      _ssh "rm -f /tmp/vm-agent-autologin.conf" || true ;;
    greetd)
      # Rewrite greetd's [initial_session] table, keeping the rest of the file.
      # No python (repo policy): a staged bash+awk script splices the block in at
      # the table's position, or appends it when the table is absent.
      { printf '%s\n' "$autologin_config"; } | _stage /tmp/vm-agent-greetd-block
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
  _sudo "$(agent_bake_blank_command)"
  verb_reboot
}

# Remove the CLI-owned autologin so the box boots to its DM greeter (for testing
# greeter bugs) — the inverse of `session`. Does NOT wait-ready afterwards: with
# autologin gone there is no graphical session to become ready, so it restarts
# the display manager and returns. `session <de>` re-arms autologin.
verb_greeter() {
  local display_manager; display_manager="$(_guest_display_manager)"
  [[ -n "$display_manager" ]] \
    || die "could not detect the guest display manager"
  info "removing $display_manager autologin → greeter…"
  case "$display_manager" in
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
  _sudo "$(agent_bake_blank_command)"
  _sudo "systemctl restart display-manager" || _sudo "systemctl reboot" || true
  info "$display_manager greeter shown — log in at the console" \
    "(agent desktop control needs 'session <de>' to re-arm autologin)."
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
  local source_path="${1:-}" dest="${2:-}" command_line
  command_line="$(agent_pull_command "$source_path")" \
    || die "pull needs an absolute guest path"
  [[ -n "$dest" ]] || die "pull needs a host dir"
  mkdir -p "$dest"
  _sudo "$command_line" | tar -C "$dest" -xf - \
    || die "pull failed: $source_path"
}

# sudo [cmd…] — run a command as root; with no args, run stdin as a root bash
# script (staged, since stdin also carries the sudo password).
verb_sudo() {
  if (($#)); then _sudo "$*"; return; fi
  local script_path="/tmp/vm-agent-sudo.$$.sh"
  _stage "$script_path"
  _sudo "bash $script_path"; local rc=$?
  _ssh "rm -f $script_path" || true
  return "$rc"
}

# push <host-path> <guest-dir> — copy a host file/dir into a user-writable
# guest dir (as the agent user); the inverse of pull.
verb_push() {
  local source_path="${1:-}" destination="${2:-}" parent
  [[ -e "$source_path" && -n "$destination" ]] \
    || die "push needs <host-path> <guest-dir>"
  while [[ "$source_path" == */ && "$source_path" != / ]]; do
    source_path="${source_path%/}"
  done
  parent=.
  [[ "$source_path" == */* ]] && parent="${source_path%/*}"
  tar -C "${parent:-/}" -cf - "${source_path##*/}" \
    | _ssh "mkdir -p '$destination' && tar -C '$destination' -xf -" \
    || die "push failed: $source_path"
}

# net <on|off> — cut/restore the guest's internet, keeping SSH (Feature
# Audit offline probes, ADR 0152).
verb_net() {
  local command_line; command_line="$(agent_network_command "${1:-}")" \
    || die "net needs on|off"
  _sudo "$command_line"
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
  local qcodes; qcodes="$(agent_key_qcodes "${1:-}")" \
    || die "keydown: not injectable"
  virsh qemu-monitor-command "$VM_NAME" "$(agent_key_qmp down "$qcodes")" \
    >/dev/null || die "keydown failed"
}
verb_keyup() {
  local qcodes; qcodes="$(agent_key_qcodes "${1:-}")" \
    || die "keyup: not injectable"
  virsh qemu-monitor-command "$VM_NAME" "$(agent_key_qmp up "$qcodes")" \
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
      kwin_wayland) echo spectacle;; niri|Hyprland|umbriel) echo grim;; esac)
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
  local selection_kind=profile selection_reference="$AGENT_PROFILE_DEFAULT"
  while (($#)); do
    case "$1" in
      --profile) selection_kind=profile; selection_reference="${2:-}"; shift \
        2 ;;
      --profile=*) selection_kind=profile; selection_reference="${1#*=}"; \
        shift ;;
      --vm) selection_kind=vm; selection_reference="${2:-}"; shift 2 ;;
      --vm=*) selection_kind=vm; selection_reference="${1#*=}"; shift ;;
      --user) AGENT_USER="${2:-}"; shift 2 ;;
      --help|-h) usage; return 0 ;;
      --) shift; break ;;
      -*) usage >&2; die "unknown option '$1'" ;;
      *) break ;;
    esac
  done

  local verb="${1:-}"; shift || true
  [[ -n "$verb" ]] || { usage >&2; die "a verb is required"; }

  VM_NAME="$(agent_resolve_name "$selection_kind" "$selection_reference")"

  case "$verb" in
    status|start|stop)
      _preflight any-state
      "agent_lifecycle_${verb}"
      return ;;
    exec|launch|ssh|ready|session|greeter|logout|reboot|idle|lock|unlock|shot\
    |pull|push|sudo|net|key|keydown|keyup|mouse) ;;
    *) usage >&2; die "unknown verb '$verb'" ;;
  esac

  _preflight
  "verb_${verb}" "$@"
}

# Source-guard so the bats suite can source and call the pure helpers.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then main "$@"; fi
