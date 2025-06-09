#!/usr/bin/env bash

function package_installed() {
  pacman -Q "$1" &>/dev/null
}
