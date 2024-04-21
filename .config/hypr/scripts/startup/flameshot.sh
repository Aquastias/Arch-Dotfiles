#!/usr/bin/env bash

if command -v flameshot &>/dev/null; then
  echo 'Starting flameshot..'
  sleep 10 && /usr/bin/flameshot
else
  echo 'Flameshot is not installed!'
fi
