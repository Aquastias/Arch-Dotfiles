#!/usr/bin/env bash

if ! command -v firewall-applet &>/dev/null; then
  echo 'firewall-applet command not found! Exiting...'
  exit 127
fi

sleep 10 && firewall-applet