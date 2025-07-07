#!/usr/bin/env bash

# === Configuration ===
SCAN_DIR="/home"
EXCLUDE_JSON="$PROGRAMS/clamav/clamav_exclude_list.json"
LOG_FILE="/tmp/clamav-scan.log"

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

# === Run ClamAV scan and exit on first infection ===
{
  clamscan -r --infected --no-summary "${EXCLUDE_ARGS[@]}" "$SCAN_DIR" 2>&1 |
    while IFS= read -r line; do
      echo "$line" >>"$LOG_FILE"
      if [[ "$line" == *"FOUND" ]]; then
        THREAT=$(echo "$line" | sed 's/ FOUND$//')
        notify-send --app-name="ClamAV Daily Scan" -t=15000 -i "clamav" "[WARNING] ClamAV Alert" "Infection detected: $THREAT"
        echo "[WARNING] Infection detected: $THREAT" >>"$LOG_FILE"
        exit 1
      fi
    done
} || exit 1

# === If no infection found ===
echo "[SUCCESS] No infections found." >>"$LOG_FILE"
