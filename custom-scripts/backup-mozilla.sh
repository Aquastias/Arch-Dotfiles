#!/usr/bin/env bash

# shellcheck source=/dev/null
source "$SHELL_COMMONS/commands.sh"
source "$SHELL_COMMONS/directories.sh"

check_command "gpg"
check_directory "$HOME/.mozilla"

mozilla_archive="mozilla.tar.bz2"

if command_output_contains "gpg --list-keys" "E958CDC0A484DE9E35AC4F6956371D45741FB52C"; then
  tar -cjvf "$mozilla_archive" "$HOME/.mozilla" && gpgtar -u E958CDC0A484DE9E35AC4F6956371D45741FB52C -s -c -o "$mozilla_archive.gpg" "$mozilla_archive"
  rm -rf $mozilla_archive
  mv "$mozilla_archive.gpg" "$DOTFILES/archives"
else
  echo "GPG key not found."
fi
