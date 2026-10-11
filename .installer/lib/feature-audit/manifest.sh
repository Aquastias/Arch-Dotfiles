#!/usr/bin/env bash
# =============================================================================
# lib/feature-audit/manifest.sh — Audit Manifest → VM Profiles (ADR 0152)
# =============================================================================
# The manifest names one max-feature base host and the Audit Variants over it.
# A variant is one of:
#   {id}                      the base itself
#   {id, patch: {...}}        base host profile deep-merged with the patch
#                             BEFORE assembly, so derived host_programs
#                             (power daemon, cups, ...) follow the patch
#   {id, host: "<name>"}      a real host installed as-is (own hardware)
#   {id, guided: "<ref>"}     a guided install via the guided test flow
# Every variant installs into the same VM name; one VM at a time.
#
# Public API:
#   feature_audit_manifest_path / feature_audit_manifest_json
#   feature_audit_variant_ids                    → ids in manifest order
#   feature_audit_variant_json <id>              → the variant object
#   feature_audit_variant_vm_profile <id>        → VM Profile JSON (vm.sh input)
#   feature_audit_variant_config <id>            → the resolved Effective Config
#   feature_audit_validate_config <config-json>
#       → 0 iff validation_check_install_context passes
#
# Used by: tools/feature-audit.sh, lib/feature-audit/{check,live-run}.sh.
# =============================================================================

# committed audit data (manifest, Known Noise), INSTALLER_DIR-relative
FA_DATA=tests/vm/feature-audit

feature_audit_manifest_path() {
  local def="$INSTALLER_DIR/$FA_DATA/manifest.jsonc"
  printf '%s\n' "${FEATURE_AUDIT_MANIFEST:-$def}"
}

feature_audit_manifest_json() { jsonc_strip "$(feature_audit_manifest_path)" \
  | jq -c .; }

feature_audit_variant_ids() { feature_audit_manifest_json \
  | jq -r '.variants[].id'; }

feature_audit_variant_json() {
  feature_audit_manifest_json \
    | jq -ce --arg id "$1" '.variants[] | select(.id == $id)'
}

# The phases a variant may declare (install + boot1 always run). Order is
# the run order.
FA_VARIANT_PHASES_ALL="sessions probes keybinds timers boot2 upgrade power"

# feature_audit_variant_phases <id> — the variant's Variant Phases (manifest
# `phases`), space-separated; every phase when it declares none.
feature_audit_variant_phases() {
  local variant
  variant="$(feature_audit_variant_json "$1")" || return 1
  jq -r --arg all "$FA_VARIANT_PHASES_ALL" \
    '(.phases // ($all | split(" "))) | join(" ")' <<<"$variant"
}

# feature_audit_variant_host_core <id> — "true" unless the variant's Host
# Profile sets packages.inherit false (a pure host gets no Host Core packages).
# The probes read it as the Host Core gate (Probe Gate).
feature_audit_variant_host_core() {
  local manifest variant host profile_file
  manifest="$(feature_audit_manifest_json)"
  variant="$(feature_audit_variant_json "$1")" || return 1
  host="$(jq -r --argjson v "$variant" '$v.host // .base.host' <<<"$manifest")"
  [[ "$(type -t profile_loader_directory)" == function ]] || {
    # shellcheck source=../config/profile-loader.sh
    source "$INSTALLER_DIR/lib/config/profile-loader.sh"
  }
  profile_file="$(profile_loader_directory hosts "$host")/profile.jsonc"
  jsonc_strip "$profile_file" | jq -r '.packages.inherit != false'
}

# feature_audit_variant_vm_profile <id> — the VM Profile vm.sh provisions. The
# base and real hosts go through host_profile (the real Profile Loader); a
# patched variant carries its resolved config inline.
feature_audit_variant_vm_profile() {
  local id="$1" manifest variant
  manifest="$(feature_audit_manifest_json)"
  variant="$(feature_audit_variant_json "$id")" \
    || { echo "feature-audit: unknown variant '$id'" >&2; return 1; }
  local base
  base="$(jq -c --argjson v "$variant" '
    { name: .vm_name,
      hardware: ($v.hardware // .base.hardware),
      fixtures: (if $v.host then ($v.fixtures // [])
                 else .base.fixtures // [] end) }' <<<"$manifest")"
  if jq -e '.patch' <<<"$variant" >/dev/null; then
    local config; config="$(feature_audit_variant_config "$id")" || return 1
    jq -c --argjson c "$config" '. + {install: $c}' <<<"$base"
  elif jq -e '.host' <<<"$variant" >/dev/null; then
    jq -c --arg h "$(jq -r .host <<<"$variant")" \
      '. + {host_profile: $h, layout: {mode: "single"}}' <<<"$base"
  else
    jq -c --arg h "$(jq -r .base.host <<<"$manifest")" \
      '. + {host_profile: $h}' \
      <<<"$base"
  fi
}

# feature_audit_variant_config <id> — the Effective Config the variant installs,
# resolved host-side exactly as vm.sh would (a patch is applied to the loaded
# base host profile inside the loader seam).
feature_audit_variant_config() {
  local id="$1" manifest variant host patch profile
  manifest="$(feature_audit_manifest_json)"
  variant="$(feature_audit_variant_json "$id")" \
    || { echo "feature-audit: unknown variant '$id'" >&2; return 1; }
  host="$(jq -r '.base.host' <<<"$manifest")"
  patch="$(jq -c '.patch // empty' <<<"$variant")"
  if [[ -n "$patch" ]]; then
    profile="$(jq -c --arg h "$host" '
      { name: .vm_name, hardware: .base.hardware, host_profile: $h }' \
      <<<"$manifest")"
  else
    local vm_profile; vm_profile="$(feature_audit_variant_vm_profile "$id")" \
      || return 1
    profile="$vm_profile"
  fi
  (
    # shellcheck source=../../vm/lib/profile.sh
    source "$INSTALLER_DIR/vm/lib/profile.sh"
    if [[ -n "$patch" ]]; then
      eval "_manifest_original_$(declare -f profile_loader_load)"
      profile_loader_load() { \
         # readability-ok: patches the loader in a subshell
        if [[ "$1" == "$host" ]]; then
          _manifest_original_profile_loader_load "$1" \
            | jq -c --argjson p "$patch" '. * $p'
        else _manifest_original_profile_loader_load "$1"; fi
      }
    fi
    profile_resolve_config "$profile"
  )
}

# feature_audit_validate_config <cfg-json> — run the installer's own
# validation_check_install_context over an Effective Config (block-device probe
# stubbed: disks are a VM concern), as the Combination Matrix Tier 1 does.
feature_audit_validate_config() {
  local config="$1" config_file
  config_file="$(mktemp)"
  printf '%s\n' "$config" > "$config_file"
  (
    export CONFIG_FILE="$config_file" SCRIPT_DIR="$INSTALLER_DIR"
    local module
    for module in lib/common.sh lib/config/categorized-list.sh \
      lib/config/post-install.sh lib/config/install-config.sh \
      lib/config/lifecycle.sh lib/config/program-registry.sh \
      lib/config/profile-loader.sh \
      lib/layout/dispatch.sh lib/packages/package-list.sh \
      lib/profiles/runner.sh lib/config/validation.sh; do
      # shellcheck source=/dev/null
      source "$INSTALLER_DIR/$module"
    done
    lifecycle_load_config >/dev/null 2>&1
    lifecycle_detect_mode >/dev/null 2>&1
    # shellcheck source=/dev/null
    source "$(root_adapter_source "$INSTALLER_DIR" \
      "$(install_config_filesystem)" "$INSTALL_MODE")"
    # shellcheck disable=SC2329 # called by validation_check_install_context
    layout_disk_exists() { return 0; }  # readability-ok: stubbed in a subshell
    validation_check_install_context
  ) >"$config_file.log" 2>&1
  local rc=$?
  ((rc == 0)) || awk '{ gsub(/\033\[[0-9;]*m/, ""); print }' \
    "$config_file.log" \
    | grep -E 'ERROR|WARN' >&2
  rm -f "$config_file" "$config_file.log"
  return "$rc"
}
