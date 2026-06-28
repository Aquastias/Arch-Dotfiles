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
  "LOCALES|.locales|array"
  "KEYMAP|.keymap|scalar"
  "KEYMAPS|.keymaps|array"
  "KERNEL|.kernel|scalar"
  "KERNELS|.kernels|array"
  "BOOTLOADER|.bootloader|scalar"
  "RPOOL|.rpool|scalar"
  "ROOT_CMDLINE|.root_cmdline|scalar"
  "HOOKS|.hooks|scalar"
  "SSH_ENABLED|.ssh.enabled|bool"
  "SWAP|.swap|bool"
  "ZSWAP_ENABLED|.zswap.enabled|bool"
  "ZSWAP_COMPRESSOR|.zswap.compressor|scalar"
  "ZSWAP_MAX_POOL_PERCENT|.zswap.max_pool_percent|number"
  "ESP_COUNT|.esp_count|number"
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
# load_profile to assemble the persist payload. The .hostname field
# written into install-state.json comes from install_config_hostname,
# which is the machine identity — not the profile name.
install_state_write() {
  local path="$1" profile="$2" host_json persist kernels
  # load_profile prints core-only JSON *and* returns 1 when no host-specific
  # profile exists (its graceful path). Capture stdout and ignore the exit
  # status; fall back to {} only when nothing was printed (a hard load
  # failure). A `|| printf '{}'` here would append a second JSON value onto
  # valid output, corrupting the --argjson persist payload below.
  host_json="$(load_profile "$profile" 2>/dev/null)" || true
  [[ -n "$host_json" ]] || host_json='{}'
  persist="$(_install_state_persist_obj "$host_json")"
  # Full Kernel Selection as a JSON array; KERNEL stays the scalar primary.
  kernels="$(install_config_kernels | jq -R . | jq -sc .)"
  # Locale/Keymap Selection as arrays (element 0 = default); the scalar
  # locale/keymap stay the primaries for back-compat consumers.
  local locales keymaps
  locales="$(install_config_locales | jq -R . | jq -sc .)"
  keymaps="$(install_config_keymaps | jq -R . | jq -sc .)"
  jq -n \
    --arg     hostname    "$(install_config_hostname)"               \
    --arg     timezone    "$(install_config_timezone)"               \
    --arg     locale      "$(install_config_locale)"                 \
    --argjson locales     "$locales"                                 \
    --arg     keymap      "$(install_config_keymap)"                 \
    --argjson keymaps     "$keymaps"                                 \
    --arg     kernel      "$(install_config_kernel)"                 \
    --argjson kernels     "$kernels"                                 \
    --arg     bootloader  "$(install_config_bootloader)"             \
    --arg     rpool       "$LAYOUT_OS_POOL_NAME"                     \
    --arg     root_cmdline "$LAYOUT_ROOT_CMDLINE"                    \
    --arg     hooks       "$LAYOUT_HOOKS"                            \
    --argjson ssh_enabled "$(install_config_ssh_enabled)"            \
    --argjson swap        "$(install_config_swap_enabled)"           \
    --argjson zswap_on    "$(install_config_zswap_enabled)"          \
    --arg     zswap_comp  "$(install_config_zswap_compressor)"       \
    --argjson zswap_pct   "$(install_config_zswap_max_pool_percent)" \
    --argjson esp_count   "${#LAYOUT_ESP_PARTS[@]}"                  \
    --argjson imp_enabled "$(install_config_impermanence_enabled)"   \
    --arg     imp_dataset "$(install_config_impermanence_dataset)"   \
    --arg     imp_mount   "$(install_config_impermanence_mount)"     \
    --argjson persist     "$persist"                                 \
    '{
      hostname:$hostname, timezone:$timezone,
      locale:$locale, locales:$locales,
      keymap:$keymap, keymaps:$keymaps,
      kernel:$kernel, kernels:$kernels,
      bootloader:$bootloader,
      ssh:          { enabled:$ssh_enabled },
      rpool:$rpool, root_cmdline:$root_cmdline, hooks:$hooks,
      swap:$swap,
      zswap: { enabled:$zswap_on, compressor:$zswap_comp,
        max_pool_percent:$zswap_pct },
      esp_count:$esp_count,
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

# =============================================================================
# Credential resolution — the .secrets / .guided_passwords keys
# =============================================================================
# These keys carry filesystem paths to *decrypted* secret files staged in
# tmpfs during install. Two producers write them: the Secrets Module
# (.secrets.*, SOPS-backed) and the Guided Installer's no-SOPS injector
# (.guided_passwords.*). Both belong to this wire format, so their read
# precedence and the SOPS-activation gate live here — the schema's owner —
# instead of being re-encoded as raw jq at every consumer (chroot.sh,
# profiles/runner.sh).

# install_state_credential_path <state> host
# install_state_credential_path <state> user <name>
# Echoes the decrypted-secret file path for a credential role, applying the
# precedence: SOPS .secrets.* first, then the Guided no-SOPS
# .guided_passwords.*. Empty output when neither key is set or <state> is
# absent. Pure: reads <state> only — existence + copy are the caller's job.
install_state_credential_path() {
  local state="$1" role="$2" name="${3:-}"
  [[ -f "$state" ]] || return 0
  case "$role" in
    host)
      jq -r '.secrets.host // .guided_passwords.host // empty' "$state" ;;
    user)
      jq -r --arg n "$name" \
        '.secrets.users[$n] // .guided_passwords.users[$n] // empty' \
        "$state" ;;
    *)
      echo "[install-state] bad credential role: $role" >&2; return 2 ;;
  esac
}

# install_state_activates_sops <state>
# True (0) iff the install records a SOPS secret — .secrets.host set or
# .secrets.users non-empty. The Guided no-SOPS .guided_passwords.* key
# deliberately does NOT activate the SOPS Runtime Service (ADR 0025).
# Reads only; false (1) on a missing file.
install_state_activates_sops() {
  local state="$1"
  [[ -f "$state" ]] || return 1
  jq -e '(.secrets.host // "") != ""
    or ((.secrets.users // {}) | length > 0)' "$state" >/dev/null 2>&1
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
