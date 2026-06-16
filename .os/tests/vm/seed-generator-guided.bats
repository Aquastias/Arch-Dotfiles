#!/usr/bin/env bats
# Tests for the Guided Installer cloud-init render in .os/vm/lib/seed-generator.sh
# (issue 01b). The guided seed drives install.sh --guided headlessly: it resolves
# the install disk in-guest via the Pre-Install Picker, writes a replay answers
# file (hostname / disk / INSTALL), and runs the guided installer — no fzf, no
# tty. These inspect the rendered user-data text directly (no cloud-localds).

setup() {
  REPO_URL="https://github.com/example/dotfiles.git"
  HOSTNAME_FIXTURE="vm-guided-host"

  # shellcheck source=../../vm/lib/seed-generator.sh
  source "$BATS_TEST_DIRNAME/../../vm/lib/seed-generator.sh"
}

render() { _seed_generator_render_guided_user_data "$REPO_URL" "$HOSTNAME_FIXTURE" "$@"; }

# ── tracer: the guided runcmd drives install.sh --guided with a replay file ──

@test "guided user-data: clones the repo and runs install.sh --guided" {
  run render
  [ "$status" -eq 0 ]
  [[ "$output" =~ "git clone $REPO_URL /root/dotfiles" ]]
  [[ "$output" =~ "./install.sh --guided /root/guided-answers" ]]
}

@test "guided user-data: resolves the disk in-guest via the Pre-Install Picker" {
  run render
  [ "$status" -eq 0 ]
  [[ "$output" =~ "picker_enum_disks" ]]
  [[ "$output" =~ "GUIDED_DISK=" ]]
}

@test "guided user-data: writes a replay answers file with hostname + INSTALL" {
  run render
  [ "$status" -eq 0 ]
  [[ "$output" =~ "hostname=%s" ]]
  [[ "$output" =~ "'$HOSTNAME_FIXTURE'" ]]
  [[ "$output" =~ "confirm=INSTALL" ]]
  [[ "$output" =~ "> /root/guided-answers" ]]
}

@test "guided user-data: cloud-config header + sentinel + poweroff" {
  run render
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | head -1)" = "#cloud-config" ]
  [[ "$output" =~ "===INSTALLER-EXIT-%d===" ]]
  [[ "$output" =~ "poweroff -f" ]]
}

@test "guided user-data: verify_boot injects the first-boot marker; off omits it" {
  run render false true
  [ "$status" -eq 0 ]
  [[ "$output" =~ "===FIRSTBOOT-OK===" ]]

  run render false false
  [ "$status" -eq 0 ]
  [[ ! "$output" =~ "===FIRSTBOOT-OK===" ]]
}
