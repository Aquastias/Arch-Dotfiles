#!/usr/bin/env bash
# =============================================================================
# lib/wipe/progress.sh — the Progress Renderer
# =============================================================================
# Pure helpers that turn a disk's bytes-written and size into a per-disk
# progress display: percent, bar, rate, and ETA. No terminal control and no
# device access live here — the orchestrator in 02-wipe.sh owns the live
# multi-line redraw and feeds these functions parsed bytes.
#
# Sourced by 02-wipe.sh. main()-free, so sourcing is inert.
# =============================================================================

# wipe_progress_percent BYTES SIZE
#   Integer percent of SIZE represented by BYTES, clamped to 0..100. Safe when
#   SIZE is 0 (returns 0). Echoes the percent.
wipe_progress_percent() {
  local bytes="$1" size="$2"
  ((size > 0)) || { echo 0; return; }
  local percent=$((bytes * 100 / size))
  ((percent > 100)) && percent=100
  ((percent < 0)) && percent=0
  echo "$percent"
}

# wipe_progress_bar BYTES SIZE [WIDTH]
#   A "[####----]" bar WIDTH cells wide (default 20), filled to the clamped
#   percent. Echoes the bar.
wipe_progress_bar() {
  local bytes="$1" size="$2" width="${3:-20}" percent fill bar pad
  percent="$(wipe_progress_percent "$bytes" "$size")"
  fill=$((percent * width / 100))
  ((fill > width)) && fill=$width
  printf -v bar '%*s' "$fill" ''
  printf -v pad '%*s' "$((width - fill))" ''
  printf '[%s%s]' "${bar// /#}" "${pad// /-}"
}

# wipe_progress_parse_bytes STREAM
#   dd status=progress separates samples with \r; each is "<N> bytes (...)
#   copied, ...". Echoes the latest sample's byte count, or nothing when no
#   sample is present yet.
wipe_progress_parse_bytes() {
  printf '%s' "$1" | awk 'BEGIN { RS = "\r|\n" }
    match($0, /^[0-9]+ bytes/) { latest = substr($0, 1, RLENGTH - 6) }
    END { if (latest != "") print latest }'
}

# _progress_humanize N [SUFFIX]
#   Humanize N bytes in SI units (/1000, matching dd's own rate display):
#   "82 MB", "512 KB", … Echoes the value with the given SUFFIX appended.
_progress_humanize() {
  local byte_count="$1" suffix="${2:-}" unit="B" divisor=1
  if   ((byte_count >= 1000000000000)); then unit="TB"; divisor=1000000000000
  elif ((byte_count >= 1000000000));    then unit="GB"; divisor=1000000000
  elif ((byte_count >= 1000000));       then unit="MB"; divisor=1000000
  elif ((byte_count >= 1000));          then unit="KB"; divisor=1000
  fi
  echo "$((byte_count / divisor)) ${unit}${suffix}"
}

# wipe_progress_rate BYTES SECONDS
#   Average SI throughput, "82 MB/s". Zero/negative SECONDS → "0 B/s".
wipe_progress_rate() {
  local bytes="$1" seconds="$2"
  ((seconds > 0)) || { echo "0 B/s"; return; }
  _progress_humanize $((bytes / seconds)) "/s"
}

# _progress_hms SECONDS  → "mm:ss", or "h:mm:ss" past an hour.
_progress_hms() {
  local seconds="$1"
  if ((seconds >= 3600)); then
    printf '%d:%02d:%02d' $((seconds / 3600)) $((seconds % 3600 / 60)) \
      $((seconds % 60))
  else
    printf '%02d:%02d' $((seconds / 60)) $((seconds % 60))
  fi
}

# wipe_progress_eta BYTES SIZE SECONDS
#   Estimated time to completion at the average rate so far. "--:--" until at
#   least one byte is written (rate unknown); "00:00" once complete.
wipe_progress_eta() {
  local bytes="$1" size="$2" seconds="$3"
  (("$bytes" > 0 && "$seconds" > 0)) || { echo "--:--"; return; }
  local remaining=$((size - bytes))
  ((remaining <= 0)) && { echo "00:00"; return; }
  # remaining / rate, where rate = bytes / secs → remaining * secs / bytes.
  _progress_hms $((remaining * seconds / bytes))
}

# wipe_progress_line LABEL BYTES SIZE SECONDS [WIDTH]
#   The full per-disk status line the orchestrator prints for an in-flight
#   HDD wipe: "sda  [#####-----]  50%  5 B/s  ETA 00:10".
wipe_progress_line() {
  local label="$1" bytes="$2" size="$3" seconds="$4" width="${5:-20}"
  printf '%s  %s  %3s%%  %s  ETA %s' \
    "$label" \
    "$(wipe_progress_bar "$bytes" "$size" "$width")" \
    "$(wipe_progress_percent "$bytes" "$size")" \
    "$(wipe_progress_rate "$bytes" "$seconds")" \
    "$(wipe_progress_eta "$bytes" "$size" "$seconds")"
}
