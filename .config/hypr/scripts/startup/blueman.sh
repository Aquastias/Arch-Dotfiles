#!/usr/bin/env bash

if ! command -v blueman-applet &>/dev/null; then
  echo 'blueman-applet command not found! Exiting...'
  exit 127
fi

sleep 1 && blueman-applet