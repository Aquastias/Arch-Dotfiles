#!/usr/bin/env bash
# =============================================================================
# lib/packages/pacman-config.sh — host pacman.conf edits before pacstrap
# =============================================================================
# pacstrap reads the HOST /etc/pacman.conf and chroot.sh copies it into the
# target, so every edit here (Optional Repositories, custom repositories,
# Pacman Options, CheckSpace, the test-only Audit Cache) lands on both systems.
#
# Used by: lib/packages/package-list.sh (package_list_install_base),
# 03-install.sh (pacman_config_strip_audit_cache). Requires lib/common.sh.
# =============================================================================

[[ -n "${_PACMAN_CONFIG_SH_SOURCED:-}" ]] && return 0
_PACMAN_CONFIG_SH_SOURCED=1
_PACMAN_CONFIG_DIRECTORY="${BASH_SOURCE[0]%/*}"
[[ "$_PACMAN_CONFIG_DIRECTORY" != "${BASH_SOURCE[0]}" ]] \
  || _PACMAN_CONFIG_DIRECTORY=.
_PACMAN_CONFIG_DIRECTORY="$(cd "$_PACMAN_CONFIG_DIRECTORY" && pwd)"

# _pacman_config_uncomment_section <name> — in /etc/pacman.conf, drop the
# leading `#` from the shipped `#[name]` line through its next `#Include`.
_pacman_config_uncomment_section() {
  local header="#[$1]" edited line in_section=0
  edited="$(mktemp)"
  while IFS= read -r line || [[ -n "$line" ]]; do
    # The `]` in the header keeps [multilib] from catching [multilib-testing].
    [[ "$line" == "$header"* ]] && in_section=1
    if (( in_section )); then
      [[ "$line" == "#Include"* ]] && in_section=0
      [[ "$line" == "#"* ]] && line="${line:1}"
    fi
    printf '%s\n' "$line"
  done < /etc/pacman.conf > "$edited"
  cat "$edited" > /etc/pacman.conf
  rm -f "$edited"
}

# _pacman_config_enable_repository <name> — enable one official optional repo in
# the host /etc/pacman.conf. Uncomments the shipped `#[name]` + its `#Include`
# in place (preserving Arch's testing-above-stable ordering); appends a standard
# section only if the ISO's pacman.conf lacks it. Idempotent. chroot.sh copies
# this pacman.conf into the target, so the installed system inherits the same
# repos.
_pacman_config_enable_repository() {
  local repository="$1"
  grep -q "^\[${repository}\]" /etc/pacman.conf && return 0   # already enabled
  if grep -q "^#\[${repository}\]" /etc/pacman.conf; then
    # Uncomment the shipped section.
    _pacman_config_uncomment_section "$repository"
  else
    printf '\n[%s]\nInclude = /etc/pacman.d/mirrorlist\n' "$repository" \
      >> /etc/pacman.conf
  fi
  grep -q "^\[${repository}\]" /etc/pacman.conf \
    || error "Failed to enable [${repository}] in /etc/pacman.conf."
}

pacman_config_enable_optional_repositories() {
  # The Optional Repositories the operator selected (ADR 0072): any of
  # multilib / multilib-testing / core-testing / extra-testing. Defaults to
  # `multilib` (the historical options.multilib=true). lib32-* packages
  # (steam, lib32-nvidia-utils) live in [multilib], and pacstrap reads the HOST
  # pacman.conf, so the repos must be enabled here — before pacstrap — or those
  # targets error as "target not found".
  local -a repositories
  mapfile -t repositories < <(install_config_optional_repos)
  if ((${#repositories[@]} == 0)); then
    info "[repos] no optional repositories selected — skipping."
    return 0
  fi
  local repository
  for repository in "${repositories[@]}"; do
    [[ -n "$repository" ]] || continue
    info "Enabling [${repository}] repository..."
    _pacman_config_enable_repository "$repository"
  done
  pacman -Sy --noconfirm >/dev/null 2>&1 || true
}

pacman_config_disable_checkspace() {
  # pacman's CheckSpace mis-estimates free space on ZFS: it rounds every file
  # up to the dataset recordsize (128K), inflating the "needed" total several-
  # fold, so pacstrap aborts "Partition /mnt too full" even with gigabytes
  # free (e.g. a 20G OS disk after an 8G swap zvol — ~9G free, but ~10G
  # "needed" for a 2.3G install). pacstrap reads the HOST /etc/pacman.conf and
  # chroot.sh copies it into the new root, so disabling it here also spares the
  # installed ZFS system the same false failure on every future pacman -Syu.
  # Idempotent.
  if grep -q '^CheckSpace' /etc/pacman.conf; then
    info "Disabling pacman CheckSpace (unreliable on ZFS)..."
    # Comment the directive out.
    sed -i 's/^CheckSpace/#CheckSpace/' /etc/pacman.conf
  else
    info "pacman CheckSpace already disabled."
  fi
}

# pacman_config_apply_options [<conf>] — write the Pacman Options (ADR 0074)
# into the `[options]` block of <conf> (default the host /etc/pacman.conf, which
# pacstrap reads and chroot.sh copies into the target, so the installed system
# inherits them). AUTHORITATIVE over the managed set only: every managed flag
# reflects its toggle no matter what the ISO shipped — ON uncomments/appends the
# flag, OFF comments it out. ParallelDownloads is set to the chosen value.
# ILoveCandy is not shipped in Arch's default pacman.conf, so ON appends it and
# OFF drops it. Unrelated lines (SigLevel, Include, repo sections) are never
# touched, and re-running converges to the same file (idempotent). CheckSpace is
# out of scope by design — pacman_config_disable_checkspace owns it on the ZFS
# path.
pacman_config_apply_options() {
  local pacman_config_file="${1:-/etc/pacman.conf}"
  [[ -f "$pacman_config_file" ]] || {
    warn "pacman_config_apply_options: ${pacman_config_file} missing —" \
      "skipping."
    return 0
  }

  local rewritten_file; rewritten_file="$(mktemp)"
  PAC_COLOR="$(_pacman_config_on_off "$(install_config_pacman_color)")" \
  PAC_VERBOSE="$(_pacman_config_on_off \
    "$(install_config_pacman_verbose_pkg_lists)")" \
  PAC_TIMEOUT="$(_pacman_config_on_off \
    "$(install_config_pacman_disable_download_timeout)")" \
  PAC_NOPROGRESS="$(_pacman_config_on_off \
    "$(install_config_pacman_no_progress_bar)")" \
  PAC_CANDY="$(_pacman_config_on_off "$(install_config_pacman_ilovecandy)")" \
  PAC_PARALLEL="$(install_config_pacman_parallel_downloads)" \
    _pacman_config_rewrite_options "$pacman_config_file" > "$rewritten_file"

  if cmp -s "$pacman_config_file" "$rewritten_file"; then
    info "Pacman options already applied to ${pacman_config_file}."
    rm -f "$rewritten_file"
  else
    cat "$rewritten_file" > "$pacman_config_file"
    rm -f "$rewritten_file"
    info "Applied Pacman options to ${pacman_config_file}."
  fi
}

_pacman_config_on_off() { [[ "$1" == "true" ]] && printf 'on' || printf 'off'; }
# _pacman_config_rewrite_options <pacman-config-file> — print it with the
# managed `[options]` directives set from the PAC_* environment.
_pacman_config_rewrite_options() {
  awk -f "${_PACMAN_CONFIG_DIRECTORY}/pacman-options.awk" "$1"
}

# _pacman_config_custom_repository_siglevel <sign_check> <sign_option> → the
# pacman SigLevel value. Never → "Never" (no signing); else "<Optional|Required>
# <TrustAll|TrustedOnly>".
_pacman_config_custom_repository_siglevel() {
  local check="$1" option="$2"
  [[ "$check" == "Never" ]] && { printf 'Never'; return; }
  printf '%s %s' "${check:-Required}" "${option:-TrustedOnly}"
}

# pacman_config_add_custom_repositories — append the operator's
# archinstall-style custom repos (ADR 0072) to the host /etc/pacman.conf, BEFORE
# pacstrap (so their targets resolve) and inherited by the target via
# chroot.sh's pacman.conf copy. Each repo is
# `name<TAB>url<TAB>sign_check<TAB>sign_option`. Idempotent per name.
pacman_config_add_custom_repositories() {
  local name url check option signature_level
  while IFS=$'\t' read -r name url check option; do
    [[ -n "$name" && -n "$url" ]] || continue
    grep -q "^\[${name}\]" /etc/pacman.conf && continue
    signature_level="$(_pacman_config_custom_repository_siglevel \
      "$check" "$option")"
    info "Adding custom repository [${name}]..."
    printf '\n[%s]\nSigLevel = %s\nServer = %s\n' \
      "$name" "$signature_level" "$url" \
      >> /etc/pacman.conf
  done < <(install_config_custom_repositories)
}

# ── Audit Cache (ADR 0152) — test-only, never set by a real install ─────────
# The Feature Audit harness serves the base variant's packages: a CacheServer
# per repo (tried before the mirrors, a miss falls through) and its built AUR
# packages as [audit-aur]. pacman_config_strip_audit_cache leaves the installed
# system's pacman.conf as shipped.
_AUDIT_AUR_REPO=audit-aur

# pacman_config_apply_audit_cache [<conf>] — no-op unless
# INSTALL_PKG_CACHE_SERVER / INSTALL_AUDIT_AUR_URL are set.
pacman_config_apply_audit_cache() {
  local pacman_config_file="${1:-/etc/pacman.conf}" rewritten_file line
  if [[ -n "${INSTALL_PKG_CACHE_SERVER:-}" ]]; then
    rewritten_file="$(mktemp)"
    # Each repo section header ([options] is not a repo) gets a CacheServer
    # line right below it.
    while IFS= read -r line || [[ -n "$line" ]]; do
      printf '%s\n' "$line"
      if [[ "$line" == "["* && "$line" != "[options]" ]]; then
        printf 'CacheServer = %s\n' "$INSTALL_PKG_CACHE_SERVER"
      fi
    done < "$pacman_config_file" > "$rewritten_file" \
      && cat "$rewritten_file" > "$pacman_config_file"
    rm -f "$rewritten_file"
  fi
  if [[ -n "${INSTALL_AUDIT_AUR_URL:-}" ]]; then
    printf '\n[%s]\nSigLevel = Optional TrustAll\nServer = %s\n' \
      "$_AUDIT_AUR_REPO" "$INSTALL_AUDIT_AUR_URL" >> "$pacman_config_file"
  fi
  return 0
}

# pacman_config_strip_audit_cache [<conf>] — drop every CacheServer line and the
# [audit-aur] section (with the blank line that introduced it).
pacman_config_strip_audit_cache() {
  local pacman_config_file="${1:-/etc/pacman.conf}" line skip=0
  local -a kept=()
  [[ -f "$pacman_config_file" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" == "CacheServer = "* ]] && continue
    if [[ "$line" == "[$_AUDIT_AUR_REPO]" ]]; then
      # Drop the blank line before the section too.
      (( ${#kept[@]} )) && [[ -z "${kept[-1]}" ]] && unset 'kept[-1]'
      skip=1
      continue
    fi
    # The next section header ends the skipped one.
    [[ "$line" == "["* ]] && skip=0
    (( skip )) || kept+=("$line")
  done < "$pacman_config_file"
  : > "$pacman_config_file"
  (( ${#kept[@]} )) && printf '%s\n' "${kept[@]}" > "$pacman_config_file"
  return 0
}
