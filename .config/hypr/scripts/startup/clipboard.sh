#!/usr/bin/env bash

if ! command -v cliphist &> /dev/null; then
  echo 'cliphist command not found! Exiting...'
  exit 127
fi

if ! command -v wl-paste &> /dev/null; then
  echo 'wl-paste command not found! Exiting...'
  exit 127
fi

sleep 1 && wl-paste --type text --watch cliphist store
sleep 1 && wl-paste --type image --watch cliphist store