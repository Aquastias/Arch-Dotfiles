#!/usr/bin/env bats
# Tests for .installer/vm/vm-agent.sh — the VM Agent Control CLI (ADR 0117).
# Only the pure decision logic is exercised (no libvirt, no SSH): source the
# script (its source-guard keeps main() from running) and call the helpers, or
# run it as a subprocess for usage/dispatch. The live SSH/reboot/screenshot
# paths are verified by hand on the persistent arch-combined VM.

setup() {
  AGENT="$BATS_TEST_DIRNAME/../../vm/vm-agent.sh"
}

# _call <helper-expr> — source the CLI (its source-guard keeps main() from
# running; it defaults INSTALLER_DIR from its own location) then evaluate a
# pure helper.
_call() { run bash -c "source '$AGENT'; $1"; }

@test "no verb exits non-zero with usage" {
  run bash "$AGENT" --vm x
  [ "$status" -ne 0 ]
  [[ "$output" == *"verb is required"* ]]
}

@test "unknown verb is rejected" {
  run bash "$AGENT" --vm x bogus
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown verb"* ]]
}

@test "unknown option is rejected" {
  run bash "$AGENT" --nope ready
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown option"* ]]
}

@test "agent_resolve_name reads .name from a profile ref" {
  _call "agent_resolve_name profile desktop/combined"
  [ "$status" -eq 0 ]
  [ "$output" = "arch-combined" ]
}

@test "agent_resolve_name passes a --vm name through verbatim" {
  _call "agent_resolve_name vm arch-niri"
  [ "$output" = "arch-niri" ]
}

@test "agent_key_path matches the persistent-flow harness key location" {
  _call 'CACHE_DIR=/x/.vm-cache; agent_key_path'
  [ "$output" = "/x/.vm-cache/harness_ed25519" ]
}

@test "agent_ssh_mux_options: one multiplexed connection per guest" {
  # ufw's `limit ssh` rejects a 6th connection in 30s; one TCP connection
  # per command tripped it (Audit Run 20260929, ufw variant).
  _call 'agent_ssh_mux_options /run/mux'
  [ "$status" -eq 0 ]
  [[ "$output" == *"ControlPath=/run/mux/%C"* ]]
  [[ "$output" == *"ServerAliveInterval="* ]]
}

@test "session env carries the locale (no Qt locale-C fallback)" {
  # Agent-launched Qt apps logged "Detected locale C" (Audit Run 20260929):
  # the session env import dropped LANG/LC_*.
  _call '_agent_remote_environment_function'
  [[ "$output" == *"LANG=*"* ]]
  [[ "$output" == *"LC_*=*"* ]]
}

@test "session -> .desktop mapping" {
  _call "agent_session_desktop niri";     [ "$output" = "niri.desktop" ]
  _call "agent_session_desktop hyprland"; [ "$output" = "hyprland.desktop" ]
  _call "agent_session_desktop kde";      [ "$output" = "plasma.desktop" ]
}

@test "sddm autologin config is a correct [Autologin] drop-in" {
  _call "agent_autologin_config sddm kde aquastias"
  [[ "$output" == *"[Autologin]"* ]]
  [[ "$output" == *"User=aquastias"* ]]
  [[ "$output" == *"Session=plasma.desktop"* ]]
  [[ "$output" == *"Relogin=true"* ]]
}

@test "greetd autologin config is a correct [initial_session] table" {
  _call "agent_autologin_config greetd niri aquastias"
  [[ "$output" == *"[initial_session]"* ]]
  [[ "$output" == *'command = "niri-session"'* ]]
  [[ "$output" == *'user = "aquastias"'* ]]
}

@test "greetd hyprland uses start-hyprland (ADR 0070)" {
  _call "agent_autologin_config greetd hyprland aquastias"
  [[ "$output" == *'command = "start-hyprland"'* ]]
}

@test "shot tool is selected by the running compositor" {
  _call "agent_shot_tool kwin_wayland"; [ "$output" = "spectacle" ]
  _call "agent_shot_tool niri";         [ "$output" = "grim" ]
  _call "agent_shot_tool Hyprland";     [ "$output" = "grim" ]
}

# Impermanence guests roll /etc back to @blank on boot, so the autologin
# change must be baked into @blank before the reboot or it is lost.
@test "agent_bake_blank_command runs the resnapshot helper only when present" {
  _call "agent_bake_blank_command"
  [[ "$output" == *"/usr/lib/impermanence/resnapshot.sh"* ]]
  [[ "$output" == *"-x /usr/lib/impermanence/resnapshot.sh"* ]]
  # one argv for sudo: a bare `||` would run the helper outside sudo
  [[ "$output" == "sh -c '"* ]]
}

# _stub_io — replace every guest-touching helper with a logger to $LOG.
_stub_io='
  LOG="$BATS_TEST_TMPDIR/io.log"; : > "$LOG"
  _guest_display_manager()   { echo sddm; }
  _stage()      { cat >/dev/null; echo "stage $1" >> "$LOG"; }
  _sudo()       { echo "sudo $*" >> "$LOG"; }
  _ssh()        { echo "ssh $*" >> "$LOG"; }
  verb_reboot() { echo reboot >> "$LOG"; }
  info()        { :; }'

@test "session bakes @blank after writing autologin, before reboot" {
  run bash -c "source '$AGENT'; $_stub_io; verb_session kde; cat \"\$LOG\""
  [ "$status" -eq 0 ]
  local write_line bake_line reboot_line
  write_line="$(awk '/zz-agent-autologin.conf/ { print NR; exit }' <<<"$output")"
  bake_line="$(awk '/resnapshot.sh/ { print NR; exit }' <<<"$output")"
  reboot_line="$(awk '/^reboot$/ { print NR }' <<<"$output")"
  [ -n "$write_line" ]
  [ -n "$bake_line" ]
  [ -n "$reboot_line" ]
  (( write_line < bake_line && bake_line < reboot_line ))
}

@test "greeter bakes @blank after removing autologin" {
  run bash -c "source '$AGENT'; $_stub_io; verb_greeter; cat \"\$LOG\""
  [ "$status" -eq 0 ]
  local write_line bake_line
  write_line="$(awk '/rm -f \/etc\/sddm.conf.d\/zz-agent-autologin.conf/ {
    print NR }' <<<"$output")"
  bake_line="$(awk '/resnapshot.sh/ { print NR; exit }' <<<"$output")"
  [ -n "$write_line" ]
  [ -n "$bake_line" ]
  (( write_line < bake_line ))
}

# ── Feature Audit verbs (ADR 0152) ───────────────────────────────────────────

@test "pull: guest tar streams the path's basename from its parent" {
  _call "agent_pull_command /var/log/journal"
  [ "$status" -eq 0 ]
  [ "$output" = "tar -C '/var/log' -cf - 'journal'" ]
}

@test "pull: a relative guest path is rejected" {
  _call "agent_pull_command var/log"
  [ "$status" -ne 0 ]
}

@test "pull and sudo are known verbs (dispatch past the verb check)" {
  run bash "$AGENT" --vm no-such-vm-xyz pull /x "$BATS_TEST_TMPDIR"
  [[ "$output" != *"unknown verb"* ]]
  run bash "$AGENT" --vm no-such-vm-xyz sudo true
  [[ "$output" != *"unknown verb"* ]]
}

@test "net off: drops the default route, saving it for restore" {
  _call "agent_network_command off"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ip route show default"* ]]
  [[ "$output" == *"ip route del default"* ]]
}

@test "net on: restores the saved default route" {
  _call "agent_network_command on"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ip route replace"* ]]
}

@test "net: only on|off" {
  _call "agent_network_command sideways"
  [ "$status" -ne 0 ]
}

@test "push and net are known verbs" {
  run bash "$AGENT" --vm no-such-vm-xyz push "$BATS_TEST_TMPDIR" /tmp/x
  [[ "$output" != *"unknown verb"* ]]
  run bash "$AGENT" --vm no-such-vm-xyz net off
  [[ "$output" != *"unknown verb"* ]]
}

@test "key: chord → QMP qcodes (modifiers first, Mod = Super)" {
  _call "agent_key_qcodes 'Mod+Shift+Return'"
  [ "$status" -eq 0 ]
  [ "$output" = "meta_l shift ret" ]
  _call "agent_key_qcodes 'Ctrl+Alt+Delete'"
  [ "$output" = "ctrl alt delete" ]
  _call "agent_key_qcodes 'Super+Page_Down'"
  [ "$output" = "meta_l pgdn" ]
  _call "agent_key_qcodes 'Mod+BracketLeft'"
  [ "$output" = "meta_l bracket_left" ]
  _call "agent_key_qcodes 'XF86AudioRaiseVolume'"
  [ "$output" = "volumeup" ]
  _call "agent_key_qcodes 'Mod+slash'"
  [ "$output" = "meta_l slash" ]
}

@test "key: a key QEMU cannot inject is rejected" {
  _call "agent_key_qcodes 'XF86MonBrightnessUp'"
  [ "$status" -ne 0 ]
}

@test "key: QMP event batch presses then releases in reverse" {
  _call "agent_key_qmp down 'meta_l shift'"
  [ "$status" -eq 0 ]
  jq -e '.execute == "input-send-event"
    and ([.arguments.events[] | .data.down] | all)
    and [.arguments.events[].data.key.data] == ["meta_l","shift"]' <<<"$output"
  _call "agent_key_qmp up 'meta_l shift'"
  jq -e '[.arguments.events[].data.key.data] == ["shift","meta_l"]
    and ([.arguments.events[] | .data.down] | any | not)' <<<"$output"
}

@test "mouse: move/btn/wheel → QMP events" {
  _call "agent_mouse_qmp move 100 200"
  jq -e '[.arguments.events[].data.axis] == ["x","y"]
    and [.arguments.events[].data.value] == [100,200]' <<<"$output"
  _call "agent_mouse_qmp btn left down"
  jq -e '.arguments.events[0].data == {"down":true,"button":"left"}' \
    <<<"$output"
  _call "agent_mouse_qmp wheel up"
  jq -e '.arguments.events[0].data.button == "wheel-up"' <<<"$output"
  _call "agent_mouse_qmp spin 1"
  [ "$status" -ne 0 ]
}

@test "key: KDE-style key names map to qcodes" {
  _call "agent_key_qcodes 'Meta+PgUp'"
  [ "$output" = "meta_l pgup" ]
  _call "agent_key_qcodes 'Meta+Ctrl+Esc'"
  [ "$output" = "meta_l ctrl esc" ]
  _call "agent_key_qcodes 'Volume Down'"
  [ "$output" = "volumedown" ]
  _call "agent_key_qcodes 'Meta+Volume Mute'"
  [ "$output" = "meta_l audiomute" ]
  _call "agent_key_qcodes 'Media Play'"
  [ "$output" = "audioplay" ]
  _call "agent_key_qcodes 'Meta+Plus'"
  [ "$output" = "meta_l shift equal" ]
  _call "agent_key_qcodes 'Alt+~'"
  [ "$output" = "alt shift grave_accent" ]
  _call "agent_key_qcodes 'Meta+\`'"
  [ "$output" = "meta_l grave_accent" ]
  _call "agent_key_qcodes 'Meta+='"
  [ "$output" = "meta_l equal" ]
  _call "agent_key_qcodes 'Meta+-'"
  [ "$output" = "meta_l minus" ]
  _call "agent_key_qcodes 'Meta'"
  [ "$output" = "meta_l" ]
}

@test "keydown/keyup are known verbs" {
  run bash "$AGENT" --vm no-such-vm-xyz keydown Super
  [[ "$output" != *"unknown verb"* ]]
  run bash "$AGENT" --vm no-such-vm-xyz keyup Super
  [[ "$output" != *"unknown verb"* ]]
}

# Ready means the user's compositor serves Wayland, not merely that its
# process exists (Audit Run 20261004: a Ctrl+Alt+Delete bind sent while
# Hyprland was still starting hit the text VT and rebooted the guest).
@test "agent_ready_check: the user's compositor AND its Wayland socket" {
  _call "agent_ready_check alice"
  [[ "$output" == *"pgrep -u alice -x"* ]]
  [[ "$output" == *'wayland-[0-9]'* ]]
  [[ "$output" == *"&&"* ]]
}

@test "reboot waits for a new boot id before checking readiness" {
  run bash -c "source '$AGENT'; VM_NAME=t; _sudo() { :; }; info() { :; }
    c=\"\$BATS_TEST_TMPDIR/n\"; echo 0 > \"\$c\"
    _ssh() { n=\$((\$(cat \"\$c\") + 1)); echo \$n > \"\$c\"
      [ \$n -le 2 ] && echo old || echo new; }
    verb_ready() { echo ready-after-\$(cat \"\$c\"); }
    sleep() { :; }
    verb_reboot"
  [ "$status" -eq 0 ]
  [[ "$output" == *ready-after-3* ]]
}

@test "reboot resets a guest wedged in shutdown after the grace" {
  run bash -c "source '$AGENT'; VM_NAME=t; AGENT_SHUTDOWN_GRACE=10
    _sudo() { :; }; info() { :; }; sleep() { :; }
    _ssh() { echo old; }
    virsh() { echo \"virsh \$*\" >> \"\$BATS_TEST_TMPDIR/v\"; }
    verb_ready() { :; }
    verb_reboot"
  grep -qx 'virsh reset t' "$BATS_TEST_TMPDIR/v"
}

@test "reboot resets even when the grace is not a multiple of the step" {
  run bash -c "source '$AGENT'; VM_NAME=t; AGENT_SHUTDOWN_GRACE=12
    _sudo() { :; }; info() { :; }; sleep() { :; }
    _ssh() { echo old; }
    virsh() { echo \"virsh \$*\" >> \"\$BATS_TEST_TMPDIR/v\"; }
    verb_ready() { :; }
    verb_reboot"
  [ "$(grep -cx 'virsh reset t' "$BATS_TEST_TMPDIR/v")" -eq 1 ]
}

# ── power verbs (agent-lifecycle.sh, ADR 0155) ──────────────────────────────

# _lifecycle <state> <running-names> <expr> — call a lifecycle helper with
# `virsh` stubbed: domstate prints <state> (or fails for `undefined`), list
# prints <running-names>, start logs to stdout.
_lifecycle() {
  run bash -c "source '$AGENT'
    virsh() {
      case \"\$1\" in
        domstate) [[ '$1' == undefined ]] && return 1; echo '$1' ;;
        list) printf '%b\n' '$2' ;;
        start) echo \"started \$2\" ;;
      esac
    }
    _vm_ip() { echo 192.168.122.5; }
    VM_NAME=arch-combined; $3"
}

@test "status: running VM shows its ip and other running VMs" {
  _lifecycle running 'arch-combined\nmatrix-a' agent_lifecycle_status
  [ "$status" -eq 0 ]
  [[ "$output" == *"arch-combined: running ip=192.168.122.5"* ]]
  [[ "$output" == *"other running: matrix-a"* ]]
}

@test "status: an undefined VM says so" {
  _lifecycle undefined '' agent_lifecycle_status
  [ "$output" = "arch-combined: undefined" ]
}

@test "start: refuses while another VM runs (one at a time)" {
  _lifecycle 'shut off' 'matrix-a' agent_lifecycle_start
  [ "$status" -ne 0 ]
  [[ "$output" == *"other VM(s) running: matrix-a"* ]]
}

@test "start: VM_ALLOW_PARALLEL=true lifts the one-at-a-time rule" {
  _lifecycle 'shut off' 'matrix-a' \
    'VM_ALLOW_PARALLEL=true agent_lifecycle_start'
  [ "$status" -eq 0 ]
}

@test "start: boots a shut-off VM when nothing else runs" {
  _lifecycle 'shut off' '' agent_lifecycle_start
  [ "$status" -eq 0 ]
  [[ "$output" == *"started 'arch-combined'"* ]]
}
