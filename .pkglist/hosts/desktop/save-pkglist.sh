#!/usr/bin/env bash

pacman -Qqen >"${1:-pkglist-repo.txt}"
pacman -Qqem >"${2:-pkglist-aur.txt}"
