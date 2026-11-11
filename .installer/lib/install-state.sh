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
  "CONSOLE_FONT|.console_font|scalar"
  "KERNEL|.kernel|scalar"
  "KERNELS|.kernels|array"
  "BOOTLOADER|.bootloader|scalar"
  "ROOT_SHELL|.root_shell|scalar"
  "FILESYSTEM|.filesystem|scalar"
  "RPOOL|.rpool|scalar"
  "ROOT_CMDLINE|.root_cmdline|scalar"
  "HOOKS|.hooks|scalar"
  "GPU|.gpu|array"
  "DISPLAY_MANAGER|.display_manager|scalar"
  "SSH_ENABLED|.ssh.enabled|bool"
  "SWAP|.swap|bool"
  "ZSWAP_ENABLED|.zswap.enabled|bool"
  "ZSWAP_COMPRESSOR|.zswap.compressor|scalar"
  "ZSWAP_MAX_POOL_PERCENT|.zswap.max_pool_percent|number"
  "ZFS_ARC_MAX|.zfs.arc_max|scalar"
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
  local path="$1" spec variable jq_path type value
  [[ -f "$path" ]] || {
    echo "[install-state] missing file: $path" >&2; return 1
  }
  for spec in "${_INSTALL_STATE_SCHEMA[@]}"; do
    IFS='|' read -r variable jq_path type < <(printf '%s\n' "$spec")
    if ! _install_state_has_path "$path" "$jq_path"; then
      echo "[install-state] missing field: $jq_path" >&2
      return 1
    fi
    if [[ "$type" == "array" ]]; then
      # The array field's items, one per line.
      mapfile -t "$variable" < <(jq -r "${jq_path}[]" "$path")
      export "${variable?}"
    else
      # The field's value.
      value="$(jq -r "$jq_path" "$path")"
      export "$variable=$value"
    fi
  done
}

# The install-state.json shape. Keys are read by the chroot modules — frozen.
# shellcheck disable=SC2016 # a jq template, not shell
_INSTALL_STATE_TEMPLATE='{
  hostname:$hostname, timezone:$timezone,
  locale:$locale, locales:$locales,
  keymap:$keymap, keymaps:$keymaps,
  console_font:$console_font,
  kernel:$kernel, kernels:$kernels,
  bootloader:$bootloader,
  root_shell:$root_shell,
  filesystem:$filesystem,
  ssh:          { enabled:$ssh_enabled },
  rpool:$rpool, root_cmdline:$root_cmdline, hooks:$hooks,
  gpu:$gpu,
  display_manager:$display_manager,
  swap:$swap,
  zswap: { enabled:$zswap_enabled, compressor:$zswap_compressor,
    max_pool_percent:$zswap_max_pool_percent },
  zfs:   { arc_max:$zfs_arc_max },
  apparmor:$apparmor,
  esp_count:$esp_count,
  impermanence: { enabled:$impermanence_enabled,
    dataset:$impermanence_dataset, mount:$impermanence_mount },
  persist:$persist
}'

# _install_state_json_array — stdin lines as a compact JSON string array.
# (The `|| -n` keeps a last line that has no newline.)
_install_state_json_array() {
  local line array='[]'
  while IFS= read -r line || [[ -n "$line" ]]; do
    # The array so far, with this line added at the end.
    array="$(jq -cn --argjson array "$array" --arg line "$line" \
      '$array + [$line]')"
  done
  printf '%s\n' "$array"
}

# _install_state_gpu_json — the resolved GPU vendor list (auto → detected
# vendors) threaded to the chroot, where the GPU Configuration Module decides
# whether to harden (ADR 0053). `${VAR+x}` guards the unset case under `set -u`
# (empty → []).
_install_state_gpu_json() {
  if [[ ${ENVIRONMENT_GPU+x} && ${#ENVIRONMENT_GPU[@]} -gt 0 ]]; then
    printf '%s\n' "${ENVIRONMENT_GPU[@]}" | _install_state_json_array
  else
    printf '[]\n'
  fi
}

# install_state_write <path>
# Everything comes from the effective config (install_config_*) and the
# resolved layout/environment globals — persist included, so Guided-added
# paths count and no profile is looked up by name (hostname ≠ profile name,
# ADR 0020). The .hostname field is install_config_hostname, the machine
# identity.
install_state_write() {
  local path="$1" persist kernels locales keymaps
  persist="$(install_config_persist_json)"
  # Full Kernel Selection as a JSON array; KERNEL stays the scalar primary.
  kernels="$(install_config_kernels | _install_state_json_array)"
  # Locale/Keymap Selection as arrays (element 0 = default); the scalar
  # locale/keymap stay the primaries for back-compat consumers.
  locales="$(install_config_locales | _install_state_json_array)"
  keymaps="$(install_config_keymaps | _install_state_json_array)"
  # The install-state.json object, from the template above.
  jq -n \
    --arg     hostname     "$(install_config_hostname)"               \
    --arg     timezone     "$(install_config_timezone)"               \
    --arg     locale       "$(install_config_locale)"                 \
    --argjson locales      "$locales"                                 \
    --arg     keymap       "$(install_config_keymap)"                 \
    --argjson keymaps      "$keymaps"                                 \
    --arg     console_font "$(install_config_console_font)"           \
    --arg     kernel       "$(install_config_kernel)"                 \
    --argjson kernels      "$kernels"                                 \
    --arg     bootloader   "$(install_config_bootloader)"             \
    --arg     root_shell   "$(install_config_root_shell)"             \
    --arg     filesystem   "$(install_config_filesystem)"             \
    --arg     rpool        "$LAYOUT_OS_POOL_NAME"                     \
    --arg     root_cmdline "$LAYOUT_ROOT_CMDLINE"                     \
    --arg     hooks        "$LAYOUT_HOOKS"                            \
    --argjson gpu          "$(_install_state_gpu_json)"               \
    --arg display_manager "${ENVIRONMENT_DISPLAY_MANAGER:-none}"      \
    --argjson ssh_enabled  "$(install_config_ssh_enabled)"            \
    --argjson swap         "$(install_config_swap_enabled)"           \
    --argjson zswap_enabled "$(install_config_zswap_enabled)"         \
    --arg zswap_compressor "$(install_config_zswap_compressor)"       \
    --argjson zswap_max_pool_percent \
      "$(install_config_zswap_max_pool_percent)"                      \
    --arg zfs_arc_max "$(install_config_zfs_arc_max)"               \
    --argjson esp_count    "${#LAYOUT_ESP_PARTS[@]}"                  \
    --argjson apparmor     "$(install_config_apparmor_enabled)"        \
    --argjson impermanence_enabled \
      "$(install_config_impermanence_enabled)"                        \
    --arg impermanence_dataset "$(install_config_impermanence_dataset)" \
    --arg impermanence_mount "$(install_config_impermanence_mount)"   \
    --argjson persist      "$persist"                                 \
    "$_INSTALL_STATE_TEMPLATE" > "$path"
}

# install_state_update <path> <jq-path> <json-value>
# Mutates state JSON in place. <json-value> must be a JSON-encoded value
# (caller responsibility — e.g. '"some string"', 'true', '42').
install_state_update() {
  local path="$1" jq_path="$2" value="$3" temporary_file
  temporary_file="$(mktemp)"
  # The state with <jq-path> set to the value.
  jq --argjson v "$value" "${jq_path} = \$v" "$path" > "$temporary_file"
  mv "$temporary_file" "$path"
}

# =============================================================================
# Credential resolution — the .secrets / .guided_passwords keys
# =============================================================================
# These keys carry tmpfs paths to *decrypted* secret files. Two producers: the
# Secrets Module (.secrets.*, SOPS-backed) and the Guided no-SOPS injector
# (.guided_passwords.*). Read precedence + the SOPS-activation gate live here,
# the schema's owner, not re-encoded as raw jq at every consumer.

# install_state_credential_path <state> host
# install_state_credential_path <state> user <name>
# Echoes the decrypted-secret file path for a credential role, applying the
# precedence: SOPS .secrets.* first, then the Guided no-SOPS
# .guided_passwords.*. Empty output when neither key is set or <state> is
# absent. Pure: reads <state> only — existence + copy are the caller's job.
install_state_credential_path() {
  local state="$1" role="$2" name="${3:-}"
  [[ -f "$state" ]] || return 0
  # The decrypted-secret path for the role: the SOPS key first, then
  # the Guided no-SOPS one.
  local host_filter='.secrets.host // .guided_passwords.host // empty'
  local user_filter
  # shellcheck disable=SC2016 # $n is a jq variable, not shell
  user_filter='.secrets.users[$n] // .guided_passwords.users[$n] // empty'
  case "$role" in
    host)
      # The host credential's path.
      jq -r "$host_filter" "$state" ;;
    user)
      # The named user credential's path.
      jq -r --arg n "$name" "$user_filter" "$state" ;;
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
  local host_secret user_count
  # The SOPS host secret path, and how many SOPS user secrets there are.
  host_secret="$(jq -r '.secrets.host // ""' "$state" 2>/dev/null)" \
    || return 1
  user_count="$(jq -r '.secrets.users // {} | length' "$state" \
    2>/dev/null)" || return 1
  [[ -n "$host_secret" ]] || (( user_count > 0 ))
}

# Returns true iff every segment exists (parent contains key) AND the
# final value is not JSON null. Path is dotted: ".a.b.c".
_install_state_has_path() {
  local file="$1" path="$2" value segment
  local -a segments
  value="$(cat "$file")"
  # The path's keys, split at the dots (".a.b" → "", "a", "b").
  IFS=. read -ra segments < <(printf '%s\n' "$path")
  for segment in "${segments[@]}"; do
    [[ -n "$segment" ]] || continue
    # Whether the value so far is an object holding this key.
    printf '%s\n' "$value" \
      | jq -e --arg key "$segment" 'type == "object" and has($key)' \
        >/dev/null 2>&1 || return 1
    # The value under that key.
    value="$(printf '%s\n' "$value" | jq -c --arg key "$segment" '.[$key]')"
  done
  # The final value must not be null.
  printf '%s\n' "$value" | jq -e '. != null' >/dev/null 2>&1
}
