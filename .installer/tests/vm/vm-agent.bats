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
