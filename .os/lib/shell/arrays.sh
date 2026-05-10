#!/usr/bin/env bash
# lib/shell/arrays.sh — array utility functions

function array_contains() {
  local -r needle="$1"
  shift
  local -ra haystack=("$@")
  local item
  for item in "${haystack[@]}"; do
    [[ "$item" == "$needle" ]] && return 0
  done
  return 1
}

function array_split() {
  local -r separator="$1"
  local -r str="$2"
  local -a ary=()
  IFS="$separator" read -r -a ary <<<"$str"
  echo "${ary[*]}"
}

function array_join() {
  local -r separator="$1"
  shift
  local -ar values=("$@")
  local out=""
  local i
  for ((i = 0; i < ${#values[@]}; i++)); do
    [[ "$i" -gt 0 ]] && out="${out}${separator}"
    out="${out}${values[i]}"
  done
  echo -n "$out"
}

function array_prepend() {
  local -r prefix="$1"
  shift 1
  local -ar ary=("$@")
  local -a updated_ary
  updated_ary=("${ary[@]/#/$prefix}")
  echo "${updated_ary[*]}"
}
