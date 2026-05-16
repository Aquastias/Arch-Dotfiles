#!/usr/bin/env zsh

find_text_in_files() {
  local folder="."
  [ -d "$1" ] && { folder="$1"; shift; }
  find "$folder" -type f -not -path '*/\.*' -print0 \
    | xargs -0 grep -nHir --color=always "$@" \
    | less -R
}

chtsh() {
  local languages=("typescript" "js" "rust" "nodejs" "bash")
  local core_utils=("xargs" "find" "mv" "sed" "awk")
  command -v fzf &>/dev/null || { echo "Error: fzf required." >&2; return 127; }
  local selected
  selected=$(printf "%s\n" "${languages[@]}" "${core_utils[@]}" | fzf)
  [ -z "$selected" ] && return 1
  if [[ "${languages[*]}" =~ $selected ]]; then
    local query
    read query?"Enter query: "
    [ -z "$query" ] && return 1
    curl -s "cht.sh/$selected/$query"
  else
    man "$selected"
  fi
}

zshconfig() {
  local editors=("vim" "nvim" "nano" "code" "codium" "gedit" "kate")
  local installed_editors=() selected_editor
  command -v fzf &>/dev/null || { echo "Please install fzf." >&2; return 127; }
  for editor in "${editors[@]}"; do
    command -v "$editor" &>/dev/null && installed_editors+=("$editor")
  done
  selected_editor=$(printf '%s\n' "${installed_editors[@]}" | fzf)
  [ -z "$selected_editor" ] && { echo "No editor selected."; return 1; }
  "$selected_editor" "$HOME/.zshrc"
}

alias ftext='find_text_in_files'
alias zshreload='source $ZSHRC_SOURCE'
