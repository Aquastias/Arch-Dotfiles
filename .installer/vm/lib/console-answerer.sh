#!/usr/bin/env bash
# =============================================================================
# vm/lib/console-answerer.sh — Console Answerer prompt-matcher (ADR 0046)
# =============================================================================
# The closest-to-reality encrypted-boot oracle: drive the real passphrase-unlock
# path over serial, no human keystroke. This file is the Answerer's PURE core —
# a prompt-matcher. Given a line of serial text it decides whether a disk-unlock
# prompt is present and which unlock variant produced it. The IO watcher (in
# flow-test.sh) tails the serial log, and on a match writes the test passphrase
# to the serial char device (with console=ttyS0 the prompt reads /dev/console,
# so send-key would miss it).
#
# Pure: text in, decision out — no serial device, no VM.
#
# Public API:
#   console_answerer_variant <serial_text>
#       → prints the unlock variant (encrypt-hook | systemd-cryptsetup |
#         zfs-native) and exit 0 when a disk-unlock prompt is present; else
#         exit 1 with no output.
#   console_answerer_passphrase [variant]
#       → the passphrase to send for that variant (the test passphrase).
#   console_answerer_reply <serial_text>
#       → print the passphrase and exit 0 when a prompt is present; else exit 1.
#   console_answerer_watch <log_path> <char_device> [poll_interval]
#       → the IO loop: tail the serial log and write the passphrase to the char
#         device once per unlock prompt (runs in the background during boot).
# =============================================================================

# The passphrase the Answerer sends. Every variant unlocks with the one test
# passphrase (INSTALL_ENC_PASSPHRASE='testtest'); the per-variant arg keeps the
# door open for distinct secrets without changing the call sites.
: "${CONSOLE_ANSWERER_PASSPHRASE:=${INSTALL_ENC_PASSPHRASE:-testtest}}"

# console_answerer_variant <serial_text> — classify a line of serial output.
# Matching is substring-based so serial CRLF and surrounding noise are OK.
console_answerer_variant() {
  local text="$1"
  # zfs load-key names the pool in single quotes: Enter passphrase for 'rpool':
  if [[ "$text" == *"Enter passphrase for '"* ]]; then
    echo zfs-native; return 0
  fi
  # systemd-cryptsetup's password agent: Please enter passphrase for disk NAME:
  if [[ "$text" == *"Please enter passphrase for disk"* ]]; then
    echo systemd-cryptsetup; return 0
  fi
  # mkinitcpio encrypt hook: the volume banner, or cryptsetup's device prompt.
  if [[ "$text" == *"A password is required to access"* ]] \
     || [[ "$text" == *"Enter passphrase for "* ]]; then
    echo encrypt-hook; return 0
  fi
  return 1
}

# console_answerer_passphrase [variant] — the passphrase for the unlock variant.
console_answerer_passphrase() {
  printf '%s\n' "$CONSOLE_ANSWERER_PASSPHRASE"
}

# console_answerer_reply <serial_text> — the whole matcher decision: when the
# line is a disk-unlock prompt, print the passphrase to send and exit 0; else
# exit 1 with no output. This is what the IO watcher writes to the char device.
console_answerer_reply() {
  local variant
  variant="$(console_answerer_variant "$1")" || return 1
  console_answerer_passphrase "$variant"
}

# _console_answerer_replies — read serial text on stdin, print one passphrase
# line per unlock prompt (in order). The `|| [[ -n "$line" ]]` tail catches a
# prompt printed WITHOUT a trailing newline (cryptsetup leaves the cursor on the
# prompt line), which a plain line read would otherwise drop.
_console_answerer_replies() {
  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    console_answerer_reply "$line" || true
  done
}

# console_answerer_watch <log_path> <char_device> [poll_interval] — the IO loop.
# Re-scans the serial log each tick, writing the passphrase to the char device
# for every prompt not yet answered (tracked by count, so each prompt is
# answered exactly once and multi-disk / re-prompted unlocks are all handled).
# Runs until killed; the boot-verify phase bounds it with its own timeout, so a
# missed unlock surfaces as a boot-fail rather than a hang.
console_answerer_watch() {
  local log="$1" dev="$2" interval="${3:-0.3}" answered=0
  local -a reps
  while :; do
    if [[ -f "$log" ]]; then
      mapfile -t reps < <(_console_answerer_replies <"$log")
      while (( answered < ${#reps[@]} )); do
        printf '%s\n' "${reps[answered]}" >>"$dev"
        answered=$((answered + 1))
      done
    fi
    sleep "$interval"
  done
}
