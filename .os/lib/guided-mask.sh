#!/usr/bin/env bash
# =============================================================================
# lib/guided-mask.sh — Guided Installer inline password masking core (ADR 0051)
# =============================================================================
# fzf has no masked-input mode, so a password typed inline in its query line is
# masked with a query-buffer trick: the real characters live in a tmpfs buffer,
# and every `change` event runs guided_mask_apply to reconstruct the buffer from
# the previous buffer + the new query, then renders the query as bullets.
#
# The reconstruction is diff-based and therefore only supports APPEND (typing or
# pasting) and BACKSPACE-AT-END — a longer query means its non-bullet suffix was
# just typed; a shorter one means characters were deleted from the end. Mid-string
# edits would desync it, so the live front-end UNBINDS cursor movement on the
# password screen (ADR 0051), making those impossible. This module is the pure,
# bats-covered heart; the fzf `transform-query` bind + cursor unbind are the thin
# untested glue over it.
#
# Pure: two strings in, two lines out (new buffer, then the bullet display). No
# fzf, no tty, no files.
# =============================================================================

# The bullet the query renders as. UTF-8 (the installer + repo are UTF-8 through-
# out); one display column per real character.
_GUIDED_MASK_BULLET='•'

# guided_mask_apply <buffer> <query> — the reconstructed real buffer on the first
# line, the bullet display (one bullet per buffer char) on the second. <query> is
# fzf's current query: the previous bullet display with the latest edit applied.
# A longer query appends its non-bullet suffix (real newly-typed chars, so a paste
# lands whole); a shorter query truncates the buffer to the query's length.
guided_mask_apply() {
  local buf="$1" q="$2" blen qlen
  blen=${#buf}; qlen=${#q}
  if (( qlen > blen )); then
    local add="${q:blen}" clean="" i c
    for (( i = 0; i < ${#add}; i++ )); do
      c="${add:i:1}"
      [[ "$c" == "$_GUIDED_MASK_BULLET" ]] || clean+="$c"
    done
    buf="$buf$clean"
  elif (( qlen < blen )); then
    buf="${buf:0:qlen}"
  fi
  local disp="" i
  for (( i = 0; i < ${#buf}; i++ )); do disp+="$_GUIDED_MASK_BULLET"; done
  printf '%s\n%s' "$buf" "$disp"
}

# guided_mask_buffer <buffer> <query> — just the reconstructed buffer (first line
# of guided_mask_apply). Convenience for the fzf-entry glue's buffer file write.
guided_mask_buffer() { guided_mask_apply "$1" "$2" | head -1; }

# guided_mask_display <buffer> <query> — just the bullet display (second line).
guided_mask_display() { guided_mask_apply "$1" "$2" | tail -1; }
