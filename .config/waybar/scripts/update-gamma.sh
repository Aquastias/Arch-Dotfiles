#!/usr/bin/env bash

# Is Hyprland running
if ! hyprctl monitors | grep -q 'Monitor'; then
  echo 'Hyprland is not running! Exiting...'
  exit 0
fi

if ! command -v wl-gammarelay-rs &>/dev/null; then
  echo 'wl-gammarelay-rs command not found! Exiting...'
  exit 127
fi

if ! command -v busctl &>/dev/null; then
  echo 'busctl command not found! Exiting...'
  exit 127
fi

if ! command -v bc &>/dev/null; then
  echo 'bc command not found! Exiting...'
  exit 127
fi

# Get the system timezone
if command -v timedatectl; then
  timezone=$(timedatectl | grep "Time zone" | awk '{print $3}')
else
  timezone=$(date +%Z)
fi

# Set the start and end times for gamma adjustment in 24-hour format
start_time="16:00"
end_time="23:59"

# Set the daylight time in 24-hour format
daylight_time="08:00"

# Get the current time in HH:MM format in the system's timezone
current_time=$(TZ=$timezone date +"%H:%M")

# Convert start and end times to seconds since midnight
start_time_sec=$(date -d "$start_time" +"%s")
end_time_sec=$(date -d "$end_time" +"%s")
current_time_sec=$(date -d "$current_time" +"%s")
daylight_time_sec=$(date -d "$daylight_time" +"%s")

function is_time_in_interval() {
  local current_time="$1"
  local start_time="$2"
  local end_time="$3"

  if [[ "$current_time" -ge "$start_time" && "$current_time" -le "$end_time" ]]; then
    return 0
  else
    return 1
  fi
}

function set_gamma() {
  local gamma="$1"

  busctl --user set-property rs.wl-gammarelay / rs.wl.gammarelay gamma d "$gamma"
}

if is_time_in_interval "$current_time_sec" "$start_time_sec" "$end_time_sec"; then
  # Calculate the gamma reduction within the time range, with steps of 0.02
  # This formula gradually reduces the gamma value by 0.02 for each 1800 seconds (30 minutes) within the time range
  gamma_step=0.02
  gamma_reduction=$(echo "($current_time_sec - $start_time_sec) / 1800 * $gamma_step" | bc -l 2>/dev/null)
  gamma=$(echo "1.0 - $gamma_reduction" | bc -l 2>/dev/null)

  if (($(echo "$gamma < 0.8" | bc -l 2>/dev/null))); then
    gamma=0.8
  fi

  set_gamma "$gamma"
else
  if [[ "$current_time_sec" -lt "$daylight_time_sec" ]]; then
    set_gamma 0.8
  else
    set_gamma 1.0
  fi
fi
