#!/usr/bin/env bash

if ! command -v nm-applet &> /dev/null; then
  echo 'nm-applet command not found! Exiting...'
  exit 127
fi

sleep 1 && nm-applet --indicator