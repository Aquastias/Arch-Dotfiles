#!/usr/bin/env bash

if ! command -v swaync; then
  echo 'swaync command not found! Exiting...'
  exit 127
fi

sleep 1 && swaync