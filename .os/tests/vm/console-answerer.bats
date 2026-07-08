#!/usr/bin/env bats
# Tests for .os/vm/lib/console-answerer.sh — the Console Answerer's pure prompt-
# matcher (combination-matrix/07, ADR 0046). Given a line of serial text, decide
# whether a disk-unlock prompt is present and which unlock variant it is, so the
# IO watcher can write the test passphrase to the serial char device unattended.
# Pure: text in, decision out — no serial device, no VM.

setup() {
  # shellcheck source=../../vm/lib/console-answerer.sh
  source "$BATS_TEST_DIRNAME/../../vm/lib/console-answerer.sh"
}

# ── AC1: the mkinitcpio `encrypt` hook prompt is detected ────────────────────

@test "variant: mkinitcpio encrypt-hook prompt → encrypt-hook" {
  run console_answerer_variant \
    "A password is required to access the cryptroot volume:"
  [ "$status" -eq 0 ]
  [ "$output" = encrypt-hook ]
}

@test "variant: ordinary serial noise → not detected (no output)" {
  run console_answerer_variant "[   3.14159] random kernel log line"
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

# ── AC1: the zfs-native (keylocation=prompt) prompt is detected ──────────────

@test "variant: zfs-native pool prompt → zfs-native" {
  run console_answerer_variant "Enter passphrase for 'rpool':"
  [ "$status" -eq 0 ]
  [ "$output" = zfs-native ]
}

@test "variant: cryptsetup device prompt (encrypt hook) → encrypt-hook" {
  # the encrypt hook's cryptsetup prompt names a device, not a quoted pool.
  run console_answerer_variant \
    "Enter passphrase for /dev/disk/by-uuid/abcd-1234:"
  [ "$status" -eq 0 ]
  [ "$output" = encrypt-hook ]
}

# ── AC1: the systemd-cryptsetup (sd-encrypt) prompt is detected ──────────────

@test "variant: systemd-cryptsetup prompt → systemd-cryptsetup" {
  run console_answerer_variant \
    "Please enter passphrase for disk cryptroot (cryptroot):"
  [ "$status" -eq 0 ]
  [ "$output" = systemd-cryptsetup ]
}

# ── AC1: reply supplies the passphrase for a prompt, nothing for noise ───────

@test "reply: a prompt → the passphrase; noise → nothing + nonzero" {
  run console_answerer_reply "Enter passphrase for 'rpool':"
  [ "$status" -eq 0 ]
  [ "$output" = testtest ]                       # default test passphrase

  run console_answerer_reply "[    0.00] booting the kernel"
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "reply: passphrase is overridable via CONSOLE_ANSWERER_PASSPHRASE" {
  CONSOLE_ANSWERER_PASSPHRASE=hunter2 run console_answerer_reply \
    "A password is required to access the cryptroot volume:"
  [ "$status" -eq 0 ]
  [ "$output" = hunter2 ]
}

# ── the IO watcher writes to the char device when a prompt lands on serial ────
# (drives the real loop against a temp file standing in for the serial pty)

# _await <file> <needle> — poll until <file> contains <needle> (bounded).
_await() {
  local i=0
  until grep -q -- "$2" "$1" 2>/dev/null || (( i++ > 60 )); do sleep 0.05; done
}

@test "watch: writes the passphrase to the device on an unlock prompt" {
  local log="$BATS_TEST_TMPDIR/serial.log" dev="$BATS_TEST_TMPDIR/console"
  : >"$log"; : >"$dev"
  console_answerer_watch "$log" "$dev" 0.05 & local wpid=$!
  sleep 0.1
  printf 'some boot noise\n' >>"$log"
  printf "Enter passphrase for 'rpool':\n" >>"$log"
  _await "$dev" testtest
  kill "$wpid" 2>/dev/null || true
  grep -q testtest "$dev"
}

@test "watch: answers each prompt once (multi-disk), no re-answering" {
  local log="$BATS_TEST_TMPDIR/serial.log" dev="$BATS_TEST_TMPDIR/console"
  : >"$log"; : >"$dev"
  console_answerer_watch "$log" "$dev" 0.05 & local wpid=$!
  sleep 0.1
  printf "Enter passphrase for '/dev/sda1':\n" >>"$log"
  _await "$dev" testtest
  sleep 0.15                                    # let extra polls run
  printf 'noise between prompts\n' >>"$log"
  printf "Enter passphrase for '/dev/sdb1':\n" >>"$log"
  # wait until two passphrase lines have been written
  local i=0
  until (( $(grep -c testtest "$dev") >= 2 )) || (( i++ > 60 )); do
    sleep 0.05
  done
  kill "$wpid" 2>/dev/null || true
  [ "$(grep -c testtest "$dev")" -eq 2 ]        # exactly one per prompt
}
