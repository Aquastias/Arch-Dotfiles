#!/usr/bin/env bash

# === Configuration ===
SCAN_DIR="/home"
EXCLUDE_JSON="$PROGRAMS/clamav/clamav_exclude_list.json"
LOG_FILE="/tmp/clamav-scan-$(date +%Y%m%d-%H%M%S).log"
EXIT_ON_FIRST_INFECTION=false
STOP_ON_INFECTION=true

# === Start logging ===
{
  echo "===== ClamAV Daily Scan: $(date) ====="
  echo "Scanning directory: $SCAN_DIR"
} >"$LOG_FILE"

# === Load exclusions from JSON ===
EXCLUDE_ARGS=()

if [[ -f "$EXCLUDE_JSON" ]]; then
  {
    echo "Using exclusion list: $EXCLUDE_JSON"
    echo "--- Excluded Files ---"
  } >>"$LOG_FILE"

  mapfile -t EXCLUDE_FILES < <(jq -r '.exclude_files[]?' "$EXCLUDE_JSON")
  for pattern in "${EXCLUDE_FILES[@]}"; do
    EXCLUDE_ARGS+=(--exclude="$pattern")
    echo "$pattern" >>"$LOG_FILE"
  done

  {
    echo "--- Excluded Directories ---"
  } >>"$LOG_FILE"

  mapfile -t EXCLUDE_DIRS < <(jq -r '.exclude_dirs[]?' "$EXCLUDE_JSON")
  for pattern in "${EXCLUDE_DIRS[@]}"; do
    EXCLUDE_ARGS+=(--exclude-dir="$pattern")
    echo "$pattern" >>"$LOG_FILE"
  done
else
  echo "Exclude list not found: $EXCLUDE_JSON" >>"$LOG_FILE"
fi

if [[ "$EXIT_ON_FIRST_INFECTION" == true ]]; then
  # === Run ClamAV scan and exit on first infection ===
  {
    clamscan -r -i --no-summary "${EXCLUDE_ARGS[@]}" "$SCAN_DIR" 2>&1 |
      while IFS= read -r line; do
        echo "$line" >>"$LOG_FILE"
        if [[ "$line" == *"FOUND" ]]; then
          THREAT=$(echo "$line" | sed 's/ FOUND$//')

          "$SUDO" -u "$SUDO_USER" DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus notify-send -a "ClamAV Daily Scan" \
            -h "string:desktop-entry:clamav" \
            -t 15000 \
            -i "clamav" \
            "[WARNING] ClamAV Alert" \
            "Infection detected: $THREAT"

          echo "[WARNING] Infection detected: $THREAT" >>"$LOG_FILE"

          if [[ "$STOP_ON_INFECTION" == true ]]; then
            echo "[INFO] Stopping scan early due to infection." >>"$LOG_FILE"
            kill $$
          fi
        fi
      done
  } || exit 1
else
  # === Run ClamAV scan and generate summary ===
  SCAN_OUTPUT=$(clamscan -r -i "${EXCLUDE_ARGS[@]}" "$SCAN_DIR")
  echo "$SCAN_OUTPUT" >>"$LOG_FILE"

  # Extract the number of infected files from the output
  INFECTED_COUNT=$(echo "$SCAN_OUTPUT" | grep "Infected files:" | awk '{print $3}')

  if [[ "$INFECTED_COUNT" -gt 0 ]]; then
    "$SUDO" -u "$SUDO_USER" DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus notify-send -a "ClamAV Daily Scan" \
      -h "string:desktop-entry:clamav" \
      -t 15000 \
      -i "clamav" \
      "[WARNING] ClamAV Alert" \
      "Scan completed: $INFECTED_COUNT infected file(s) found. Check latest log: $LOG_FILE"
  else
    echo -e "\n[INFO] No infections found." >>"$LOG_FILE"
  fi
fi
