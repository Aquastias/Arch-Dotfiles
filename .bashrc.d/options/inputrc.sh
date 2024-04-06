#!/usr/bin/env bash

# shellcheck source=/dev/null

# Find the index of the character "i" in the value of the $- shell variable
i_pos_helper=${-%%i*}; i_pos=${i_pos_helper:+$(( ${#i_pos_helper} + 1 ))}

# Disable the bell which causes the shell to flash the screen
# when a bell character is received (such as when the user types Ctrl+G)
if [[ $i_pos -gt 0 ]]; then bind "set bell-style visible"; fi

# Ignore case on auto-completion
# Note: bind used instead of sticking these in .inputrc
if [[ $i_pos -gt 0 ]]; then bind "set completion-ignore-case on"; fi

# Show auto-completion list automatically, without double tab
if [[ $i_pos -gt 0 ]]; then bind "set show-all-if-ambiguous On"; fi