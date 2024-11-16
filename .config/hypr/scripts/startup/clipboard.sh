#!/usr/bin/env bash

#if ! command -v cliphist &>/dev/null; then
#  echo 'cliphist command not found! Exiting...'
#  exit 127
#fi

#if ! command -v wl-paste &>/dev/null; then
#  echo 'wl-paste command not found! Exiting...'
#  exit 127
#fi

sleep 1 && clipse -listen
#sleep 1 && clipse -wl-store
#sleep 1 && wl-clip-persist --clipboard both
#sleep 1 && clipse -p | bash -c '[[ "$(xclip -selection clipboard -o)" == "$(clipse -p)" ]] || [[ "$(clipse -clear-text && clipse -p)" == "" ]] && xclip -selection clipboard'
sleep 1 && wl-paste -t text -w bash -c '[ "$(xclip -selection clipboard -o)" = "$(wl-paste -n)" ] || [ "$(wl-paste -l | grep image)" = "" ] && xclip -selection clipboard'


#sleep 1 && wl-paste --type text --watch cliphist store
#sleep 1 && wl-paste --type image --watch cliphist store
