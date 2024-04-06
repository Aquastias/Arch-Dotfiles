#!/usr/bin/env bash

if command -v hypridle; then
	if ! command -v hyprlock; then
	  if ! command -v swaylock; then
	    echo 'Neither hyprlock or swaylock could be found. Please install at least one of them and adjust the hypridle configuration!'
	    exit 127
          fi
	fi
	
	echo 'hypridle is not running. Starting hypridle.'
	hypridle
else
	if ! command -v swayidle; then
	  echo 'swayidle command not found! Exiting...'
	  exit 127
	fi

	if ! command -v pgrep; then
	  echo 'pgrep command not found! Exiting...'
	  exit 127
	fi

	if ! command -v killall; then
	  echo 'killall command not found! Exiting...'
	  exit 127
	fi

	timeswaylock=600
	timeoff=1200
	pgrep_output=$(pgrep swayidle)
	pgrep_arr=($pgrep_output)

	if [[ "${#pgrep_arr[@]}" == "1" ]] || [[ "${#pgrep_arr[@]}" == "0" ]]; then
	  echo 'swayidle is not running. Starting swayidle.'
	  swayidle -w timeout "$timeswaylock" 'swaylock -f' \
		  timeout "$timeoff" 'hyprctl dispatch dpms off' \
		  resume 'hyprctl dispatch dpms on' \
		  before-sleep 'swaylock -f'
	else
	  echo 'swayidle is running. Killing swayidle.'

	  if ! killall swayidle; then
	    echo 'Failed to kill swayidle. Exiting...'
	    exit 1
	  fi
	fi
fi
