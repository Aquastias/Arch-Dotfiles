#!/usr/bin/env bash

# shellcheck source=/dev/null

# Extract most know archives with one command
function extract_archive () {
	for archive in "$@"; do
		if [ -f "$archive" ] ; then
			case $archive in
				*.tar.bz2)   tar xvjf "$archive"    ;;
				*.tar.gz)    tar xvzf "$archive"    ;;
				*.bz2)       bunzip2 "$archive"     ;;
				*.rar)       type -P rar >/dev/null && rar x "$archive" || echo "rar command not found. Install rar to extract '$archive'." ;;
				*.gz)        gunzip "$archive"      ;;
				*.tar)       tar xvf "$archive"     ;;
				*.tbz2)      tar xvjf "$archive"    ;;
				*.tgz)       tar xvzf "$archive"    ;;
				*.zip)       unzip "$archive"       ;;
				*.Z)         uncompress "$archive"  ;;
				*.7z)        7z x "$archive"        ;;
				*)           echo "don't know how to extract '$archive'..." ;;
			esac
		else
			echo "'$archive' is not a valid file!"
		fi
	done
}

# Searches for text in files in a specified folder
function find_text_in_files () {
  if [ -d "$1" ]; then
      folder="$1"
      shift
  else
      folder="."
  fi

  # Use find to search for only files (not directories)
  # Use -type f to exclude directories
  # Use -not -path '*/\.*' to exclude hidden files
  # Use -print0 and xargs -0 to handle filenames with spaces
  # Use grep -nH --color=always to print line numbers and highlight matches
  find "$folder" -type f -not -path '*/\.*' -print0 | xargs -0 grep -nHir --color=always "$@" | less -R
}

# Copies a file and displays progress
function copy_progress_bar() {
  # Check that source and destination files exist
  if [ ! -e "$1" ]; then
    echo "Error: Source file '$1' does not exist." >&2
    return 1
  fi
  if [ -e "$2" ]; then
    echo "Error: Destination file '$2' already exists." >&2
    return 1
  fi

  # Use pv to display progress while copying the file
  pv --progress --eta "$1" > "$2"
}

# Copies a file and changes to the destination directory
function copy_and_go() {
  # Check that source file exists
  if [ ! -f "$1" ]; then
    echo "Error: Source file '$1' does not exist." >&2
    return 1
  fi

  # Check that destination directory exists and is writable
  if [ ! -d "$2" ]; then
    echo "Error: Destination directory '$2' does not exist." >&2
    return 1
  elif [ ! -w "$2" ]; then
    echo "Error: Destination directory '$2' is not writable." >&2
    return 1
  fi

  # Copy file and change to destination directory
  if cp "$1" "$2"; then
    echo "File copied successfully."
    cd "$2" || return 1
  else
    echo "Error: Copy operation failed." >&2
    return 1
  fi
}

# Moves a file and changes to the destination directory
function move_and_go() {
  # Check that source file exists
  if [ ! -e "$1" ]; then
    echo "Error: Source file '$1' does not exist." >&2
    return 1
  fi

  # Check that destination directory exists and is writable
  if [ ! -d "$2" ]; then
    echo "Error: Destination directory '$2' does not exist." >&2
    return 1
  elif [ ! -w "$2" ]; then
    echo "Error: Destination directory '$2' is not writable." >&2
    return 1
  fi

  # Move file and change to destination directory
  mv "$1" "$2" && cd "$2" || return 1
}

# Creates a directory and changes to it
function mkdir_and_go() {
  # Check that the directory name is provided
  if [ -z "$1" ]; then
    echo "Error: No directory name provided." >&2
    return 1
  fi

  # Create directory and change to it
  mkdir -p "$1" && cd "$1" || return 1
}

# Goes up a specified number of directories
function up_n_dirs() {
  # Default to going up one directory
  local levels=${1:-1}

  # Build the string of '..' levels
  local dots=""
  for (( i=1; i<=levels; i++ )); do
    dots="../$dots"
  done

  # Change to the target directory
  if cd "$dots"; then
    pwd
  else
    echo "Error: Failed to change directory." >&2
    return 1
  fi
}

# Returns the last two fields of the working directory
function pwd_last_two () {
  printf '%s\n' "$(pwd | awk -F/ '{printf "%s/%s\n", $(NF-1), $NF}')"
}

# Show current network information
function network_info() {
  echo "--------------- Network Information ---------------"
  ip addr show | awk '/inet / {print "IP Address:",$2} /inet /{print "Netmask:",$4} /ether /{print "MAC Address:",$2} '
  echo "---------------------------------------------------"
}

# IP address lookup
function whatsmyip () {
  # Dumps a list of all IP addresses for every device
  # /sbin/ifconfig |grep -B1 "inet addr" |awk '{ if ( $1 == "inet" ) { print $2 } else if ( $2 == "Link" ) { printf "%s:" ,$1 } }' |awk -F: '{ print $1 ": " $3 }';

  # Internal IP Lookup
  local internal_ip
  internal_ip=$(ip addr show | awk '/inet / {print $2}' | cut -d '/' -f 1)
  echo "Internal IP: ${internal_ip}"

  # External IP Lookup
  local external_ip
  external_ip=$(curl -s http://ifconfig.me/ip)
  if [ -z "${external_ip}" ]; then
      echo "Failed to retrieve external IP address"
  else
      echo "External IP: ${external_ip}"
  fi
}

# Set the command prompt
function __setprompt() {
  local last_exit_status=$?

  # Define colors
  local dark_gray
  local red
  local light_red
  local green
  local yellow
  local blue
  local magenta
  local cyan
  local no_color

  dark_gray="$(tput setaf 8)"
  red="$(tput setaf 1)"
  light_red="$(tput setaf 9)"
  green="$(tput setaf 2)"
  yellow="$(tput setaf 11)"
  blue="$(tput setaf 4)"
  magenta="$(tput setaf 5)"
  cyan="$(tput setaf 6)"
  no_color="$(tput sgr0)"

  # Show error exit code if there is one
  if [[ $last_exit_status -ne 0 ]]; then
      PS1+="\[${dark_gray}\](\[${light_red}\]ERROR\[${dark_gray}\])-(\[${red}\]Exit Code \[${light_red}\]$last_exit_status\[${dark_gray}\])-(\[${red}\]"
      case $last_exit_status in
          1) PS1+="General error";;
          2) PS1+="Missing keyword, command, or permission problem";;
          126) PS1+="Permission problem or command is not an executable";;
          127) PS1+="Command not found";;
          128) PS1+="Invalid argument to exit";;
          # Use an associative array to map signal numbers to descriptions
          [0-9]|[0-9][0-9]|[0-9][0-9][0-9]) PS1+="Fatal error signal ${last_exit_status}";;
          130) PS1+="Script terminated by Control-C";;
          *) PS1+="Unknown error code";;
      esac
      PS1+="\[${dark_gray}\])\[${no_color}\]\n"
  else
      PS1=""
  fi

  # Date and Time
  PS1+="\[${dark_gray}\](\[${cyan}\]\$(date +'%a %b %-d') ${blue}\$(date +'%-I:%M:%S%P')\[${dark_gray}\])"

  # CPU
  if command -v "sensors" >/dev/null; then
      CPU_TEMP=$(sensors | awk '/^Package/ {print $4}')
      PS1+="(\[${magenta}\]CPU ${CPU_TEMP}°C"
  else
      PS1+="(\[${magenta}\]CPU $(top -bn1 | awk '/^%Cpu/ {print $2}')%"
  fi

  # Jobs
  PS1+="\[${dark_gray}\]:\[${magenta}\]\j"

  # Network Connections (for a server - comment out for non-server)
  if [[ -f "/proc/net/tcp" ]]; then
      PS1+="\[${dark_gray}\]:\[${magenta}\]Net $(awk 'END {print NR}' /proc/net/tcp)"
  fi

  # User and server
  if [[ -n "$SSH_CLIENT" ]] || [[ -n "$SSH2_CLIENT" ]]; then
      if [[ -n "$SSH_CLIENT" ]] && [[ -n "$SSH2_CLIENT" ]]; then
          PS1+="\[${dark_gray}\])- (\[${red}\]\u@\h\[${dark_gray}\]:\[${yellow}\]ssh2\[${dark_gray}\]-\[${green}\]${SSH2_IP}\[${dark_gray}\]/\[${yellow}\]ssh\[${dark_gray}\]-\[${green}\]${SSH_IP}\[${dark_gray}\])"
      elif [[ -n "$SSH_CLIENT" ]]; then
          PS1+="\[${dark_gray}\])- (\[${red}\]\u@\h\[${dark_gray}\]:\[${yellow}\]ssh\[${dark_gray}\]-\[${green}\]${SSH_IP}\[${dark_gray}\])"
      else
          PS1+="\[${dark_gray}\])- (\[${red}\]\u@\h\[${dark_gray}\]:\[${yellow}\]ssh2\[${dark_gray}\]-\[${green}\]${SSH2_IP}\[${dark_gray}\])"
      fi
  else
      PS1+="\[${dark_gray}\])- (\[${red}\]\u@\h\[${dark_gray}\])"
  fi

  # Current directory
  PS1+="\[${dark_gray}\]:\[${yellow}\]\w\[${dark_gray}\])-"

  # Total size of files in current directory
  size=$(du -shs . 2>/dev/null | awk '{print $1}')

  if [[ -n "$size" ]]; then
    PS1+="(\[${green}\]$size\[${dark_gray}\]:"
  fi

  # Number of files
  PS1+="\[${green}\]$(ls -1A | wc -l | awk '{$1=$1};1')\[${dark_gray}\])"

  # Skip to the next line
  PS1+="\n"

  if [[ $EUID -ne 0 ]]; then
    PS1+="\[${green}\]❯\[${no_color}\] " # Normal user
  else
    PS1+="\[${RED}\]❯\[${no_color}\] " # Root user
  fi

  # PS2 is used to continue a command using the \ character
  PS2="\[${dark_gray}\]❯\[${no_color}\] "

  # PS3 is used to enter a number choice in a script
  PS3='Please enter a number from the above list: '

  # PS4 is used for tracing a script in debug mode
  PS4='\[${dark_gray}\]+\[${no_color}\] '
}

# Querying cht.sh
function chtsh () {
  local languages=("typescript" "js" "rust" "nodejs" "bash")
  local core_utils=("xargs" "find" "mv" "sed" "awk")

  # Prompt the user to select a language or core utility
  selected=$(printf "%s\n" "${languages[@]}" "${core_utils[@]}" | fzf)

  # If the user selected a language, query the cheat sheet website for that language
  if [[ "${languages[*]}" =~ $selected ]]; then
    read -p "Enter your query: " query
    curl -s "cht.sh/$selected/$query"
  # If the user selected a core utility, display its man page
  elif [[ "${core_utils[*]}" =~ $selected ]]; then
    man "$selected"
  fi
}