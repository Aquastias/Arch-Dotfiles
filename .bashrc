#!/usr/bin/env bash

# shellcheck source=/dev/null

# GLOBAL VARIABLES
GLOBAL_DEFINITIONS_DIRECTORY=/etc/bashrc
BASHRC_CONFIG_DIRECTORY=$HOME/.bashrc.d/

# Source global definitions
if [ -f "$GLOBAL_DEFINITIONS_DIRECTORY" ]; then
  source "$GLOBAL_DEFINITIONS_DIRECTORY"
fi

# Source all files from .BASHRC_CONFIG_DIRECTORY directory
# if [ -d "$BASHRC_CONFIG_DIRECTORY" ]; then
#   for file in $(find "$BASHRC_CONFIG_DIRECTORY" -type f -name '*.sh'); do
#     source "$file"
#   done
# fi
while IFS= read -r -d '' file; do
  source "${file}"
done < <(find "$BASHRC_CONFIG_DIRECTORY" -mtime -7 -name '*.sh' -print0)

# Enable programmable completion features (you don't need to enable
# this, if it's already enabled in /etc/bash.bashrc and /etc/profile
# sources /etc/bash.bashrc).
if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    source /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
    source /etc/bash_completion
  fi
fi

# ~/.bashrc: executed by bash(1) for non-login shells.
# See /usr/share/doc/bash/examples/startup-files (in the package bash-doc)
# for examples

# If not running interactively, don't do anything
case $- in
*i*) ;;
*) return ;;
esac

# VARIABLES
PS1='[\u@\h \W]\$ '
# Don't put duplicate lines or lines starting with space in the history.
# See bash(1) for more options
HISTCONTROL=ignoreboth
# For setting history length see HISTSIZE and HISTFILESIZE in bash(1)
# HISTSIZE=1000'
# HISTFILESIZE=2000
# LS_COLORS='rs=0:di=01
# 34:ln=01
# 36:mh=00:pi=40
# 33'

# export LS_COLORS
# export CLICOLOR=1

# # Append to the history file, don't overwrite it
shopt -s histappend

# Check the window size after each command and, if necessary,
# Update the values of LINES and COLUMNS.
shopt -s checkwinsize

# If set, the pattern "**" used in a pathname expansion context will
# match all files and zero or more directories and subdirectories.
shopt -s globstar

# Make less more friendly for non-text input files, see lesspipe(1).
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

# Set a fancy prompt (non-color, unless we know we "want" color)
case "$TERM" in
xterm-color) color_prompt=yes ;;
esac

# Uncomment for a colored prompt, if the terminal has the capability; turned
# off by default to not distract the user: the focus in a terminal window
# should be on the output of commands, not on the prompt.
#force_color_prompt=yes

if [ -n "$force_color_prompt" ]; then
  if [ -x /usr/bin/tput ] && tput setaf 1 >&/dev/null; then
    # We have color support; assume it's compliant with Ecma-48
    # (ISO/IEC-6429). (Lack of such support is extremely rare, and such
    # a case would tend to support setf rather than setaf.)
    color_prompt=yes
  else
    color_prompt=
  fi
fi

unset color_prompt force_color_prompt

# START ssh-agent
# Setup

# END ssh-agent

