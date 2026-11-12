#!/usr/bin/env bash
# =============================================================================
# aur-vet-maintenance.sh — aur-vet's non-hook commands (ADR 0143)
# =============================================================================
# Sourced by aur-vet (it provides say, die, data_directory and
# library_directory): refresh-indicators, audit and doctor.
# =============================================================================

# ── refresh-indicators ──────────────────────────────────────────────────────
# Pull the official Arch Atomic Arch list and lenucksi's npm list, append the
# names not yet held, tagged with their source key, and print them for review.
# Explicit and offline-safe: vetting itself never fetches (ADR 0143).
ARCH_LIST_URL="https://md.archlinux.org/s/SxbqukK6IA/download"
NPM_LIST_URL="https://raw.githubusercontent.com/lenucksi/aur-malware-check"
NPM_LIST_URL+="/main/data/campaigns/aur-infected/npm-packages.txt"

refresh_indicators() {
  local indicators arch npm additions count=0
  indicators="$(data_directory)/indicators.tsv"
  [[ -w "$indicators" ]] || die "not writable: $indicators"
  arch="$(curl -fsSL "${AUR_VET_ARCH_LIST_URL:-$ARCH_LIST_URL}")" \
    || die "download failed: Arch package list"
  npm="$(curl -fsSL "${AUR_VET_NPM_LIST_URL:-$NPM_LIST_URL}")" \
    || die "download failed: npm package list"
  additions="$(new_indicator_rows "$indicators" "$arch" "$npm")"
  if [[ -n "$additions" ]]; then
    printf '%s\n' "$additions" >> "$indicators"
    count="$(printf '%s\n' "$additions" | wc -l)"
    printf '%s\n' "$additions"
  fi
  say "added ${count} indicator(s) to ${indicators} —" \
    "review the diff, then commit"
}

# new_indicator_rows <indicators.tsv> <arch-list> <npm-list> — an Indicator
# row for each listed name not held yet, each once. AUR names are
# [a-z0-9@._+-] (npm names may hold /); anything else (markup, typos) is
# dropped.
new_indicator_rows() {
  local line value
  local -A held=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" == "#"* ]] && continue
    # The row's kind and value (kind<TAB>value).
    held["$(printf '%s\n' "$line" | cut -f1,2)"]=1
  done < "$1"
  while IFS= read -r value; do
    [[ "$value" =~ ^[a-z0-9@._+-]+$ ]] || continue
    [[ -n "${held["pkgbase"$'\t'"$value"]:-}" ]] && continue
    held["pkgbase"$'\t'"$value"]=1
    printf 'pkgbase\t%s\tatomic-arch\tarch-md\n' "$value"
  done < <(printf '%s\n' "$2")
  while IFS= read -r value; do
    [[ "$value" =~ ^[a-z0-9@._/-]+$ ]] || continue
    [[ -n "${held["npm"$'\t'"$value"]:-}" ]] && continue
    held["npm"$'\t'"$value"]=1
    printf 'npm\t%s\tatomic-arch\tlenucksi\n' "$value"
  done < <(printf '%s\n' "$3")
  return 0
}

# ── audit ───────────────────────────────────────────────────────────────────
# Post-install check for installer-created VMs, never the operator's host
# (ADR 0143): installed foreign packages on a campaign list, campaign npm/bun
# packages in caches or global node_modules, and on-disk IOC paths.
# AUR_VET_AUDIT_ROOT prefixes every path (tests).
audit() {
  local root="${AUR_VET_AUDIT_ROOT:-}" data kind value campaign hits=0
  data="$(data_directory)"
  local -A campaign_of=()
  local -a npm_names=() paths=() homes=()
  while IFS=$'\t' read -r kind value campaign; do
    case "$kind" in
      pkgbase) campaign_of[$value]="$campaign" ;;
      npm) npm_names+=("$value") ;;
      path) paths+=("$value") ;;
    esac
  done < <(awk -v rules="$data/rules.tsv" -v indicators="$data/indicators.tsv" \
             -v campaigns="$data/campaigns.tsv" -v list_indicators=1 \
             -f "$(library_directory)/scan.awk" </dev/null)

  local package
  while IFS= read -r package; do
    [[ -n "${campaign_of[$package]:-}" ]] \
      && audit_hit "installed ${package} is on the" \
        "${campaign_of[$package]} list"
  done < <(pacman -Qmq 2>/dev/null || true)

  local home
  for home in "$root"/home/* "$root/root"; do
    [[ -d "$home" ]] && homes+=("$home")
  done
  audit_npm
  audit_paths

  if ((hits)); then say "audit: ${hits} finding(s)"; return 1; fi
  say "audit: clean"
}

# audit_hit <text> — report one audit finding (counts audit's hits).
audit_hit() { say "AUDIT $*"; hits=$((hits + 1)); }

# audit_npm — campaign npm/bun packages in each home's caches and global
# node_modules, and the system's (reads audit's root, homes, npm_names).
audit_npm() {
  local name home path cached
  for name in "${npm_names[@]}"; do
    for home in "${homes[@]}"; do
      # The npm cache index files that mention the package.
      cached="$(find "$home/.npm/_cacache/index-v5" -type f \
        -exec grep -lF -- "/${name}/-/" {} + 2>/dev/null || true)"
      [[ -n "$cached" ]] \
        && audit_hit "npm cache of ${home:${#root}} holds ${name}"
      for path in "$home/.bun/install/cache/${name}" \
                  "$home/.bun/install/cache/${name}@"* \
                  "$home/.local/lib/node_modules/${name}" \
                  "$home/.npm-global/lib/node_modules/${name}"; do
        [[ -e "$path" ]] && audit_hit "${path:${#root}}"
      done
    done
    for path in "$root/usr/lib/node_modules/${name}" \
                "$root/usr/local/lib/node_modules/${name}"; do
      [[ -e "$path" ]] && audit_hit "${path:${#root}}"
    done
  done
  return 0
}

# audit_paths — the on-disk IOC paths; a ~/ path is looked for in every home
# (reads audit's root, homes, paths).
audit_paths() {
  local path home
  for path in "${paths[@]}"; do
    # shellcheck disable=SC2088  # a literal ~/ marker from indicators.tsv
    if [[ "$path" == "~/"* ]]; then
      for home in "${homes[@]}"; do
        [[ -e "$home/${path:2}" ]] && audit_hit "${home:${#root}}/${path:2}"
      done
    elif [[ -e "${root}${path}" ]]; then
      audit_hit "$path"
    fi
  done
  return 0
}

# ── doctor ──────────────────────────────────────────────────────────────────
# Login check (/etc/profile.d/aur-vet.sh): paru reads $PARU_CONF or the
# user's own paru.conf *instead of* /etc/paru.conf, so any of them without
# the hook runs AUR builds unvetted (ADR 0143). Silent when all is well.
HOOK_LINE="PreBuildCommand = /usr/local/bin/aur-vet"
doctor() {
  local system="${AUR_VET_ETC_PARU_CONF:-/etc/paru.conf}" file bad=0
  local user="${XDG_CONFIG_HOME:-$HOME/.config}/paru/paru.conf"
  for file in "${PARU_CONF:-}" "$user" "$system"; do
    [[ -n "$file" && -f "$file" ]] || continue
    hook_in_bin "$file" && continue
    say "WARNING: ${file} is without the AUR Vetting hook — AUR builds run" \
      "unvetted. Add under [bin]: ${HOOK_LINE}"
    bad=1
  done
  return "$bad"
}

# hook_in_bin <paru.conf> — rc 0 when its [bin] section holds our hook line.
# paru parses PreBuildCommand only in [bin]; anywhere else it is ignored.
hook_in_bin() {
  local line section=""
  local header='^[[:space:]]*\['
  local hook='^[[:space:]]*PreBuildCommand[[:space:]]*=[[:space:]]*'
  hook+='/usr/local/bin/aur-vet[[:space:]]*$'
  while IFS= read -r line || [[ -n "$line" ]]; do
    # A section header, its spaces removed.
    [[ "$line" =~ $header ]] \
      && section="$(printf '%s\n' "$line" | tr -d '[:space:]')"
    [[ "$section" == "[bin]" && "$line" =~ $hook ]] && return 0
  done < "$1"
  return 1
}
