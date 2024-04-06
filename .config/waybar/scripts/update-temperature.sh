#!/usr/bin/env bash

# Is Hyprland running
if ! hyprctl monitors | grep -q 'Monitor'; then
	exit 0
fi

if ! command -v wl-gammarelay-rs &> /dev/null; then
  echo 'wl-gammarelay-rs command not found! Exiting...'
  exit 127
fi

if ! command -v busctl &> /dev/null; then
  echo 'busctl command not found! Exiting...'
  exit 127
fi

if ! command -v bc &> /dev/null; then
  echo 'bc command not found! Exiting...'
  exit 127
fi

# Get the system timezone
if command -v timedatectl; then
  timezone=$(timedatectl | grep "Time zone" | awk '{print $3}')
else
  timezone=$(date +%Z);
fi

# Set the start and end times for temperature adjustment in 24-hour format
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
midnight=$(date -d "00:00" +"%s")

# Check if the current time is within the specified range
if [[ "$current_time_sec" > "$start_time_sec" && "$current_time_sec" < "$end_time_sec" ]]; then
	# Calculate the temperature value based on the current time (adjust this formula as needed)
	# This formula gradually reduces the temperature value from 6500 to 4500 over the time range
	temperature=$(echo "6500 - 2000 * ($current_time_sec - $start_time_sec) / ($end_time_sec - $start_time_sec)" | bc)

	# In case the temperature falls under 4500 set it back
	if [ "$temperature" -lt 4500 ]; then
		temperature=4500
	fi

	# Set the temperature value using busctl
	busctl --user set-property rs.wl-gammarelay / rs.wl.gammarelay Temperature q "$temperature"
else
	if [[ "$current_time_sec" < "$daylight_time_sec" || "$current_time_sec" -ge "$midnight" ]]; then
		# Before daylight time or at midnight, set temperature to 4500
		busctl --user set-property rs.wl-gammarelay / rs.wl.gammarelay Temperature q 4500
	else
		# After daylight time, set the temperature value to a default (e.g., 6500)
		busctl --user set-property rs.wl-gammarelay / rs.wl.gammarelay Temperature q 6500
	fi
fi
