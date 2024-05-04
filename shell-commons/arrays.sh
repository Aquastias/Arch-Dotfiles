#!/usr/bin/env bash

function string_in_array() {
  local string="$1"
  local array=("$2")
  local found=0

  for element in "${array[@]}"; do
    if [ "$element" == "$string" ]; then
      found=1
      break
    fi
  done

  if [ $found -eq 1 ]; then
    return 0
  else
    return 1
  fi
}
