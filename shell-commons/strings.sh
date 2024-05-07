#!/usr/bin/env bash

function string_contains() {
  string="$1"
  substring="$2"

  if [[ "$string" == *"$substring"* ]]; then
    return 0
  else
    return 1
  fi
}
