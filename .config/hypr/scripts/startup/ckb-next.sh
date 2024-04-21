#!/usr/bin/env bash

if ! command -v ckb-next &>/dev/null; then
  echo 'ckb-next command not found! Exiting...'
  exit 127
fi

sleep 1 && ckb-next --background &