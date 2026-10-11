#!/usr/bin/env bash
# =============================================================================
# lib/guided/controller.sh — Guided Installer persistent-fzf controller (ADR
# 0042)
# =============================================================================
# Invoked by the single persistent fzf's reload/transform binds as SUBPROCESSES.
# It reads the navigation + Config-State files (paths in GUIDED_NAV_FILE /
# GUIDED_STATE_FILE / GUIDED_BASELINE_FILE), mutates them, and either prints the
# current screen's item list (guided_controller_list, for `reload`) or a single
# navigation DIRECTIVE the launcher maps to fzf actions (guided_controller_enter
# / guided_controller_back). No fzf is needed to drive it — state files in,
# files + a directive out — so the dispatch is unit-testable without a tty.
#
# Screens (navigation.sh): top, category, values (enum picks, toggles, list
# editors, the Disk-layout preset picker), text (typed into fzf's query line).
# Everything commits in place, so the menu never leaves fzf; ^Z/^Y/^R drive
# undo/redo/reset over a snapshot history.
#
# Directives (one per guided_controller_enter / guided_controller_back call):
#   render             re-list + re-prompt + re-header the current screen
#   terminal <action>  exit with proceed|save|export
#                       (launcher → result + accept)
#   abort              cancel the whole menu             (launcher → abort)
#   noop               do nothing
# =============================================================================

# INSTALL_DEFAULT_ENC_PASSPHRASE (ADR 0059) — the 8-char passphrase default.
# shellcheck source=../globals.sh
[[ -n "${INSTALL_DEFAULT_ENC_PASSPHRASE:-}" ]] \
  || source "${BASH_SOURCE[0]%/*}/../globals.sh"
# shellcheck source=../config/config-state.sh
declare -F config_state_get >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../config/config-state.sh"
# shellcheck source=../config/config-store.sh
declare -F config_store_state >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../config/config-store.sh"
# shellcheck source=../config/navigation.sh
declare -F navigation_new >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../config/navigation.sh"
# shellcheck source=../config/edit.sh
declare -F edit_set_bool >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../config/edit.sh"
# shellcheck source=../config/menu.sh
declare -F menu_categories >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../config/menu.sh"
# shellcheck source=rows.sh
declare -F guided_row_inert >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/rows.sh"

declare -F esp_budget_fits_size >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../boot/esp-budget.sh"
# shellcheck source=../config/manual-partition.sh
declare -F manual_partition_kind_active >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../config/manual-partition.sh"
# shellcheck source=../config/skeleton.sh
declare -F skeleton_preset >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../config/skeleton.sh"
# shellcheck source=../picker.sh
declare -F picker_enum_disks >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../picker.sh"
# shellcheck source=../config/history.sh
declare -F history_new >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../config/history.sh"
# shellcheck source=../config/display.sh
declare -F display_label >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../config/display.sh"
# shellcheck source=secrets-file.sh
declare -F guided_secrets_file_has_root >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/secrets-file.sh"
# shellcheck source=../config/profile-loader.sh
declare -F profile_loader_load_user >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../config/profile-loader.sh"
# shellcheck source=../config/printing.sh
declare -F printing_owned_programs >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../config/printing.sh"
# shellcheck source=../config/mirrors.sh
declare -F mirrors_owned_programs >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../config/mirrors.sh"
# shellcheck source=../config/bluetooth.sh
declare -F bluetooth_owned_programs >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../config/bluetooth.sh"
# shellcheck source=../config/power.sh
declare -F power_owned_programs >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../config/power.sh"
# shellcheck source=../config/menu-owned.sh
declare -F menu_owned_programs >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../config/menu-owned.sh"
# shellcheck source=../config/profiles.sh
declare -F profiles_list >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../config/profiles.sh"
# shellcheck source=../config/program-registry.sh
declare -F _program_registry_parse >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../config/program-registry.sh"
# shellcheck source=userforms.sh
declare -F guided_userform_get >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/userforms.sh"
# Curated Persist Defaults, for the Impermanence Editor's read-only count line
# (ADR 0066).
# shellcheck source=../impermanence-common.sh
[[ -n "${CURATED_FILES:-}" ]] \
  || source "${BASH_SOURCE[0]%/*}/../impermanence-common.sh"
# shellcheck source=mask.sh
declare -F guided_mask_apply >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/mask.sh"
# shellcheck source=../packages/package-resolver.sh
declare -F package_resolver_resolve >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../packages/package-resolver.sh"
# shellcheck source=../config/layer-resolver.sh
declare -F layer_resolver_resolve >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../config/layer-resolver.sh"

# _controller_secret_state <root|user|enc> [name] → "(set)" / "(not set)" for
# the in-menu credential rows, read from GUIDED_SECRETS_FILE. Never emits the
# value. With no secrets file wired (non-persistent), everything reads "(not
# set)".
_controller_secret_state() {
  local secrets_file="${GUIDED_SECRETS_FILE:-}"
  if [[ -n "$secrets_file" ]]; then
    case "$1" in
    root) guided_secrets_file_has_root "$secrets_file" \
      && { echo "(set)"; return; } ;;
    enc)  guided_secrets_file_has_encryption  "$secrets_file" \
      && { echo "(set)"; return; } ;;
    *)    guided_secrets_file_has_user "$secrets_file" "$2" \
      && { echo "(set)"; return; } ;;
    esac
  fi
  echo "(not set)"
}

# _controller_secret_tag <root|user|enc> [name] → the ADR-0055 source tag for a
# credential: `custom` (operator typed it into GUIDED_SECRETS_FILE), else
# `from age` (a committed secret will decrypt via the wired age key — .secrets.*
# wins over .guided_passwords.* in the resolver), else the default tag. The
# default is role-dependent (ADR 0059): the disk passphrase reports its 8-char
# default, accounts their 5-char one. Never emits the value. Reads the secrets
# file + effective state.
_controller_secret_tag() {
  local secrets_file="${GUIDED_SECRETS_FILE:-}" role="$1" name="${2:-}"
  if [[ -n "$secrets_file" ]]; then
    case "$role" in
    root) guided_secrets_file_has_root "$secrets_file" \
      && { echo "custom"; return; } ;;
    enc)  guided_secrets_file_has_encryption  "$secrets_file" \
      && { echo "custom"; return; } ;;
    *)
      guided_secrets_file_has_user "$secrets_file" "$name" \
        && { echo "custom"; return; } ;;
    esac
  fi
  [[ -n "$(config_state_get "$(_controller_live_effective)" \
      options.age_key_url)" ]] && { echo "from age"; return; }
  if [[ "$role" == "enc" ]]; then echo "default $INSTALL_DEFAULT_ENC_PASSPHRASE"
  else echo "default 12345"; fi
}

# _controller_password_missing — count of required-but-unset passwords (root +
# each enabled user), from GUIDED_SECRETS_FILE over the effective user list. 0
# when no secrets file is wired (non-persistent contexts), so the top screen
# stays undecorated.
_controller_password_missing() {
  local secrets_file="${GUIDED_SECRETS_FILE:-}"
  [[ -n "$secrets_file" ]] || { printf '0'; return; }
  local users
  users="$(jq -c '.users // []' \
    <<<"$(_controller_live_effective)")"
  guided_secrets_file_missing "$secrets_file" "$users" | grep -c .
}

# _controller_encryption_missing — rc 0 when the encryption passphrase is
# required but unset (ADR 0054): encryption is on AND no passphrase captured.
# Inert (rc 1) when no secrets file is wired or encryption is off — so toggling
# encryption off drops the requirement even though a stored passphrase is
# retained.
_controller_encryption_missing() {
  local secrets_file="${GUIDED_SECRETS_FILE:-}"
  [[ -n "$secrets_file" ]] || return 1
  [[ "$(config_state_get "$(_controller_live_effective)" \
    options.encryption)" == "true" ]] || return 1
  guided_secrets_file_has_encryption "$secrets_file" && return 1
  return 0
}

# _controller_display_values <field> → 0 when <field>'s enum/toggle VALUES are
# human words that should render through the Display Label formatter (desktop,
# gpu, kernel, filesystem, bootloader, firewall). Every other field's values are
# technical (keymap codes, mirror countries, program names), free-text, or
# booleans and are shown verbatim. Labels are always formatted; only VALUES are
# gated by this allowlist.
_controller_display_values() {
  case "$1" in
  environment.desktop | environment.gpu | environment.display_manager \
    | options.kernel | filesystem \
    | options.bootloader | post_install.security.firewall) return 0 ;;
  *) return 1 ;;
  esac
}

# _controller_display_value_string <field> <value-string> → the value formatted
# for display when <field> is value-formattable, else verbatim. Multi-value
# fields render as ", "-joined tokens (menu_render_value), so each token is
# formatted and re-joined; single values are one token.
_controller_display_value_string() {
  local field="$1" value="$2"
  { _controller_display_values "$field" && [[ -n "$value" ]]; } \
    || { printf '%s' "$value"; return; }
  local out="" part
  while [[ "$value" == *", "* ]]; do
    part="${value%%, *}"; value="${value#*, }"
    out+="${out:+, }$(display_label "$part")"
  done
  printf '%s' "${out:+$out, }$(display_label "$value")"
}

# The rule separating the categories from the terminal-action rows on the top
# screen.
_CONTROLLER_DIVIDER="──────────────────────────"

# ── state-file accessors ─────────────────────────────────────────────────────
# Thin delegations to the Config Store (lib/config/config-store.sh), which owns
# the triad session files — so the file IPC lives in one place, not here.
_controller_state()       { config_store_state; }
_controller_navigation()         { config_store_navigation; }
_controller_baseline()    { config_store_baseline; }
_controller_write_state() { config_store_write_state "$1"; }
_controller_write_navigation()   { config_store_write_navigation "$1"; }

# _controller_effective <state> <baseline> — the merged view (override wins).
_controller_effective() { jq -n --argjson b "$2" --argjson o "$1" '$b * $o'; }

# _controller_live_effective — the merged view of the live session files.
_controller_live_effective() {
  _controller_effective "$(_controller_state)" "$(_controller_baseline)"
}

# The controller's parts, in their original order.
# shellcheck source=controller-fields.sh
source "${BASH_SOURCE[0]%/*}/controller-fields.sh"
# shellcheck source=controller-user-fields.sh
source "${BASH_SOURCE[0]%/*}/controller-user-fields.sh"
# shellcheck source=controller-chrome.sh
source "${BASH_SOURCE[0]%/*}/controller-chrome.sh"
# shellcheck source=controller-screen-data.sh
source "${BASH_SOURCE[0]%/*}/controller-screen-data.sh"
# shellcheck source=controller-detail.sh
source "${BASH_SOURCE[0]%/*}/controller-detail.sh"
# shellcheck source=controller-list.sh
source "${BASH_SOURCE[0]%/*}/controller-list.sh"
# shellcheck source=controller-list-editors.sh
source "${BASH_SOURCE[0]%/*}/controller-list-editors.sh"
# shellcheck source=controller-enter-users.sh
source "${BASH_SOURCE[0]%/*}/controller-enter-users.sh"
# shellcheck source=controller-enter-host.sh
source "${BASH_SOURCE[0]%/*}/controller-enter-host.sh"
# shellcheck source=controller-enter-values.sh
source "${BASH_SOURCE[0]%/*}/controller-enter-values.sh"
# shellcheck source=controller-enter-pools.sh
source "${BASH_SOURCE[0]%/*}/controller-enter-pools.sh"
# shellcheck source=controller-history.sh
source "${BASH_SOURCE[0]%/*}/controller-history.sh"
