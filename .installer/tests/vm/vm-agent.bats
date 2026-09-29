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
@test "agent_bake_blank_cmd runs the resnapshot helper only when present" {
  _call "agent_bake_blank_cmd"
  [[ "$output" == *"/usr/lib/impermanence/resnapshot.sh"* ]]
  [[ "$output" == *"-x /usr/lib/impermanence/resnapshot.sh"* ]]
  # one argv for sudo: a bare `||` would run the helper outside sudo
  [[ "$output" == "sh -c '"* ]]
}

# _stub_io — replace every guest-touching helper with a logger to $LOG.
_stub_io='
  LOG="$BATS_TEST_TMPDIR/io.log"; : > "$LOG"
  _guest_dm()   { echo sddm; }
  _stage()      { cat >/dev/null; echo "stage $1" >> "$LOG"; }
  _sudo()       { echo "sudo $*" >> "$LOG"; }
  _ssh()        { echo "ssh $*" >> "$LOG"; }
  verb_reboot() { echo reboot >> "$LOG"; }
  info()        { :; }'

@test "session bakes @blank after writing autologin, before reboot" {
  run bash -c "source '$AGENT'; $_stub_io; verb_session kde; cat \"\$LOG\""
  [ "$status" -eq 0 ]
  local w b r
  w="$(grep -n 'zz-agent-autologin.conf' <<<"$output" | head -1 | cut -d: -f1)"
  b="$(grep -n 'resnapshot.sh' <<<"$output" | head -1 | cut -d: -f1)"
  r="$(grep -n '^reboot$' <<<"$output" | cut -d: -f1)"
  [ -n "$w" ]
  [ -n "$b" ]
  [ -n "$r" ]
  (( w < b && b < r ))
}

@test "greeter bakes @blank after removing autologin" {
  run bash -c "source '$AGENT'; $_stub_io; verb_greeter; cat \"\$LOG\""
  [ "$status" -eq 0 ]
  local w b
  w="$(grep -n 'rm -f /etc/sddm.conf.d/zz-agent-autologin.conf' <<<"$output" \
    | cut -d: -f1)"
  b="$(grep -n 'resnapshot.sh' <<<"$output" | head -1 | cut -d: -f1)"
  [ -n "$w" ]
  [ -n "$b" ]
  (( w < b ))
}

# ── Feature Audit verbs (ADR 0152) ───────────────────────────────────────────

@test "pull: guest tar streams the path's basename from its parent" {
  _call "agent_pull_cmd /var/log/journal"
  [ "$status" -eq 0 ]
  [ "$output" = "tar -C '/var/log' -cf - 'journal'" ]
}

@test "pull: a relative guest path is rejected" {
  _call "agent_pull_cmd var/log"
  [ "$status" -ne 0 ]
}

@test "pull and sudo are known verbs (dispatch past the verb check)" {
  run bash "$AGENT" --vm no-such-vm-xyz pull /x "$BATS_TEST_TMPDIR"
  [[ "$output" != *"unknown verb"* ]]
  run bash "$AGENT" --vm no-such-vm-xyz sudo true
  [[ "$output" != *"unknown verb"* ]]
}
