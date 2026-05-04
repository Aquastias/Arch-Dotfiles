#!/usr/bin/env zsh

_op_and_go() {
  local op="$1" src="$2" dst="$3"
  [[ ! -e "$src" ]] && { echo "Error: '$src' does not exist." >&2; return 1; }
  [[ ! -d "$dst" ]] && { echo "Error: '$dst' is not a directory." >&2; return 1; }
  [[ ! -w "$dst" ]] && { echo "Error: '$dst' is not writable." >&2; return 1; }
  "$op" "$src" "$dst" && cd "$dst"
}

copy_and_go() {
  [[ ! -f "$1" ]] && { echo "Error: '$1' is not a regular file." >&2; return 1; }
  _op_and_go cp "$1" "$2"
}

move_and_go() { _op_and_go mv "$1" "$2"; }

mkdir_and_go() {
  [[ -z "$1" ]] && { echo "Error: no directory name provided." >&2; return 1; }
  mkdir -p "$1" && cd "$1"
}

copy_progress_bar() {
  [[ ! -e "$1" ]] && { echo "Error: '$1' does not exist." >&2; return 1; }
  [[ -e "$2" ]] && { echo "Error: '$2' already exists." >&2; return 1; }
  pv --progress --eta "$1" > "$2"
}

up_n_dirs() {
  local levels="${1:-1}" dots=""
  for (( i=1; i<=levels; i++ )); do dots="../$dots"; done
  cd "$dots" && pwd
}

pwd_last_two() {
  printf '%s\n' "$(pwd | awk -F/ '{printf "%s/%s\n", $(NF-1), $NF}')"
}

alias cpp='copy_progress_bar'
alias cpg='copy_and_go'
alias mvg='move_and_go'
alias mkdirg='mkdir_and_go'
alias updir='up_n_dirs'
alias pwdt='pwd_last_two'
