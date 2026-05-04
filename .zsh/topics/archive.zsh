#!/usr/bin/env zsh

extract_archive() {
  for archive in "$@"; do
    if [ -f "$archive" ]; then
      case $archive in
        *.tar.bz2)  tar xvjf "$archive"   ;;
        *.tar.gz)   tar xvzf "$archive"   ;;
        *.bz2)      bunzip2 "$archive"    ;;
        *.rar)      type -P rar >/dev/null && rar x "$archive" || echo "rar not found." ;;
        *.gz)       gunzip "$archive"     ;;
        *.tar)      tar xvf "$archive"    ;;
        *.tbz2)     tar xvjf "$archive"   ;;
        *.tgz)      tar xvzf "$archive"   ;;
        *.zip)      unzip "$archive"      ;;
        *.Z)        uncompress "$archive" ;;
        *.7z)       7z x "$archive"       ;;
        *)          echo "don't know how to extract '$archive'" ;;
      esac
    else
      echo "'$archive' is not a valid file!"
    fi
  done
}

archive_encrypt_openssl() {
  if [ $# -lt 2 ]; then
    echo "Usage: archive_encrypt_openssl output_file.tar.gz.enc file1 [file2 ...]"
    return 1
  fi
  local output_file="$1"; shift
  local files_to_archive=("$@")
  local password password_confirm
  while true; do
    read -r -s "password?Enter encryption password: "; echo
    read -r -s "password_confirm?Confirm encryption password: "; echo
    if [ "$password" = "$password_confirm" ]; then
      [ -z "$password" ] && { echo "Password cannot be empty."; continue; }
      break
    else
      echo "Passwords do not match."
    fi
  done
  if tar czf - "${files_to_archive[@]}" |
    openssl enc -aes-256-cbc -pbkdf2 -iter 100000 -salt -e -out "$output_file" -pass fd:3 3<<<"$password"; then
    echo "Encrypted: $output_file"
  else
    echo "Error: archiving or encryption failed." >&2
    rm -f "$output_file"
    return 1
  fi
}

unarchive_decrypt_openssl() {
  if [ $# -lt 2 ]; then
    echo "Usage: unarchive_decrypt_openssl input_file.tar.gz.enc target_directory"
    return 1
  fi
  local input_file="$1" target_directory="$2"
  [ ! -f "$input_file" ] && { echo "Error: '$input_file' not found." >&2; return 1; }
  [ ! -d "$target_directory" ] && { mkdir -p "$target_directory" || return 1; }
  local password
  read -r -s "password?Enter decryption password: "; echo
  if openssl enc -aes-256-cbc -d -pbkdf2 -iter 100000 -salt -in "$input_file" -pass fd:3 3<<<"$password" |
    tar xzf - -C "$target_directory"; then
    echo "Decrypted to: $target_directory"
  else
    echo "Error: decryption or extraction failed." >&2
    return 1
  fi
}

encrypt_with_age() {
  if [ $# -lt 2 ]; then
    echo "Usage: encrypt_with_age output_file.age input_file"
    return 1
  fi
  local output_file="$1" input_file="$2"
  [ ! -f "$input_file" ] && { echo "Error: '$input_file' not found." >&2; return 1; }
  if age -e -p -o "$output_file" "$input_file"; then
    echo "Encrypted: $output_file"
  else
    rm -f "$output_file"
    return 1
  fi
}

decrypt_with_age() {
  if [ $# -lt 2 ]; then
    echo "Usage: decrypt_with_age input_file.age output_file"
    return 1
  fi
  local input_file="$1" output_file="$2"
  [ ! -f "$input_file" ] && { echo "Error: '$input_file' not found." >&2; return 1; }
  if [ -f "$output_file" ]; then
    read -rq "choice?'$output_file' exists. Overwrite? (y/N) "; echo
    [[ ! "$choice" =~ ^[yY]$ ]] && { echo "Cancelled."; return 1; }
  fi
  if age -d -o "$output_file" "$input_file"; then
    echo "Decrypted: $output_file"
  else
    rm -f "$output_file"
    return 1
  fi
}

alias extractarchive='extract_archive'
alias archiveopenssl='archive_encrypt_openssl'
alias unarchiveopenssl='unarchive_decrypt_openssl'
alias ageencrypt='encrypt_with_age'
alias agedecrypt='decrypt_with_age'
