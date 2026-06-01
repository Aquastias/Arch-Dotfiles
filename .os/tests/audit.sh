#!/usr/bin/env bash
# =============================================================================
# tests/audit.sh — Static installer audit
# =============================================================================
# Checks the module graph for issues that would cause a live install to fail
# or silently misbehave. No disk writes; safe on any host.
#
# Checks:
#   1.  Host-side lib modules present
#   2.  Staged file manifest  (configure_system copies)
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
#  13.  No _fixture/ directories under .os/programs/
#  14.  Package existence — packages.repo in official repos, packages.aur in AUR
#       (offline via pacman/AUR RPC; SKIPs when tooling/network unavailable)
#
# Usage: ./tests/audit.sh
# Exit:  0 = all pass, 1 = one or more failures  (SKIPs never fail the run)
# =============================================================================

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OS="$(cd "$HERE/.." && pwd)"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'
BOLD='\033[1m'; NC='\033[0m'

_pass=0; _fail=0; _nskip=0

_pass() { echo -e "  ${GREEN}PASS${NC}  $*"; : $(( _pass++ )); }
_fail() { echo -e "  ${RED}FAIL${NC}  $*"; : $(( _fail++ )); }
_skip() { echo -e "  ${YELLOW}SKIP${NC}  $*"; : $(( _nskip++ )); }
_section() { echo -e "\n${BOLD}── $* ──${NC}"; }

_file() {
  local f="$1" label="${2:-$1}"
  if [[ -e "$f" ]]; then _pass "$label"; else _fail "$label  (not found)"; fi
}

_fn_in() {
  local fn="$1" file="$2"
  if grep -qE "^${fn}[[:space:]]*\(\)" "$file" 2>/dev/null; then
    _pass "${fn}() defined in $(basename "$file")"
  else
    _fail "${fn}() missing from $(basename "$file")"
  fi
}

_jsonc_valid() {
  local f="$1" label="$2"
  if sed -e 's|[[:space:]]*//[^"]*$||' -e '/^[[:space:]]*\/\//d' "$f" \
       | jq empty 2>/dev/null; then
    _pass "$label — valid JSON"
  else
    _fail "$label — invalid JSON"
  fi
}

# Strip JSONC comments → plain JSON on stdout
_strip() { sed -e 's|[[:space:]]*//[^"]*$||' -e '/^[[:space:]]*\/\//d' "$1"; }

# =============================================================================
echo -e "\n${BOLD}Installer static audit${NC}  (OS_DIR: ${OS})"

# =============================================================================
_section "1. Host-side lib modules"
# =============================================================================
for f in common.sh jsonc.sh globals.sh config.sh configs.sh environment.sh \
          packages.sh chroot.sh profiles.sh validation.sh finalize.sh \
          zfs-pools.sh layout-single.sh layout-multi.sh; do
  _file "${OS}/lib/${f}" "lib/${f}"
done

# =============================================================================
_section "2. Staged file manifest  (configure_system → /root/)"
# =============================================================================
# Files explicitly copied in lib/chroot.sh::configure_system():
#   lib/common.sh   → /root/lib/common.sh
#   lib/jsonc.sh    → /root/lib/jsonc.sh
#   lib/globals.sh  → /root/lib/globals.sh
#   lib/chroot/extras-common.sh → /root/lib/chroot/extras-common.sh
# (lib/chroot/* is also cp -r to /root/lib-chroot/ — covered in section 4)
for f in lib/common.sh lib/jsonc.sh lib/globals.sh \
  lib/chroot/extras-common.sh; do
  _file "${OS}/${f}" "${f}  (staged → /root/${f})"
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

for de in kde hyprland; do
  script="${OS}/extras/desktop/${de}/${de}.sh"
  if [[ ! -f "$script" ]]; then
    _fail "extras/desktop/${de}/${de}.sh  (missing)"
    continue
  fi
  # Must source the extras-common.sh path that resolves to
  # /root/lib/chroot/extras-common.sh
  if grep -q 'lib/chroot/extras-common\.sh' "$script"; then
    _pass "extras/${de}: sources lib/chroot/extras-common.sh"
  else
    _fail "extras/${de}: does not source extras-common.sh via lib/chroot/ path"
  fi
  # Must NOT call jsonc() or other helpers before the source line
  src_line=$(grep -n 'extras-common\.sh' "$script" | head -1 | cut -d: -f1)
  if grep -nE '\bjsonc[[:space:](]' "$script" 2>/dev/null \
      | grep -v '\.jsonc' \
      | awk -F: '$1 < '"${src_line:-999}"' {found=1} END{exit !found}'; \
      then
    _fail "extras/${de}: calls jsonc() before sourcing" \
          "extras-common.sh (line ${src_line})"
  else
    _pass "extras/${de}: no jsonc() call before source"
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
for f in configure.sh extras.sh identity.sh initcpio.sh \
          bootloader-systemd-boot.sh bootloader-grub.sh \
          create-user.sh password.sh extras-common.sh; do
  _file "${OS}/lib/chroot/${f}" "lib/chroot/${f}"
done

# configure.sh must source install-state.sh (staged from lib/install-state.sh)
if grep -qE 'source.*install-state\.sh' \
    "${OS}/lib/chroot/configure.sh" 2>/dev/null; then
  _pass "configure.sh: sources install-state.sh"
else
  _fail "configure.sh: does not source install-state.sh"
fi

# extras.sh must source install-state.sh
if grep -qE 'source.*install-state\.sh' \
    "${OS}/lib/chroot/extras.sh" 2>/dev/null; then
  _pass "extras.sh: sources install-state.sh"
else
  _fail "extras.sh: does not source install-state.sh"
fi

# =============================================================================
_section "5. jsonc.sh function definitions"
# =============================================================================
for fn in jsonc jsonc_strip jsonc_read jsonc_read_opt; do
  _fn_in "$fn" "${OS}/lib/jsonc.sh"
done

# =============================================================================
_section "6. Bootloader scripts"
# =============================================================================
for bl in systemd-boot grub; do
  _file "${OS}/lib/chroot/bootloader-${bl}.sh" "lib/chroot/bootloader-${bl}.sh"
done

# =============================================================================
_section "7. STAGED_RUNTIME_FILES  (profiles.sh → /var/tmp/.os-runtime/)"
# =============================================================================
while IFS= read -r entry; do
  _file "${OS}/${entry}" "_STAGED_RUNTIME_FILES: ${entry}"
done < <(
  sed -n '/_STAGED_RUNTIME_FILES=(/,/^)/p' "${OS}/lib/profiles.sh" \
    | grep '"' | sed 's|.*"\([^"]*\)".*|\1|'
)

# =============================================================================
_section "8. Program registry"
# =============================================================================
# Build name → path map from all program config.jsonc files.
declare -A _prog_dir=()
while IFS= read -r cfg; do
  name="$(basename "$(dirname "$cfg")")"
  _prog_dir["$name"]="$(dirname "$cfg")"
done < <(find "${OS}/programs" -name "config.jsonc")

_check_program() {
  local name="$1" want_system="$2" context="$3"
  if [[ ! -v _prog_dir["$name"] ]]; then
    _fail "${context}: program '${name}' not found in programs/"
    return
  fi
  local dir="${_prog_dir[$name]}"
  local got_system
  got_system="$(grep '"system"' "${dir}/config.jsonc" 2>/dev/null \
                | head -1 \
                | sed 's/.*"system"[[:space:]]*:[[:space:]]*\(true\|false\).*/\1/')"
  if [[ "$got_system" == "$want_system" ]]; then
    _pass "${context}: program '${name}' (system=${got_system})"
  else
    _fail "${context}: program '${name}' has" \
          "system=${got_system}, expected ${want_system}"
  fi
  if [[ ! -f "${dir}/install.sh" ]]; then
    _fail "${context}: program '${name}' missing install.sh"
  fi
}

# Host configs → system_programs must have system:true
while IFS= read -r cfg; do
  host="$(basename "$(dirname "$cfg")")"
  [[ "$host" == "core" ]] && continue
  while IFS= read -r prog; do
    _check_program "$prog" "true" "host:${host}"
  done < <(_strip "$cfg" | jq -r '.system_programs[]?' 2>/dev/null)
done < <(find "${OS}/hosts" -name "config.jsonc")

# User configs → programs must have system:false
while IFS= read -r cfg; do
  user="$(basename "$(dirname "$cfg")")"
  [[ "$user" == "core" ]] && continue
  while IFS= read -r prog; do
    _check_program "$prog" "false" "user:${user}"
  done < <(_strip "$cfg" | jq -r '.programs[]?' 2>/dev/null)
done < <(find "${OS}/users" -name "config.jsonc")

# =============================================================================
_section "9. Extras JSON files"
# =============================================================================
for de in kde hyprland; do
  json="${OS}/extras/desktop/${de}/install-${de}.jsonc"
  if [[ -f "$json" ]]; then
    _jsonc_valid "$json" "extras/desktop/${de}/install-${de}.jsonc"
  else
    _fail "extras/desktop/${de}/install-${de}.jsonc  (not found)"
  fi
done

# =============================================================================
_section "10. Host config cross-refs  (referenced users exist)"
# =============================================================================
while IFS= read -r cfg; do
  host="$(basename "$(dirname "$cfg")")"
  [[ "$host" == "core" ]] && continue
  while IFS= read -r user; do
    if [[ -d "${OS}/users/${user}" ]]; then
      _pass "host:${host} → user '${user}' directory exists"
    else
      _fail "host:${host} → user '${user}' not found in users/"
    fi
  done < <(_strip "$cfg" | jq -r '.users[]?' 2>/dev/null)
done < <(find "${OS}/hosts" -name "config.jsonc")

# =============================================================================
_section "11. User config cross-refs  (referenced programs consistent)"
# =============================================================================
while IFS= read -r cfg; do
  user="$(basename "$(dirname "$cfg")")"
  [[ "$user" == "core" ]] && continue
  while IFS= read -r prog; do
    if [[ -v _prog_dir["$prog"] ]]; then
      _pass "user:${user} → program '${prog}' exists"
    else
      _fail "user:${user} → program '${prog}' not found in programs/"
    fi
  done < <(_strip "$cfg" | jq -r '.programs[]?' 2>/dev/null)
done < <(find "${OS}/users" -name "config.jsonc")

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
  for fn in "${_commons_fns[@]}"; do
    if grep -qE "^[[:space:]]*(function[[:space:]]+)?${fn}[[:space:]]*\(" \
        "$script" 2>/dev/null; then
      _fail "${rel}: redefines commons helper '${fn}()' (see ADR 0011)"
      _dups_found=$((_dups_found + 1))
    fi
  done
done < <(find "${OS}/programs" -name install.sh)
if (( _dups_found == 0 )); then
  _pass "no programs/*/install.sh redefines a commons helper"
fi

# =============================================================================
_section "13. No _fixture/ directories under .os/programs/"
# =============================================================================
# Per ADR 0013 + config-generator-finalization slice 04, the production
# programs/ tree must ship no fixture program. Test fixtures live under
# .os/tests/fixtures/programs/ and are reached via PROGRAMS_ROOT overrides.
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
  done < <(find "${OS}/hosts" "${OS}/users" -name config.jsonc) | sort -u
)"
_aur_pkgs="$(
  while IFS= read -r cfg; do
    _strip "$cfg" | jq -r '.packages.aur[]?' 2>/dev/null
  done < <(find "${OS}/hosts" "${OS}/users" -name config.jsonc) | sort -u
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
