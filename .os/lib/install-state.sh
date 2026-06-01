#!/usr/bin/env bash
# =============================================================================
# lib/install-state.sh — Install State wire format (host ↔ chroot)
# =============================================================================
# Sole owner of the install-state.json schema. Writer runs on the host,
# loader runs inside arch-chroot. Schema declared once below as
# pipe-delimited specs: "VAR_NAME|jq-path|type" where type ∈
# {scalar, bool, array}. Loader iterates the list; writer assembles the
# matching JSON shape. Round-trip test catches drift.
#
# No JSON-level defaults — every schema field must be present in the
# wire format; absence is an error.
# =============================================================================

# "VAR|.path|type"
_INSTALL_STATE_SCHEMA=(
  "HOSTNAME|.hostname|scalar"
  "TIMEZONE|.timezone|scalar"
  "LOCALE|.locale|scalar"
  "KEYMAP|.keymap|scalar"
  "KERNEL|.kernel|scalar"
  "KERNELS|.kernels|array"
  "BOOTLOADER|.bootloader|scalar"
  "RPOOL|.rpool|scalar"
  "SWAP|.swap|bool"
  "ESP_COUNT|.esp_count|number"
  "EXTRAS_BACKUP|.extras.backup|bool"
  "EXTRAS_SECURITY|.extras.security|bool"
  "IMPERMANENCE_ENABLED|.impermanence.enabled|bool"
  "IMPERMANENCE_DATASET|.impermanence.dataset|scalar"
  "IMPERMANENCE_MOUNT|.impermanence.mount|scalar"
  "PERSIST_DIRECTORIES|.persist.directories|array"
  "PERSIST_FILES|.persist.files|array"
)

# install_state_load <path>
# Sources every schema field as a shell variable. Returns 1 (no exit) on
# missing file or missing field, with field name on stderr.
install_state_load() {
  local path="$1" spec var jq_path type value
  [[ -f "$path" ]] || {
    echo "[install-state] missing file: $path" >&2; return 1
  }
  for spec in "${_INSTALL_STATE_SCHEMA[@]}"; do
    IFS='|' read -r var jq_path type <<< "$spec"
    if ! _install_state_has_path "$path" "$jq_path"; then
      echo "[install-state] missing field: $jq_path" >&2
      return 1
    fi
    if [[ "$type" == "array" ]]; then
      mapfile -t "$var" < <(jq -r "${jq_path}[]" "$path")
      export "${var?}"
    else
      value="$(jq -r "$jq_path" "$path")"
      printf -v "$var" '%s' "$value"
      export "${var?}"
    fi
  done
}

# install_state_write <path> <profile>
# <profile> is the Host Profile (directory key under hosts/), used only for
# load_host_config to assemble the persist payload. The .hostname field
# written into install-state.json comes from install_config_hostname,
# which is the machine identity — not the profile name.
install_state_write() {
  local path="$1" profile="$2" host_json persist kernels
  # load_host_config prints core-only JSON *and* returns 1 when no host-specific
  # config exists (its graceful path). Capture stdout and ignore the exit
  # status; fall back to {} only when nothing was printed (a hard load
  # failure). A `|| printf '{}'` here would append a second JSON value onto
  # valid output, corrupting the --argjson persist payload below.
  host_json="$(load_host_config "$profile" 2>/dev/null)" || true
  [[ -n "$host_json" ]] || host_json='{}'
  persist="$(_install_state_persist_obj "$host_json")"
  # Full Kernel Selection as a JSON array; KERNEL stays the scalar primary.
  kernels="$(install_config_kernels | jq -R . | jq -sc .)"
  jq -n \
    --arg     hostname    "$(install_config_hostname)"               \
    --arg     timezone    "$(install_config_timezone)"               \
    --arg     locale      "$(install_config_locale)"                 \
    --arg     keymap      "$(install_config_keymap)"                 \
    --arg     kernel      "$(install_config_kernel)"                 \
    --argjson kernels     "$kernels"                                 \
    --arg     bootloader  "$(install_config_bootloader)"             \
    --arg     rpool       "$LAYOUT_OS_POOL_NAME"                     \
    --argjson swap        "$(install_config_swap_enabled)"           \
    --argjson esp_count   "${#LAYOUT_ESP_PARTS[@]}"                  \
    --argjson backup      "$(install_config_extras_backup)"          \
    --argjson security    "$(install_config_extras_security)"        \
    --argjson imp_enabled "$(install_config_impermanence_enabled)"   \
    --arg     imp_dataset "$(install_config_impermanence_dataset)"   \
    --arg     imp_mount   "$(install_config_impermanence_mount)"     \
    --argjson persist     "$persist"                                 \
    '{
      hostname:$hostname, timezone:$timezone, locale:$locale,
      keymap:$keymap, kernel:$kernel, kernels:$kernels,
      bootloader:$bootloader,
      rpool:$rpool, swap:$swap, esp_count:$esp_count,
      extras:       { backup:$backup, security:$security },
      impermanence: { enabled:$imp_enabled, dataset:$imp_dataset,
        mount:$imp_mount },
      persist:$persist
    }' > "$path"
}

# install_state_update <path> <jq-path> <json-value>
# Mutates state JSON in place. <json-value> must be a JSON-encoded value
# (caller responsibility — e.g. '"some string"', 'true', '42').
install_state_update() {
  local path="$1" jq_path="$2" value="$3" tmp
  tmp="$(mktemp)"
  jq --argjson v "$value" "${jq_path} = \$v" "$path" > "$tmp"
  mv "$tmp" "$path"
}

# Builds the .persist sub-object from a merged host config JSON string.
_install_state_persist_obj() {
  printf '%s' "${1:-{\}}" | jq '{
    directories: (.persist.directories // []),
    files:       (.persist.files       // [])
  }'
}

# Returns true iff every segment exists (parent contains key) AND the
# final value is not JSON null. Path is dotted: ".a.b.c".
_install_state_has_path() {
  local file="$1" path="$2"
  jq --arg p "${path#.}" -e '
    ($p | split(".")) as $segs
    | reduce $segs[] as $k (.;
        if type=="object" and has($k) then .[$k] else null end)
    | . != null
  ' "$file" >/dev/null 2>&1
}
