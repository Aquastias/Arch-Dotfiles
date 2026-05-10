#!/usr/bin/env bash
# lib/shell/strings.sh — string utility functions

function string_contains() {
  local -r haystack="$1"
  local -r needle="$2"
  [[ "$haystack" == *"$needle"* ]]
}

function string_multiline_contains() {
  local -r haystack="$1"
  local -r needle="$2"
  echo "$haystack" | grep -q "$needle"
}

function string_to_uppercase() {
  local -r str="$1"
  echo "$str" | awk '{print toupper($0)}'
}

function string_strip_prefix() {
  local -r str="$1"
  local -r prefix="$2"
  # SC2295: prefix is data, not a glob pattern — quote so '*' / '?' are literal.
  echo "${str#"$prefix"}"
}

function string_strip_suffix() {
  local -r str="$1"
  local -r suffix="$2"
  # SC2295: suffix is data, not a glob pattern — quote so '*' / '?' are literal.
  echo "${str%"$suffix"}"
}

function string_is_empty_or_null() {
  local -r response="$1"
  [[ -z "$response" || "$response" == "null" ]]
}

function string_substr() {
  local -r str="$1"
  local -r start="$2"
  local end="$3"

  if [[ "$start" -lt 0 || "$end" -lt 0 ]]; then
    echo "Error: string_substr: start and end must be >= 0." >&2
    exit 1
  fi
  if [[ "$start" -gt "$end" ]]; then
    echo "Error: string_substr: start must be <= end." >&2
    exit 1
  fi
  [[ -z "$end" ]] && end="${#str}"
  echo "${str:$start:$end}"
}
