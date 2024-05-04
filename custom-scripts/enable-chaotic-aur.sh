#!/usr/bin/env bash

# Check if running as root
if [[ $(id -u) -ne 0 ]]; then
    echo "This script must be run as root" 
    exit 1
fi

# Install primary key, keyring and mirrorlist
pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com
pacman-key --lsign-key 3056513887B78AEB
pacman -U 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst'
pacman -U 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst' 

# Check if the pacman.conf already contains the [chaotic-aur] repository
if grep -q "\[chaotic-aur\]" /etc/pacman.conf; then
	echo "pacman.conf already contains the [chaotic-aur] repository configuration."
	exit 0
fi

# Backup original pacman.conf
cp /etc/pacman.conf /etc/pacman.conf.backup

# Define the new repository configuration
new_repo_config="[chaotic-aur]
Include = /etc/pacman.d/chaotic-mirrorlist"

# Read the current pacman.conf
current_pacman_conf=$(cat /etc/pacman.conf)

# Append the new repository configuration
updated_pacman_conf="$current_pacman_conf\n$new_repo_config"

# Write the updated pacman.conf
echo -e "$updated_pacman_conf" > /etc/pacman.conf
echo "New pacman.conf written."
