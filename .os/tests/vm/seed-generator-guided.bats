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

# ── encryption (arg 5): the runcmd presets the passphrase + replays the answer

@test "guided user-data: encryption exports the passphrase and replays the answer" {
  run render false false true false   # dirty / verify / encryption / impermanence
  [ "$status" -eq 0 ]
  [[ "$output" =~ "INSTALL_ENC_PASSPHRASE" ]]
  [[ "$output" =~ "encryption=true" ]]
}

@test "guided user-data: no encryption omits the passphrase and answer" {
  run render
  [ "$status" -eq 0 ]
  [[ ! "$output" =~ "INSTALL_ENC_PASSPHRASE" ]]
  [[ ! "$output" =~ "encryption=true" ]]
}

# ── impermanence (arg 6): replays the impermanence answer ───────────────────

@test "guided user-data: impermanence replays the impermanence answer" {
  run render false false false true
  [ "$status" -eq 0 ]
  [[ "$output" =~ "impermanence=true" ]]
}

@test "guided user-data: no impermanence omits the impermanence answer" {
  run render
  [ "$status" -eq 0 ]
  [[ ! "$output" =~ "impermanence=true" ]]
}

# ── multi layout (args 7/8): replays layout + a whitespace disk list, resolves
#    N disks in-guest, gates on ACCEPT; single keeps the one-disk answer ───────

@test "guided user-data: a multi layout replays layout/disks/accept + resolves N" {
  run render false true false false os-mirror-raidz1 5
  [ "$status" -eq 0 ]
  [[ "$output" =~ "layout=os-mirror-raidz1" ]]
  [[ "$output" =~ "accept_layout=ACCEPT" ]]
  [[ "$output" =~ "disks=%s" ]]
  [[ "$output" =~ "head -5" ]]
}

@test "guided user-data: single (no layout) keeps the single-disk answer" {
  run render
  [ "$status" -eq 0 ]
  [[ "$output" =~ "disk=%s" ]]
  [[ ! "$output" =~ "accept_layout" ]]
  [[ "$output" =~ "head -1" ]]
}

# ── guided_user (arg 9): ad-hoc user + root-password answers (issue 07) ──────

@test "guided user-data: a guided_user appends the ad-hoc + root password answers" {
  run render false false false false single 1 \
    '{"name":"carol","password":"hunter2","sudo":true,"shell":"/bin/zsh","root_password":"r00t"}'
  [ "$status" -eq 0 ]
  [[ "$output" =~ "new_user_name=carol" ]]
  [[ "$output" =~ "new_user_password=hunter2" ]]
  [[ "$output" =~ "new_user_sudo=true" ]]
  [[ "$output" =~ "new_user_shell=/bin/zsh" ]]
  [[ "$output" =~ "root_password=r00t" ]]
}

@test "guided user-data: no guided_user omits the user answers" {
  run render
  [ "$status" -eq 0 ]
  [[ ! "$output" =~ "new_user_name=" ]]
}

@test "guided user-data: guided_user + verify_boot injects a USER-OK check naming the user" {
  run render false true false false single 1 \
    '{"name":"carol","password":"hunter2"}'
  [ "$status" -eq 0 ]
  [[ "$output" =~ "===USER-OK===" ]]
  [[ "$output" =~ "carol" ]]
}
