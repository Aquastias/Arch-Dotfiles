#!/usr/bin/env bash
# =============================================================================
# tests/audit.sh — Static installer audit
# =============================================================================
# Checks the module graph for issues that would cause a live install to fail
# or silently misbehave. No disk writes; safe on any host.
#
# Checks:
#   1.  Host-side lib modules present
#   2.  Staged file manifest  (chroot_configure_system copies)
#   3.  Chroot source chain   (extras → extras-common → common → jsonc/globals)
#   4.  lib/chroot/ scripts present  (staged as /root/lib-chroot/)
#   5.  jsonc.sh function definitions
#   6.  Bootloader scripts
#   7.  STAGED_RUNTIME_FILES manifest  (profiles.sh)
#   8.  Program registry — install.sh exists + system flag correct
#   9.  Extras JSON files — valid JSONC
#  10.  Host config cross-refs — referenced users exist
#  11.  User config cross-refs — referenced programs exist + correct flag
#  12.  Program install scripts — no local commons-helper redefinitions
#  13.  No _fixture/ directories under .installer/programs/
#  14.  Package existence — packages.repo in official repos, packages.aur in AUR
#       (offline via pacman/AUR RPC; SKIPs when tooling/network unavailable)
#
# Usage: ./tests/audit.sh
# Exit:  0 = all pass, 1 = one or more failures  (SKIPs never fail the run)
# =============================================================================

set -euo pipefail

script_path="${BASH_SOURCE[0]}"
[[ "$script_path" == */* ]] || script_path="./$script_path"
HERE="$(cd "${script_path%/*}" && pwd)"
OS="$(cd "$HERE/.." && pwd)"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'
BOLD='\033[1m'; NC='\033[0m'

_pass=0; _fail=0; _nskip=0

_pass() { echo -e "  ${GREEN}PASS${NC}  $*"; : $(( _pass++ )); }
_fail() { echo -e "  ${RED}FAIL${NC}  $*"; : $(( _fail++ )); }
_skip() { echo -e "  ${YELLOW}SKIP${NC}  $*"; : $(( _nskip++ )); }
_section() { echo -e "\n${BOLD}── $* ──${NC}"; }

_file() {
  local file_path="$1" label="${2:-$1}"
  if [[ -e "$file_path" ]]; then _pass "$label"; else _fail "$label  (not found)"; fi
}

_function_in() {
  local function_name="$1" file="$2"
  if grep -qE "^${function_name}[[:space:]]*\(\)" "$file" 2>/dev/null; then
    _pass "${function_name}() defined in ${file##*/}"
  else
    _fail "${function_name}() missing from ${file##*/}"
  fi
}

_jsonc_valid() {
  local file_path="$1" label="$2"
  if _strip "$file_path" | jq empty 2>/dev/null; then
    _pass "$label — valid JSON"
  else
    _fail "$label — invalid JSON"
  fi
}

# Strip JSONC comments → plain JSON on stdout
_strip() {
  awk '{ sub(/[[:space:]]*\/\/[^"]*$/, "") } !/^[[:space:]]*\/\// { print }' \
    "$1"
}

# =============================================================================
echo -e "\n${BOLD}Installer static audit${NC}  (INSTALLER_DIR: ${OS})"

# =============================================================================
_section "1. Host-side lib modules"
# =============================================================================
for file_path in lib/common.sh lib/jsonc.sh lib/globals.sh \
          lib/config/lifecycle.sh lib/config/program-registry.sh \
          lib/config/environment.sh lib/config/validation.sh \
          lib/packages/package-list.sh lib/chroot.sh lib/profiles/runner.sh \
          lib/finalize.sh \
          lib/zfs/pools.sh lib/layout/zfs/single.sh lib/layout/zfs/multi.sh; do
  _file "${OS}/${file_path}" "${file_path}"
done

# =============================================================================
_section "2. Staged file manifest  (chroot_configure_system → /root/)"
# =============================================================================
# Files explicitly copied in lib/chroot.sh::chroot_configure_system():
#   lib/common.sh   → /root/lib/common.sh
#   lib/jsonc.sh    → /root/lib/jsonc.sh
#   lib/globals.sh  → /root/lib/globals.sh
#   lib/chroot/extras-common.sh → /root/lib/chroot/extras-common.sh
# (lib/chroot/* is also cp -r to /root/lib-chroot/ — covered in section 4)
for file_path in lib/common.sh lib/jsonc.sh lib/globals.sh \
  lib/chroot/extras-common.sh; do
  _file "${OS}/${file_path}" "${file_path}  (staged → /root/${file_path})"
done

# Verify the cp lines actually exist in chroot.sh so the manifest stays in sync
for needle in \
  'lib/common.sh' \
  'lib/jsonc.sh' \
  'lib/globals.sh' \
  'lib/chroot/extras-common.sh'; do
  if grep -q "$needle" "${OS}/lib/chroot.sh"; then
    _pass "chroot.sh stages  ${needle}"
  else
    _fail "chroot.sh does not stage  ${needle}  — manifest out of sync"
  fi
done

# =============================================================================
_section "3. Chroot source chain  (extras scripts running at /root/)"
# =============================================================================
# Each extras script is run from its chroot path, e.g.:
#   /root/extras/desktop/kde/kde.sh
# It sources: ../../../lib/chroot/extras-common.sh
#   → resolves to /root/lib/chroot/extras-common.sh  (staged in §2)
# extras-common.sh sources ../common.sh → /root/lib/common.sh  (staged in §2)
# common.sh sources jsonc.sh and globals.sh relative to itself →
# /root/lib/{jsonc,globals}.sh

# shellcheck disable=SC2043  # kde is the only extras-common DE today; loop eases adds
for desktop in kde; do
  script="${OS}/extras/desktop/${desktop}/${desktop}.sh"
  if [[ ! -f "$script" ]]; then
    _fail "extras/desktop/${desktop}/${desktop}.sh  (missing)"
    continue
  fi
  # Must source the extras-common.sh path that resolves to
  # /root/lib/chroot/extras-common.sh
  if grep -q 'lib/chroot/extras-common\.sh' "$script"; then
    _pass "extras/${desktop}: sources lib/chroot/extras-common.sh"
  else
    _fail "extras/${desktop}: does not source extras-common.sh via lib/chroot/ path"
  fi
  # Must NOT call jsonc() or other helpers before the source line
  src_line=$(awk '/extras-common\.sh/ { print NR; exit }' "$script")
  if grep -nE '\bjsonc[[:space:](]' "$script" 2>/dev/null \
      | grep -v '\.jsonc' \
      | awk -F: '$1 < '"${src_line:-999}"' {found=1} END{exit !found}'; \
      then
    _fail "extras/${desktop}: calls jsonc() before sourcing" \
          "extras-common.sh (line ${src_line})"
  else
    _pass "extras/${desktop}: no jsonc() call before source"
  fi
done

# extras-common.sh must source ../common.sh (the _EC_COMMON path)
if grep -q '_EC_COMMON\|\.\.\/common\.sh' \
    "${OS}/lib/chroot/extras-common.sh" 2>/dev/null; then
  _pass "extras-common.sh: sources ../common.sh"
else
  _fail "extras-common.sh: does not source ../common.sh"
fi

# common.sh must source jsonc.sh and globals.sh relative to itself
for dep in jsonc.sh globals.sh; do
  if grep -q "$dep" "${OS}/lib/common.sh" 2>/dev/null; then
    _pass "common.sh: sources ${dep}"
  else
    _fail "common.sh: does not source ${dep}  (chain broken)"
  fi
done

# =============================================================================
_section "4. lib/chroot/ scripts  (staged → /root/lib-chroot/)"
# =============================================================================
for file_path in configure.sh extras.sh identity.sh initcpio.sh \
          bootloader-systemd-boot.sh bootloader-grub.sh \
          create-user.sh password.sh extras-common.sh; do
  _file "${OS}/lib/chroot/${file_path}" "lib/chroot/${file_path}"
done

# configure.sh must source install-state.sh (staged from lib/install-state.sh)
if grep -qE 'source.*install-state\.sh' \
    "${OS}/lib/chroot/configure.sh" 2>/dev/null; then
  _pass "configure.sh: sources install-state.sh"
else
  _fail "configure.sh: does not source install-state.sh"
fi

# extras.sh does NOT source install-state.sh: it is invoked by configure.sh
# (bash /root/lib-chroot/extras.sh) after install_state_load has exported the
# state, so extras.sh reads the inherited DISPLAY_MANAGER / ENVIRONMENT_DESKTOP.
# Assert it consumes that inherited state rather than re-loading it.
if grep -qE 'DISPLAY_MANAGER|ENVIRONMENT_DESKTOP' \
    "${OS}/lib/chroot/extras.sh" 2>/dev/null; then
  _pass "extras.sh: reads install-state via inherited env (from configure.sh)"
else
  _fail "extras.sh: does not read the inherited install-state env"
fi

# =============================================================================
_section "5. jsonc.sh function definitions"
# =============================================================================
for function_name in jsonc jsonc_strip jsonc_read jsonc_read_optional; do
  _function_in "$function_name" "${OS}/lib/jsonc.sh"
done

# =============================================================================
_section "6. Bootloader scripts"
# =============================================================================
for bootloader in systemd-boot grub; do
  _file "${OS}/lib/chroot/bootloader-${bootloader}.sh" "lib/chroot/bootloader-${bootloader}.sh"
done

# =============================================================================
_section "7. STAGED_RUNTIME_FILES  (profiles.sh → /var/tmp/.installer-runtime/)"
# =============================================================================
while IFS= read -r entry; do
  _file "${OS}/${entry}" "_STAGED_RUNTIME_FILES: ${entry}"
done < <(
  awk '/_STAGED_RUNTIME_FILES=\(/, /^\)/ {
    if (!/"/) next
    sub(/"[^"]*$/, ""); sub(/.*"/, ""); print
  }' "${OS}/lib/profiles/runner.sh"
)

# =============================================================================
_section "8. Program registry"
# =============================================================================
# Build name → path map from all program config.jsonc files.
declare -A _program_directories=()
while IFS= read -r cfg; do
  name="${cfg%/*}"; name="${name##*/}"
  _program_directories["$name"]="${cfg%/*}"
done < <(find "${OS}/programs" -name "config.jsonc")

_check_program() {
  local name="$1" want_kind="$2" context="$3"
  if [[ ! -v _program_directories["$name"] ]]; then
    _fail "${context}: program '${name}' not found in programs/"
    return
  fi
  local program_directory="${_program_directories[$name]}"
  local got_kind
  got_kind="$(awk '/"kind"/ {
      if (match($0, /"kind"[[:space:]]*:[[:space:]]*"(host|user)"/)) {
        $0 = substr($0, RSTART, RLENGTH); sub(/^"kind"[^"]*"/, ""); sub(/"$/, "")
      }
      print; exit
    }' "${program_directory}/config.jsonc" 2>/dev/null)"
  if [[ "$got_kind" == "$want_kind" ]]; then
    _pass "${context}: program '${name}' (kind=${got_kind})"
  else
    _fail "${context}: program '${name}' has" \
          "kind=${got_kind}, expected ${want_kind}"
  fi
  if [[ ! -f "${program_directory}/install.sh" ]]; then
    _fail "${context}: program '${name}' missing install.sh"
  fi
}

# Host configs → host_programs must have kind:host
while IFS= read -r cfg; do
  host="${cfg%/*}"; host="${host##*/}"
  [[ "$host" == "core" ]] && continue
  while IFS= read -r prog; do
    _check_program "$prog" "host" "host:${host}"
  done < <(_strip "$cfg" | jq -r '.host_programs[]?' 2>/dev/null)
done < <(find "${OS}/hosts" -name "profile.jsonc")

# User configs → programs must have kind:user
while IFS= read -r cfg; do
  user="${cfg%/*}"; user="${user##*/}"
  [[ "$user" == "core" ]] && continue
  while IFS= read -r prog; do
    _check_program "$prog" "user" "user:${user}"
  done < <(_strip "$cfg" | jq -r '.programs[]?' 2>/dev/null)
done < <(find "${OS}/users" -name "profile.jsonc")

# =============================================================================
_section "9. Extras JSON files"
# =============================================================================
# shellcheck disable=SC2043  # kde is the only extras JSON DE today; loop eases adds
for desktop in kde; do
  json="${OS}/extras/desktop/${desktop}/install-${desktop}.jsonc"
  if [[ -f "$json" ]]; then
    _jsonc_valid "$json" "extras/desktop/${desktop}/install-${desktop}.jsonc"
  else
    _fail "extras/desktop/${desktop}/install-${desktop}.jsonc  (not found)"
  fi
done

# =============================================================================
_section "10. Host config cross-refs  (referenced users exist)"
# =============================================================================
while IFS= read -r cfg; do
  host="${cfg%/*}"; host="${host##*/}"
  [[ "$host" == "core" ]] && continue
  while IFS= read -r user; do
    # Same lookup as the Profile Loader: users/<name>, else users/vm/<name>.
    if [[ -d "${OS}/users/${user}" || -d "${OS}/users/vm/${user}" ]]; then
      _pass "host:${host} → user '${user}' directory exists"
    else
      _fail "host:${host} → user '${user}' not found in users/ or users/vm/"
    fi
  done < <(_strip "$cfg" | jq -r '.users[]?' 2>/dev/null)
done < <(find "${OS}/hosts" -name "profile.jsonc")

# =============================================================================
_section "11. User config cross-refs  (referenced programs consistent)"
# =============================================================================
while IFS= read -r cfg; do
  user="${cfg%/*}"; user="${user##*/}"
  [[ "$user" == "core" ]] && continue
  while IFS= read -r prog; do
    if [[ -v _program_directories["$prog"] ]]; then
      _pass "user:${user} → program '${prog}' exists"
    else
      _fail "user:${user} → program '${prog}' not found in programs/"
    fi
  done < <(_strip "$cfg" | jq -r '.programs[]?' 2>/dev/null)
done < <(find "${OS}/users" -name "profile.jsonc")

# =============================================================================
_section "12. Program install scripts must not redefine commons helpers"
# =============================================================================
# Per ADR 0011, programs/*/install.sh sources Shell Stdlib via the Program
# Runner. Local redefinitions of commons-named helpers silently shadow the
# stdlib version and split the source of truth.
_commons_fns=(print_status check_root send_user_notification command_exists \
              package_installed)
_dups_found=0
while IFS= read -r script; do
  rel="${script#"${OS}"/}"
  for function_name in "${_commons_fns[@]}"; do
    if grep -qE "^[[:space:]]*(function[[:space:]]+)?${function_name}[[:space:]]*\(" \
        "$script" 2>/dev/null; then
      _fail "${rel}: redefines commons helper '${function_name}()' (see ADR 0011)"
      _dups_found=$((_dups_found + 1))
    fi
  done
done < <(find "${OS}/programs" -name install.sh)
if (( _dups_found == 0 )); then
  _pass "no programs/*/install.sh redefines a commons helper"
fi

# =============================================================================
_section "13. No _fixture/ directories under .installer/programs/"
# =============================================================================
# Per ADR 0013 + config-generator-finalization slice 04, the production
# programs/ tree must ship no fixture program. Test fixtures live under
# .installer/tests/fixtures/programs/ and are reached via PROGRAMS_ROOT
# overrides.
_strays=0
while IFS= read -r d; do
  rel="${d#"${OS}"/}"
  _fail "${rel}: _fixture/ directory must not live under programs/"
  _strays=$((_strays + 1))
done < <(find "${OS}/programs" -type d -name "_fixture")
if (( _strays == 0 )); then
  _pass "no _fixture/ directories under programs/"
fi

# =============================================================================
_section "14. Package existence  (repo → official/archzfs, aur → AUR/official)"
# =============================================================================
# Guards the bug class where a config lists a package that no longer exists in
# any installable source (renamed / moved repo↔AUR / dropped), which makes
# pacstrap or paru fail mid-install. Repo packages resolve offline via
# `pacman -Sp` (which also follows provides); AUR packages via the AUR RPC.
# Both degrade to SKIP when pacman/network is unavailable, so the audit stays
# safe on any host.

# archzfs packages live in the [archzfs] repo — added by the live ISO at
# install time, but a dev host may not have it configured. Allowlist them so
# they don't false-fail the offline resolver.
_ARCHZFS_OK=" zfs-dkms zfs-utils zfs-linux zfs-linux-headers zfs-linux-lts \
zfs-linux-lts-headers "

# Collect config-declared packages (the user-editable surface).
_repo_pkgs="$(
  while IFS= read -r cfg; do
    _strip "$cfg" | jq -r '(.packages.repo // {}) | [.. | strings] | .[]' \
      2>/dev/null
  done < <(find "${OS}/hosts" "${OS}/users" -name profile.jsonc) | sort -u
)"
_aur_pkgs="$(
  while IFS= read -r cfg; do
    _strip "$cfg" | jq -r '(.packages.aur // {}) | [.. | strings] | .[]' \
      2>/dev/null
  done < <(find "${OS}/hosts" "${OS}/users" -name profile.jsonc) | sort -u
)"

# Resolve AUR membership once (used by both checks). Empty if curl/net absent.
_aur_found=""
if command -v curl >/dev/null 2>&1; then
  _aur_args=""
  while IFS= read -r p; do
    [[ -n "$p" ]] && _aur_args+="&arg[]=${p}"
  done <<<"${_aur_pkgs}"$'\n'"${_repo_pkgs}"
  _aur_found="$(curl -fsS --max-time 20 \
    "https://aur.archlinux.org/rpc/v5/info?${_aur_args#&}" 2>/dev/null \
    | jq -r '.results[]?.Name' 2>/dev/null | sort -u || true)"
fi
_in_aur() { [[ -n "$_aur_found" ]] && grep -qxF "$1" <<<"$_aur_found"; }

# ── Repo packages → must resolve in the official repos (or archzfs) ──────────
if command -v pacman >/dev/null 2>&1 \
   && pacman -Sp --print-format '%n' bash >/dev/null 2>&1; then
  _avail="$(pacman -Slq 2>/dev/null | sort -u)"
  _repo_bad=0
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    grep -qxF "$p" <<<"$_avail" && continue              # direct repo match
    [[ "$_ARCHZFS_OK" == *" $p "* ]] && continue          # archzfs allowlist
    pacman -Sp --print-format '%n' "$p" >/dev/null 2>&1 && continue  # provides
    if _in_aur "$p"; then
      _fail "packages.repo: '${p}' exists only in AUR — move to packages.aur"
    else
      _fail "packages.repo: '${p}' not found in any official repo or AUR"
    fi
    _repo_bad=$(( _repo_bad + 1 ))
  done <<<"$_repo_pkgs"
  (( _repo_bad == 0 )) \
    && _pass "all packages.repo entries resolve (official repos / archzfs)"
else
  _skip "packages.repo existence — pacman or synced DBs unavailable"
fi

# ── AUR packages → must exist in the AUR (or be an official repo package) ────
if command -v curl >/dev/null 2>&1 \
   && curl -fsS --max-time 8 \
        "https://aur.archlinux.org/rpc/v5/info?arg[]=paru" >/dev/null 2>&1; then
  _have_pacman=0
  command -v pacman >/dev/null 2>&1 \
    && pacman -Sp --print-format '%n' bash >/dev/null 2>&1 && _have_pacman=1
  _aur_bad=0
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    _in_aur "$p" && continue                               # in AUR
    # paru also installs plain repo packages — accept those too.
    (( _have_pacman )) \
      && pacman -Sp --print-format '%n' "$p" >/dev/null 2>&1 && continue
    _fail "packages.aur: '${p}' not found in AUR (or official repos)"
    _aur_bad=$(( _aur_bad + 1 ))
  done <<<"$_aur_pkgs"
  (( _aur_bad == 0 )) && _pass "all packages.aur entries exist in AUR/official"
else
  _skip "packages.aur existence — curl or AUR RPC unavailable"
fi

# =============================================================================
echo ""
_skipnote=""
(( _nskip > 0 )) && _skipnote="  ${YELLOW}${_nskip} skipped${NC}"
if ((_fail == 0)); then
  echo -e "${BOLD}${GREEN}All ${_pass} checks passed.${NC}${_skipnote}"
else
  echo -e "${BOLD}${GREEN}${_pass} passed${NC}  ${RED}${_fail} failed${NC}${_skipnote}"
  echo -e "${RED}Audit found failures — fix before running the installer.${NC}"
  exit 1
fi
