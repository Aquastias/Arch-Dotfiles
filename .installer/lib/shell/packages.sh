#!/usr/bin/env bash
# lib/shell/packages.sh — pacman package query helpers

function package_installed() {
  pacman -Q "$1" &>/dev/null
}
