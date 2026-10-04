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
#   fa_manifest_path / fa_manifest_json
#   fa_variant_ids                    → ids in manifest order
#   fa_variant_json <id>              → the variant object
#   fa_variant_vm_profile <id>        → VM Profile JSON (vm.sh input)
#   fa_variant_config <id>            → the resolved Effective Config
#   fa_validate_config <cfg-json>     → 0 iff validate_install_context passes
# =============================================================================

# committed audit data (manifest, Known Noise), INSTALLER_DIR-relative
FA_DATA=tests/vm/feature-audit

fa_manifest_path() {
  local def="$INSTALLER_DIR/$FA_DATA/manifest.jsonc"
  printf '%s\n' "${FEATURE_AUDIT_MANIFEST:-$def}"
}

fa_manifest_json() { jsonc_strip "$(fa_manifest_path)" | jq -c .; }

fa_variant_ids() { fa_manifest_json | jq -r '.variants[].id'; }

fa_variant_json() {
  fa_manifest_json | jq -ce --arg id "$1" '.variants[] | select(.id == $id)'
}

# The phases a variant may declare (install + boot1 always run). Order is
# the run order.
FA_VARIANT_PHASES_ALL="sessions probes keybinds timers boot2 upgrade power"

# fa_variant_phases <id> — the variant's Variant Phases (manifest `phases`),
# space-separated; every phase when it declares none.
fa_variant_phases() {
  local v
  v="$(fa_variant_json "$1")" || return 1
  jq -r --arg all "$FA_VARIANT_PHASES_ALL" \
    '(.phases // ($all | split(" "))) | join(" ")' <<<"$v"
}

# fa_variant_host_core <id> — "true" unless the variant's Host Profile sets
# packages.inherit false (a pure host gets no Host Core packages). The probes
# read it as the Host Core gate (Probe Gate).
fa_variant_host_core() {
  local m v h f
  m="$(fa_manifest_json)"
  v="$(fa_variant_json "$1")" || return 1
  h="$(jq -r --argjson v "$v" '$v.host // .base.host' <<<"$m")"
  [[ "$(type -t profile_dir)" == function ]] || {
    # shellcheck source=../config/profile.sh
    source "$INSTALLER_DIR/lib/config/profile.sh"
  }
  f="$(profile_dir hosts "$h")/profile.jsonc"
  jsonc_strip "$f" | jq -r '.packages.inherit != false'
}

# fa_variant_vm_profile <id> — the VM Profile vm.sh provisions. The base and
# real hosts go through host_profile (the real Profile Loader); a patched
# variant carries its resolved config inline.
fa_variant_vm_profile() {
  local id="$1" m v
  m="$(fa_manifest_json)"
  v="$(fa_variant_json "$id")" \
    || { echo "feature-audit: unknown variant '$id'" >&2; return 1; }
  local base
  base="$(jq -c --argjson v "$v" '
    { name: .vm_name,
      hardware: ($v.hardware // .base.hardware),
      fixtures: (if $v.host then ($v.fixtures // [])
                 else .base.fixtures // [] end) }' <<<"$m")"
  if jq -e '.patch' <<<"$v" >/dev/null; then
    local cfg; cfg="$(fa_variant_config "$id")" || return 1
    jq -c --argjson c "$cfg" '. + {install: $c}' <<<"$base"
  elif jq -e '.host' <<<"$v" >/dev/null; then
    jq -c --arg h "$(jq -r .host <<<"$v")" \
      '. + {host_profile: $h, layout: {mode: "single"}}' <<<"$base"
  else
    jq -c --arg h "$(jq -r .base.host <<<"$m")" '. + {host_profile: $h}' \
      <<<"$base"
  fi
}

# fa_variant_config <id> — the Effective Config the variant installs, resolved
# host-side exactly as vm.sh would (a patch is applied to the loaded base host
# profile inside the loader seam).
fa_variant_config() {
  local id="$1" m v host patch prof
  m="$(fa_manifest_json)"
  v="$(fa_variant_json "$id")" \
    || { echo "feature-audit: unknown variant '$id'" >&2; return 1; }
  host="$(jq -r '.base.host' <<<"$m")"
  patch="$(jq -c '.patch // empty' <<<"$v")"
  if [[ -n "$patch" ]]; then
    prof="$(jq -c --arg h "$host" '
      { name: .vm_name, hardware: .base.hardware, host_profile: $h }' <<<"$m")"
  else
    local tmp; tmp="$(fa_variant_vm_profile "$id")" || return 1
    prof="$tmp"
  fi
  (
    # shellcheck source=../../vm/lib/profile.sh
    source "$INSTALLER_DIR/vm/lib/profile.sh"
    if [[ -n "$patch" ]]; then
      eval "_fa_orig_$(declare -f load_profile)"
      load_profile() {
        if [[ "$1" == "$host" ]]; then
          _fa_orig_load_profile "$1" | jq -c --argjson p "$patch" '. * $p'
        else _fa_orig_load_profile "$1"; fi
      }
    fi
    profile_resolve_config "$prof"
  )
}

# fa_validate_config <cfg-json> — run the installer's own
# validate_install_context over an Effective Config (block-device probe
# stubbed: disks are a VM concern), as the Combination Matrix Tier 1 does.
fa_validate_config() {
  local cfg="$1" f
  f="$(mktemp)"
  printf '%s\n' "$cfg" > "$f"
  (
    export CONFIG_FILE="$f" SCRIPT_DIR="$INSTALLER_DIR"
    local m
    for m in lib/common.sh lib/config/categorized-list.sh \
      lib/config/post-install.sh lib/config/accessors.sh \
      lib/config/lifecycle.sh lib/config/layers.sh lib/config/profile.sh \
      lib/layout/dispatch.sh lib/packages/list.sh lib/profiles/runner.sh \
      lib/config/validation.sh; do
      # shellcheck source=/dev/null
      source "$INSTALLER_DIR/$m"
    done
    load_config >/dev/null 2>&1
    detect_mode >/dev/null 2>&1
    # shellcheck source=/dev/null
    source "$(root_adapter_source "$INSTALLER_DIR" \
      "$(install_config_filesystem)" "$INSTALL_MODE")"
    # shellcheck disable=SC2329 # called by validate_install_context
    _layout_disk_exists() { return 0; }
    validate_install_context
  ) >"$f.log" 2>&1
  local rc=$?
  ((rc == 0)) || sed 's/\x1b\[[0-9;]*m//g' "$f.log" | grep -E 'ERROR|WARN' >&2
  rm -f "$f" "$f.log"
  return "$rc"
}
