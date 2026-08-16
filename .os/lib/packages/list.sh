#!/usr/bin/env bash
# =============================================================================
# lib/packages/list.sh — Package collection and base system installation
# =============================================================================
# Sourced by 03-install.sh.
# Requires: lib/common.sh already sourced.
#
# Provides:
#   collect_packages — merges the Base Package List, the derived sets, and the
#                      Effective Config's packages.repo into a sorted unique
#                      list
#   install_base — updates mirrorlist, runs pacstrap with
#                  collected packages
# =============================================================================

# collect_packages parses packages.repo through the Categorized List Parser on
# every call now, so the dependency is explicit rather than assumed of callers.
# shellcheck source=../config/categorized-list.sh
declare -F categorized_list_parse >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../config/categorized-list.sh"
# shellcheck source=../boot/bootloaders.sh
declare -F bootloader_packages >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../boot/bootloaders.sh"

# =============================================================================
# PACKAGE COLLECTION
# =============================================================================

collect_packages() {
  # Builds the full package list to install via pacstrap.
  #
  # Sources (merged and deduplicated):
  #   1. Base packages — always installed regardless of config
  #   2. Kernel packages — selected by options.kernel in config
  #      'lts'     → linux-lts + linux-lts-headers  (recommended, always
  #                  supported by archzfs, moves slowly)
  #      'default' → linux + linux-headers           (latest rolling kernel,
  #                  may temporarily be unsupported by archzfs)
  #   3. Bootloader packages — selected by options.bootloader in the profile
  #   4. Host packages.repo[] — repo packages from the merged host
  #                            config
  #   5. GPU_PACMAN_PACKAGES — resolved by resolve_environment()
  #   6. AUDIO_PACKAGES — resolved by resolve_environment()
  #
  # Output: one package name per line, sorted and deduplicated.
  resolve_environment

  # ── Kernel selection ──────────────────────────────────────────────────────
  # Every selected flavour token (Kernel Selection) is installed with its
  # matching headers, mapped through the single token table in lib/packages/kernel.sh.
  # zfs-dkms builds ZFS against whichever headers are present, so one zfs-dkms
  # covers all installed kernels (added once below, regardless of count).
  local kernel_pkgs=() tok
  while IFS= read -r tok; do
    [[ -n "$tok" ]] || continue
    kernel_pkgs+=("$(kernel_pkg "$tok")" "$(kernel_headers_pkg "$tok")")
  done < <(install_config_kernels)

  # ── Bootloader selection ──────────────────────────────────────────────────
  # Extra package(s) come from the Bootloader Manifest (ADR 0077). Today:
  # systemd-boot adds nothing, grub adds grub (it ships zfs.mod and boots ZFS
  # pools natively — grub-mkconfig runs with ZPOOL_VDEV_NAME_PATH=YES in the
  # adapter). efibootmgr (base) registers UEFI entries for both.
  local bootloader
  bootloader="$(install_config_bootloader)"
  local bootloader_pkgs=()
  mapfile -t bootloader_pkgs < <(bootloader_packages "$bootloader")

  local pkgs=(
    # ── Core system ───────────────────────────────────────────────────────
    base
    base-devel
    "${kernel_pkgs[@]}" # kernel(s) + headers; headers needed by zfs-dkms
    linux-firmware

    # ── CPU microcode ─────────────────────────────────────────────────────
    # Resolved per CPU vendor below (ADR 0038), not hardcoded to both.

    # ── ZFS ───────────────────────────────────────────────────────────────
    # zfs-dkms / zfs-utils are appended below only when some group is ZFS
    # (ADR 0043); a pure non-ZFS install must not pull ZFS userland.

    # ── Network ───────────────────────────────────────────────────────────
    networkmanager # handles wired + wireless; enabled in chroot
    openssh        # ssh-keygen used by create-user.sh + sops setup

    # ── Universal infrastructure ──────────────────────────────────────────
    cronie # cron daemon; enabled in chroot (ADR 0026) — every host needs it

    # ── Bootloader + EFI tools ────────────────────────────────────────────
    efibootmgr # manages UEFI boot entries
    dosfstools # mkfs.fat for ESP formatting
    "${bootloader_pkgs[@]+"${bootloader_pkgs[@]}"}"

    # ── Core utilities ────────────────────────────────────────────────────
    vim
    git
    sudo
    rsync          # used by the ESP mirror pacman hook
    jq             # used by the installer; handy on the installed system
    pacman-contrib # provides paccache for package cache management
    stow           # the Runner stows dotfiles for EVERY user, unconditionally

    # ── Documentation ─────────────────────────────────────────────────────
    man-db
    man-pages
    texinfo
  )

  # ── Host repo packages ─────────────────────────────────────────────────────
  # packages.repo from the EFFECTIVE CONFIG, which already carries the resolved
  # core+profile merge. Reading it here rather than re-loading the committed
  # profile by hostname is what makes all three front-ends agree: the guided
  # and inline-config paths have no hosts/<hostname>/ directory to re-read, so
  # anything they authored (including the extra-packages row) was silently
  # dropped. AUR packages (packages.aur) are handled separately in profiles.sh
  # via paru.
  local repo_json
  repo_json="$(jsonc_strip "$CONFIG_FILE" | jq -c '.packages.repo // {}')"
  while IFS= read -r p; do
    [[ -n "$p" ]] && pkgs+=("$p")
  done < <(categorized_list_parse "$repo_json" string "packages.repo")

  # ZFS userland — only when some group is ZFS (root or a data pool). A pure
  # non-ZFS install installs no ZFS packages (ADR 0043). zfs-dkms compiles ZFS
  # against the installed kernel headers; zfs-utils provides zpool/zfs.
  if [[ "$(install_config_any_zfs)" == "true" ]]; then
    pkgs+=(zfs-dkms zfs-utils)
  fi

  # LUKS userland for any non-ZFS encrypted group — a non-zfs encrypted root
  # (mkinitcpio `encrypt` hook) OR an encrypted ext4/xfs/btrfs data disk
  # (boot-time crypttab). ZFS uses its own native crypto so it needs none of
  # this (ADR 0043).
  if [[ "$(install_config_any_nonzfs_luks)" == "true" ]]; then
    pkgs+=(cryptsetup)
  fi

  # Per-filesystem userland for any non-zfs group that uses it (ADR 0043):
  # xfsprogs (fsck.xfs/mkfs.xfs) for xfs, btrfs-progs (fsck.btrfs/mkfs.btrfs) for
  # btrfs — so the data group fscks + mounts at boot. ext4 rides e2fsprogs in
  # base; zfs has no mkfs. Independent of encryption.
  [[ "$(install_config_uses_filesystem xfs)" == "true" ]]   && pkgs+=(xfsprogs)
  [[ "$(install_config_uses_filesystem btrfs)" == "true" ]] && pkgs+=(btrfs-progs)

  # GPU and audio packages resolved during validate_install_context
  pkgs+=("${GPU_PACMAN_PACKAGES[@]+"${GPU_PACMAN_PACKAGES[@]}"}")
  pkgs+=("${AUDIO_PACKAGES[@]+"${AUDIO_PACKAGES[@]}"}")

  # CPU microcode — only the running CPU's vendor's package (ADR 0038); empty
  # on a VM / unknown CPU, which then installs no microcode.
  local _ucode
  _ucode="$(microcode_vendor_package "$(microcode_detect_vendor)")"
  [[ -n "$_ucode" ]] && pkgs+=("$_ucode")

  # Sort and deduplicate — pacstrap handles duplicates gracefully but this
  # keeps the output clean and avoids confusion in the install log.
  printf '%s\n' "${pkgs[@]}" | sort -u
}

# =============================================================================
# BASE SYSTEM INSTALLATION
# =============================================================================

# _enable_pacman_repo <name> — enable one official optional repo in the host
# /etc/pacman.conf. Uncomments the shipped `#[name]` + its `#Include` in place
# (preserving Arch's testing-above-stable ordering); appends a standard section
# only if the ISO's pacman.conf lacks it. Idempotent. chroot.sh copies this
# pacman.conf into the target, so the installed system inherits the same repos.
_enable_pacman_repo() {
  local repo="$1"
  grep -q "^\[${repo}\]" /etc/pacman.conf && return 0   # already enabled
  if grep -q "^#\[${repo}\]" /etc/pacman.conf; then
    # Range anchored on '#[repo]' (the ']' keeps [multilib] from catching
    # [multilib-testing]) through its adjacent '#Include'.
    sed -i "/^#\[${repo}\]/,/^#Include/ s/^#//" /etc/pacman.conf
  else
    printf '\n[%s]\nInclude = /etc/pacman.d/mirrorlist\n' "$repo" \
      >> /etc/pacman.conf
  fi
  grep -q "^\[${repo}\]" /etc/pacman.conf \
    || error "Failed to enable [${repo}] in /etc/pacman.conf."
}

enable_optional_repos() {
  # The Optional Repositories the operator selected (ADR 0072): any of
  # multilib / multilib-testing / core-testing / extra-testing. Defaults to
  # `multilib` (the historical options.multilib=true). lib32-* packages
  # (steam, lib32-nvidia-utils) live in [multilib], and pacstrap reads the HOST
  # pacman.conf, so the repos must be enabled here — before pacstrap — or those
  # targets error as "target not found".
  local -a repos; mapfile -t repos < <(install_config_optional_repos)
  if ((${#repos[@]} == 0)); then
    info "[repos] no optional repositories selected — skipping."
    return 0
  fi
  local r
  for r in "${repos[@]}"; do
    [[ -n "$r" ]] || continue
    info "Enabling [${r}] repository..."
    _enable_pacman_repo "$r"
  done
  pacman -Sy --noconfirm >/dev/null 2>&1 || true
}

disable_checkspace() {
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
    sed -i 's/^CheckSpace/#CheckSpace/' /etc/pacman.conf
  else
    info "pacman CheckSpace already disabled."
  fi
}

# apply_pacman_options [<conf>] — write the Pacman Options (ADR 0074) into the
# `[options]` block of <conf> (default the host /etc/pacman.conf, which pacstrap
# reads and chroot.sh copies into the target, so the installed system inherits
# them). AUTHORITATIVE over the managed set only: every managed flag reflects
# its toggle no matter what the ISO shipped — ON uncomments/appends the flag,
# OFF comments it out. ParallelDownloads is set to the chosen value.
# ILoveCandy is not shipped in Arch's default pacman.conf, so ON appends it and
# OFF drops it. Unrelated lines (SigLevel, Include, repo sections) are never
# touched, and re-running converges to the same file (idempotent). CheckSpace is
# out of scope by design — disable_checkspace owns it on the ZFS path.
apply_pacman_options() {
  local conf="${1:-/etc/pacman.conf}"
  [[ -f "$conf" ]] || { warn "apply_pacman_options: ${conf} missing — skipping."
    return 0; }

  on_off() { [[ "$1" == "true" ]] && printf 'on' || printf 'off'; }

  local tmp; tmp="$(mktemp)"
  PAC_COLOR="$(on_off "$(install_config_pacman_color)")" \
  PAC_VERBOSE="$(on_off "$(install_config_pacman_verbose_pkg_lists)")" \
  PAC_TIMEOUT="$(on_off "$(install_config_pacman_disable_download_timeout)")" \
  PAC_NOPROGRESS="$(on_off "$(install_config_pacman_no_progress_bar)")" \
  PAC_CANDY="$(on_off "$(install_config_pacman_ilovecandy)")" \
  PAC_PARALLEL="$(install_config_pacman_parallel_downloads)" \
  awk '
    BEGIN {
      want["Color"]         = ENVIRON["PAC_COLOR"]
      want["VerbosePkgLists"]        = ENVIRON["PAC_VERBOSE"]
      want["DisableDownloadTimeout"] = ENVIRON["PAC_TIMEOUT"]
      want["NoProgressBar"]          = ENVIRON["PAC_NOPROGRESS"]
      want["ILoveCandy"]             = ENVIRON["PAC_CANDY"]
      parallel = ENVIRON["PAC_PARALLEL"]
      names = "Color VerbosePkgLists DisableDownloadTimeout"
      names = names " NoProgressBar ILoveCandy"
      n = split(names, order, " ")
    }
    # Which managed directive (if any) a line carries, comment or not.
    function directive(line,   l, i) {
      l = line
      sub(/^[#[:space:]]+/, "", l)
      for (i = 1; i <= n; i++)
        if (l ~ ("^" order[i] "[[:space:]]*$")) return order[i]
      if (l ~ /^ParallelDownloads([[:space:]]|=)/) return "ParallelDownloads"
      return ""
    }
    # Emit the managed on-flags / ParallelDownloads not yet seen, at the end of
    # the [options] block (called before the next section header or at EOF).
    function flush(   i, nm) {
      if (flushed) return
      for (i = 1; i <= n; i++) {
        nm = order[i]
        if (!seen[nm] && want[nm] == "on") print nm
      }
      if (parallel != "" && !seen["ParallelDownloads"])
        print "ParallelDownloads = " parallel
      flushed = 1
    }
    /^[[:space:]]*\[/ {
      if (in_options) flush()
      in_options = ($0 ~ /^\[options\][[:space:]]*$/)
      print; next
    }
    {
      if (in_options) {
        d = directive($0)
        if (d != "") {
          seen[d] = 1
          if (d == "ParallelDownloads") {
            if (parallel != "") print "ParallelDownloads = " parallel
            else print
            next
          }
          if (want[d] == "on") print d
          else if ($0 ~ /^[[:space:]]*#/) print   # already off — keep verbatim
          else print "#" d
          next
        }
      }
      print
    }
    END { if (in_options) flush() }
  ' "$conf" > "$tmp"

  if cmp -s "$conf" "$tmp"; then
    info "Pacman options already applied to ${conf}."
    rm -f "$tmp"
  else
    cat "$tmp" > "$conf"
    rm -f "$tmp"
    info "Applied Pacman options to ${conf}."
  fi
}

# reflector_country_args — the `--country <comma-list>` args for reflector,
# built from the Mirror Countries selection (issue 06). Emits one arg per line
# so install_base can mapfile them into an array. Pure: reads config only.
reflector_country_args() {
  local -a countries
  mapfile -t countries < <(install_config_mirror_countries)
  local joined; printf -v joined '%s,' "${countries[@]}"
  printf '%s\n' "--country" "${joined%,}"
}

# prepend_custom_mirror_servers — write the operator's custom mirror Servers
# (ADR 0072) ABOVE the reflector-ranked list, so they are tried first. Called
# after reflector --save so they are not clobbered. No-op when none declared.
prepend_custom_mirror_servers() {
  local -a servers; mapfile -t servers < <(install_config_mirror_servers)
  ((${#servers[@]})) || return 0
  local ml=/etc/pacman.d/mirrorlist s tmp
  tmp="$(mktemp)"
  { printf '# Custom mirror servers (guided installer)\n'
    for s in "${servers[@]}"; do
      [[ -n "$s" ]] && printf 'Server = %s\n' "$s"
    done
    printf '\n'; cat "$ml" 2>/dev/null; } > "$tmp"
  mv "$tmp" "$ml"
  info "Prepended ${#servers[@]} custom mirror server(s)."
}

# _custom_repo_siglevel <sign_check> <sign_option> → the pacman SigLevel value.
# Never → "Never" (no signing); else "<Optional|Required> <TrustAll|TrustedOnly>".
_custom_repo_siglevel() {
  local check="$1" opt="$2"
  [[ "$check" == "Never" ]] && { printf 'Never'; return; }
  printf '%s %s' "${check:-Required}" "${opt:-TrustedOnly}"
}

# add_custom_repositories — append the operator's archinstall-style custom repos
# (ADR 0072) to the host /etc/pacman.conf, BEFORE pacstrap (so their targets
# resolve) and inherited by the target via chroot.sh's pacman.conf copy. Each
# repo is `name<TAB>url<TAB>sign_check<TAB>sign_option`. Idempotent per name.
add_custom_repositories() {
  local name url check opt sig
  while IFS=$'\t' read -r name url check opt; do
    [[ -n "$name" && -n "$url" ]] || continue
    grep -q "^\[${name}\]" /etc/pacman.conf && continue
    sig="$(_custom_repo_siglevel "$check" "$opt")"
    info "Adding custom repository [${name}]..."
    printf '\n[%s]\nSigLevel = %s\nServer = %s\n' "$name" "$sig" "$url" \
      >> /etc/pacman.conf
  done < <(install_config_custom_repositories)
}

install_base() {
  section "Installing Base System (pacstrap)"

  # Refresh mirrorlist with the fastest mirrors near the operator (Mirror
  # Countries) — non-fatal if reflector fails (e.g. offline).
  info "Updating mirror list..."
  local -a _country_args
  mapfile -t _country_args < <(reflector_country_args)
  reflector "${_country_args[@]}" --latest 10 --sort rate \
    --save /etc/pacman.d/mirrorlist 2>/dev/null ||
    warn "reflector failed — using existing mirrorlist."
  # Operator's custom mirror servers go above the ranked list (ADR 0072).
  prepend_custom_mirror_servers

  # Enable the selected Optional Repositories (multilib + testing) and add any
  # custom repositories before pacstrap runs (ADR 0072).
  enable_optional_repos
  add_custom_repositories

  # Apply the operator's Pacman Options (ADR 0074) to the host pacman.conf
  # before pacstrap, so Color / ParallelDownloads / ILoveCandy act during base
  # install too and the target inherits them via chroot.sh's pacman.conf copy.
  apply_pacman_options

  # ZFS reports space in a way pacman's CheckSpace can't read — disable it so
  # pacstrap (and later upgrades) don't abort with a false "too full".
  disable_checkspace

  mapfile -t pkgs < <(collect_packages)
  info "Packages to install: ${#pkgs[@]}"

  # pacstrap flags:
  #   -K       — initialise a fresh pacman keyring inside the chroot (required
  #              for signature verification of newly installed packages)
  #   --needed — skip packages that are already installed in the target
  #              (guards against re-installing if pacstrap is re-run)
  #
  # "${pkgs[@]}" is properly quoted: each array element becomes its own arg
  # to pacstrap. Package names never contain whitespace, so even unquoted
  # would be safe — quoted is the shellcheck-clean idiom (no SC2068 disable
  # needed).
  pacstrap -K "${MOUNT_ROOT}" --needed "${pkgs[@]}"

  # Clean the package cache inside the new root — downloaded .pkg.tar.zst
  # files are no longer needed after install and take ~500 MB–1.5 GB.
  # Keep 0 cached versions (keep=0 removes everything).
  info "Cleaning pacman package cache..."
  # Remove all cached packages directly — no need to enter chroot.
  # paccache would work too but requires the chroot to be fully set up.
  rm -f "${MOUNT_ROOT}/var/cache/pacman/pkg/"*.pkg.tar.zst \
    "${MOUNT_ROOT}/var/cache/pacman/pkg/"*.pkg.tar.xz \
    "${MOUNT_ROOT}/var/cache/pacman/pkg/"*.pkg.tar.gz \
    "${MOUNT_ROOT}/var/cache/pacman/pkg/"*.pkg.tar 2>/dev/null || true
  info "Package cache cleared" \
       "($(du -sh "${MOUNT_ROOT}/var/cache/pacman/pkg/" 2>/dev/null \
          | cut -f1) remaining)."

  # Configure pacman to keep only 1 cached version going forward
  # (prevents cache from growing unbounded after updates)
  if ! grep -q '^CleanMethod' "${MOUNT_ROOT}/etc/pacman.conf" 2>/dev/null; then
    sed -i 's/^#CleanMethod.*/CleanMethod = KeepCurrent/' \
      "${MOUNT_ROOT}/etc/pacman.conf" 2>/dev/null || true
  fi


  # pacstrap -K initialises the keyring but gpg-agent state can be stale by
  # the time paru runs inside arch-chroot. Re-init and populate explicitly so
  # pacman signature checks work reliably during profile installs.
  info "Initialising pacman keyring inside chroot..."
  arch-chroot "${MOUNT_ROOT}" pacman-key --init
  arch-chroot "${MOUNT_ROOT}" pacman-key --populate archlinux

  info "Base system installed."
}
