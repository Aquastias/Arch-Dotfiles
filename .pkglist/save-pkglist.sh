#!/usr/bin/env bash

pacman -Qqen | grep -vE '^(openssh|wpa_supplicant)$' >"${1:-pkglist-repo.txt}"
pacman -Qqem >"${2:-pkglist-aur.txt}"
