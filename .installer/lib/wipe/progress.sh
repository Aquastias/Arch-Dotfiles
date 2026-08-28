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

# progress_pct BYTES SIZE
#   Integer percent of SIZE represented by BYTES, clamped to 0..100. Safe when
#   SIZE is 0 (returns 0). Echoes the percent.
progress_pct() {
  local bytes="$1" size="$2"
  ((size > 0)) || { echo 0; return; }
  local pct=$((bytes * 100 / size))
  ((pct > 100)) && pct=100
  ((pct < 0)) && pct=0
  echo "$pct"
}

# progress_bar BYTES SIZE [WIDTH]
#   A "[####----]" bar WIDTH cells wide (default 20), filled to the clamped
#   percent. Echoes the bar.
progress_bar() {
  local bytes="$1" size="$2" width="${3:-20}" pct fill bar pad
  pct="$(progress_pct "$bytes" "$size")"
  fill=$((pct * width / 100))
  ((fill > width)) && fill=$width
  printf -v bar '%*s' "$fill" ''
  printf -v pad '%*s' "$((width - fill))" ''
  printf '[%s%s]' "${bar// /#}" "${pad// /-}"
}

# progress_parse_bytes STREAM
#   dd status=progress separates samples with \r; each is "<N> bytes (...)
#   copied, ...". Echoes the latest sample's byte count, or nothing when no
#   sample is present yet.
progress_parse_bytes() {
  printf '%s' "$1" | tr '\r' '\n' \
    | grep -oE '^[0-9]+ bytes' | tail -n1 | grep -oE '^[0-9]+' || true
}

# _progress_si N [SUFFIX]
#   Humanize N bytes in SI units (/1000, matching dd's own rate display):
#   "82 MB", "512 KB", … Echoes the value with the given SUFFIX appended.
_progress_si() {
  local n="$1" suffix="${2:-}" unit="B" div=1
  if   ((n >= 1000000000000)); then unit="TB"; div=1000000000000
  elif ((n >= 1000000000));    then unit="GB"; div=1000000000
  elif ((n >= 1000000));       then unit="MB"; div=1000000
  elif ((n >= 1000));          then unit="KB"; div=1000
  fi
  echo "$((n / div)) ${unit}${suffix}"
}

# progress_rate BYTES SECONDS
#   Average SI throughput, "82 MB/s". Zero/negative SECONDS → "0 B/s".
progress_rate() {
  local bytes="$1" secs="$2"
  ((secs > 0)) || { echo "0 B/s"; return; }
  _progress_si $((bytes / secs)) "/s"
}

# _progress_hms SECONDS  → "mm:ss", or "h:mm:ss" past an hour.
_progress_hms() {
  local s="$1"
  if ((s >= 3600)); then
    printf '%d:%02d:%02d' $((s / 3600)) $((s % 3600 / 60)) $((s % 60))
  else
    printf '%02d:%02d' $((s / 60)) $((s % 60))
  fi
}

# progress_eta BYTES SIZE SECONDS
#   Estimated time to completion at the average rate so far. "--:--" until at
#   least one byte is written (rate unknown); "00:00" once complete.
progress_eta() {
  local bytes="$1" size="$2" secs="$3"
  (("$bytes" > 0 && "$secs" > 0)) || { echo "--:--"; return; }
  local remaining=$((size - bytes))
  ((remaining <= 0)) && { echo "00:00"; return; }
  # remaining / rate, where rate = bytes / secs → remaining * secs / bytes.
  _progress_hms $((remaining * secs / bytes))
}

# progress_line LABEL BYTES SIZE SECONDS [WIDTH]
#   The full per-disk status line the orchestrator prints for an in-flight
#   HDD wipe: "sda  [#####-----]  50%  5 B/s  ETA 00:10".
progress_line() {
  local label="$1" bytes="$2" size="$3" secs="$4" width="${5:-20}"
  printf '%s  %s  %3s%%  %s  ETA %s' \
    "$label" \
    "$(progress_bar "$bytes" "$size" "$width")" \
    "$(progress_pct "$bytes" "$size")" \
    "$(progress_rate "$bytes" "$secs")" \
    "$(progress_eta "$bytes" "$size" "$secs")"
}
