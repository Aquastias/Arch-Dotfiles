#!/usr/bin/env bash
# =============================================================================
# lib/zfs/module.sh — shared ZFS kernel-module install/load for the live ISO
# =============================================================================
# Single source of truth for getting a working ZFS module on the running
# live-ISO kernel. Sourced by BOTH 01-bootstrap-zfs.sh (the normal path) and
# 03-install.sh (the fallback in lib/zfs/pools.sh, when bootstrap was skipped
# or its module is no longer loaded).
#
# Before this module existed the fallback carried its own, subtly-wrong copy:
# it ran `pacman -S linux-headers` unpinned (pulling a newer kernel's headers
# than the running ISO kernel) and never passed --kernelsourcedir, so DKMS
# built against the wrong kernel and `modprobe zfs` then found nothing. See
# ADR 0023. Keeping one implementation prevents that drift from recurring.
#
# Requires: lib/common.sh already sourced (info/warn/error/section).
#
# Provides:
#   zfs_remove_stale_archzfs_testing — drop a stale [archzfs-testing] pacman
#                                      block
#   zfs_add_archzfs_repo          — add archzfs repo + signing key (idempotent)
#   zfs_install_dkms <kver>       — DKMS-build ZFS against the EXACT running
#                                   kernel, using the ISO's own headers
#   zfs_load_module               — depmod + modprobe the freshly built module
# =============================================================================

# Guard against double-sourcing (03-install.sh and a future direct source).
[[ -n "${_ZFS_MODULE_SH_SOURCED:-}" ]] && return 0
_ZFS_MODULE_SH_SOURCED=1

# Shared archive.archlinux.org fetch — the exact-version primitive this module
# and the archzfs LTS ceiling pin (ADR 0137) both use. common.sh is assumed
# already sourced by the caller.
# shellcheck source=../packages/archive.sh
source "${BASH_SOURCE[0]%/*}/../packages/archive.sh"

zfs_remove_stale_archzfs_testing() {
  # archzfs-testing no longer exists as a separate repo since the project
  # moved to GitHub in Feb 2026. The single GitHub repo is always current.
  # Remove any stale [archzfs-testing] block left from previous script runs
  # to prevent pacman from trying to fetch a non-existent database.
  if grep -q '\[archzfs-testing\]' /etc/pacman.conf; then
    warn "Removing stale [archzfs-testing] entry from /etc/pacman.conf ..."
    # Delete the [archzfs-testing] block (header + Server line + blank line)
    sed -i '/^\[archzfs-testing\]/,/^$/d' /etc/pacman.conf
    info "[archzfs-testing] removed."
  fi
}

# ── archzfs repository ─────────────────────────────────────────────────────
# IMPORTANT: archzfs.com went stale in early 2026. The project moved to GitHub
# Releases. The new repo is actively maintained and ships current ZFS builds
# (2.4.x as of April 2026).
_MODULE_ARCHZFS_KEY="3A9917BF0DED5C13F69AC68FABEC0A1208037BE9"
_MODULE_ARCHZFS_SERVER=\
"https://github.com/archzfs/archzfs/releases/download/experimental"

zfs_add_archzfs_repo() {
  section "Adding archzfs Repository"

  # Remove any stale [archzfs-testing] block before touching the DB.
  # pacman -Sy would fail trying to fetch archzfs-testing.db if it's present.
  zfs_remove_stale_archzfs_testing
  _module_refresh_keyring
  _module_import_archzfs_key
  _module_write_archzfs_repo

  info "Syncing pacman package databases..."
  _retry 3 "10,30" -- pacman -Sy --noconfirm # refresh db after adding archzfs
}

_module_refresh_keyring() {
  # Initialise and populate the pacman keyring first.
  # On a fresh live ISO this is needed before any new keys can be added.
  info "Refreshing pacman keyring..."
  pacman-key --init
  pacman-key --populate archlinux

  # Update the keyring package itself to avoid "unknown key"
  # errors on older ISOs.
  # -Sy alone (no -u) is safe here because we only need the keyring,
  # not a full upgrade.
  info "Updating archlinux-keyring..."
  _retry 3 "10,30" -- pacman -Sy --noconfirm archlinux-keyring
}

# Import the archzfs signing key from a keyserver and locally sign it.
_module_import_archzfs_key() {
  local key="$_MODULE_ARCHZFS_KEY"
  info "Importing archzfs signing key (${key:0:16}...)..."
  if ! pacman-key --recv-keys "$key" 2>/dev/null; then
    pacman-key --keyserver hkps://keyserver.ubuntu.com \
      --recv-keys "$key" ||
      error "Failed to import archzfs GPG key.
  Try manually: pacman-key --recv-keys ${key}"
  fi
  pacman-key --lsign-key "$key"
}

# Add [archzfs] repository to pacman.conf if not already present.
# SigLevel=Never is the current recommendation from the archzfs project
# while their signing infrastructure is being finalized (see archzfs wiki).
_module_write_archzfs_repo() {
  if grep -q '\[archzfs\]' /etc/pacman.conf; then
    info "[archzfs] repo already present in /etc/pacman.conf"
    # Update stale archzfs.com URL if still present
    if grep -q 'archzfs.com' /etc/pacman.conf; then
      warn "Updating stale archzfs.com repo URL to GitHub ..."
      local server="$_MODULE_ARCHZFS_SERVER"
      sed -i \
        "s|Server = https://archzfs.com/.*|Server = ${server}|" \
        /etc/pacman.conf
      sed -i '/\[archzfs\]/{n; s/SigLevel.*/SigLevel = Never/}' \
        /etc/pacman.conf 2>/dev/null || true
      info "archzfs repo URL updated."
    fi
    return 0
  fi
  cat >>/etc/pacman.conf <<REPO

# archzfs — ZFS packages for Arch Linux
# Moved from archzfs.com to GitHub Releases in Feb 2026.
# SigLevel=Never is per official archzfs recommendation while signing
# is finalised.
[archzfs]
SigLevel = Never
Server = ${_MODULE_ARCHZFS_SERVER}
REPO
  info "[archzfs] repo added (GitHub, current)."
}

# _module_try_dkms_packages — one archzfs package install; on failure, drop a
# stale testing repo and force-refresh the dbs for the next try
# (zfs_install_dkms).
_module_try_dkms_packages() {
  # stderr hidden as before: the live ISO has no /boot/vmlinuz-*, so
  # pacman's mkinitcpio hook always fails harmlessly here (20261008)
  pacman -S --noconfirm --needed dkms zfs-dkms zfs-utils 2>/dev/null \
    && return 0
  local rc=$?
  zfs_remove_stale_archzfs_testing
  pacman -Syy --noconfirm || true
  return "$rc"
}

# zfs_install_dkms <kernel_version> — DKMS build from source against the EXACT
# running kernel.
#
# The fundamental problem with DKMS on the live ISO:
#   - The ISO ships kernel 6.x.y-arch1-1 with headers already present at
#     /usr/lib/modules/$(uname -r)/build  →  symlink into the source tree.
#   - BUT: pacman -S linux-headers may pull in a DIFFERENT version if the
#     mirror has updated since the ISO was cut. DKMS then refuses to build
#     because the headers version doesn't match the running kernel.
#
# Solution: use the headers that are ALREADY on the ISO for the running
# kernel. The Arch ISO always ships kernel headers at:
#   /usr/lib/modules/$(uname -r)/build
# We install zfs-dkms source, then invoke dkms directly pointing at the
# exact kernel source tree from the ISO — bypassing the version mismatch.
zfs_install_dkms() {
  local kernel_version="$1" kernel_source zfs_version

  info "Falling back to DKMS build for kernel ${kernel_version} ..."
  info "This will take 5–30 minutes depending on CPU speed."
  info "cowspace has been pre-expanded for this build (~900 MB needed)."

  # ZFS_MODULES_DIR defaults to the real path; tests override it to a temp dir.
  kernel_source="${ZFS_MODULES_DIR:-/usr/lib/modules}/${kernel_version}/build"
  _module_ensure_kernel_headers "$kernel_version" "$kernel_source"

  # Install the DKMS framework and the ZFS source package from the archzfs
  # GitHub repo. The repo blips (timeouts, a db/asset size mismatch, Audit
  # Run 20261008): clean up, force-refresh, retry; _retry's markers let the
  # Feature Audit fold a recovered attempt (ADR 0152)
  info "Installing dkms + zfs-dkms from archzfs ..."
  _retry 3 "10,30" -- _module_try_dkms_packages ||
    error "Failed to install zfs-dkms from archzfs.
  Check: pacman -Ss zfs-dkms
  Check: df -h /run/archiso/cowspace  (need ~900 MB free)"

  _module_find_zfs_source_version zfs_version
  info "ZFS source version: ${zfs_version}"

  # Register the module with DKMS if not already registered.
  # `dkms add` is idempotent — safe to call even if already added.
  dkms add -m zfs -v "$zfs_version" 2>/dev/null || true

  _module_build_dkms "$zfs_version" "$kernel_version" "$kernel_source"

  # Install the built module into /lib/modules/<kver>/
  dkms install -m zfs -v "$zfs_version" -k "$kernel_version" ||
    error "DKMS install failed — module built but could not be installed.
  Try manually: dkms install zfs/${zfs_version} -k ${kernel_version}"

  info "DKMS build and install complete (ZFS ${zfs_version})."
}

# _module_ensure_kernel_headers <kernel_version> <kernel_source> — headers
# that match the running kernel exactly. The build directory is
# /usr/lib/modules/<kver>/build (a symlink to the kernel source tree). Three
# scenarios:
#
#   A) /usr/lib/modules/<kver>/build exists  — ISO ships matching headers.
#      Use them directly, no download needed.
#
#   B) Mirror has the exact matching linux-headers version.
#      Install it and the /build symlink will be created.
#
#   C) Mirror has moved on to a newer version (most common case when the
#      ISO is a few days old). The exact version is no longer on the mirror
#      but IS available on the Arch Linux Archive (archive.archlinux.org).
#      Download it from there and install with pacman -U.
_module_ensure_kernel_headers() {
  local kernel_version="$1" kernel_source="$2"
  if [[ -d "$kernel_source" ]]; then
    info "Kernel headers already present: ${kernel_source}"
    return 0
  fi
  warn "Kernel headers not found at ${kernel_source}."
  warn "The running kernel (${kernel_version}) does not match the installed" \
       "headers."

  # Determine the correct headers package name for this kernel flavour
  local headers_package="linux-headers"
  case "$kernel_version" in
  *-lts*)      headers_package="linux-lts-headers"      ;;
  *-hardened*) headers_package="linux-hardened-headers" ;;
  *-zen*)      headers_package="linux-zen-headers"     ;;
  esac

  # The pacman package version for this kernel release (mirror-then-archive
  # fetch is handled by the shared helper). Scenario B (mirror) and C (archive)
  # both collapse into archive_ensure_package_version.
  local package_version
  package_version="$(archive_kernel_version_to_package_version \
    "$kernel_version")"

  info "Need ${headers_package}=${package_version}"
  if archive_ensure_package_version "$headers_package" "$package_version" \
     && [[ -d "$kernel_source" ]]; then
    info "Headers installed (${headers_package}=${package_version})."
  else
    error "Failed to install ${headers_package}=${package_version}.
  Tried the current mirror and the Arch Linux Archive.
  Check the archive manually:
  $(archive_package_url "$headers_package" "$package_version")
  Or, if installed but ${kernel_source} is still missing:
  ls /usr/lib/modules/${kernel_version}/"
  fi
}

# _module_find_zfs_source_version <out-var> — the installed zfs-dkms source
# version. zfs-dkms always installs its source to /usr/src/zfs-<version>/;
# this is more reliable than parsing `dkms status`, whose output format
# changed in DKMS 3.x (Arch ships DKMS 3.x) from:
#   old: "zfs, 2.1.x, ..."
#   new: "zfs/2.1.x, 6.10.x-arch1-1, x86_64: added"
# SC2012 fix: avoid `ls | grep | sort | tail` — use a glob expansion to
# collect zfs-* directories, then version-sort with sort -V.
# ZFS_SRC_DIR defaults to the real path; tests override it to a temp dir.
# Writes <out-var> (not stdout): `error` must abort the installer, which it
# cannot do from inside $( … ).
_module_find_zfs_source_version() {
  local __version_variable="$1" __version
  local -a __source_directories=()
  shopt -s nullglob
  __source_directories=("${ZFS_SRC_DIR:-/usr/src}"/zfs-*)
  shopt -u nullglob
  if ((${#__source_directories[@]} == 0)); then
    error "zfs-dkms installed but /usr/src/zfs-* source directory not found.
  This means the zfs-dkms package did not install correctly.
  Try: pacman -S --noconfirm zfs-dkms && ls /usr/src/zfs-*"
  fi
  # Pick the highest version directory: strip path, sort -V,
  # take last, strip prefix.
  __version="$(printf '%s\n' "${__source_directories[@]##*/}" \
    | sort -V | awk 'END { print }')"
  __version="${__version#zfs-}"
  if [[ -z "$__version" ]]; then
    error "Could not determine ZFS version from /usr/src/zfs-* directory names."
  fi
  printf -v "$__version_variable" '%s' "$__version"
}

# _module_build_dkms <zfs_version> <kernel_version> <kernel_source> — build
# explicitly against the ISO kernel source tree. --kernelsourcedir overrides
# DKMS's default header search so it always uses the headers that match the
# RUNNING kernel, not whatever linux-headers pacman installed (which may be a
# newer version).
_module_build_dkms() {
  local zfs_version="$1" kernel_version="$2" kernel_source="$3"
  local makelog
  makelog="/var/lib/dkms/zfs/${zfs_version}/${kernel_version}/$(uname -m)"
  makelog+="/log/make.log"
  info "Building ZFS ${zfs_version} against kernel ${kernel_version} ..."
  info "Build log:" \
       "$makelog"
  dkms build -m zfs -v "$zfs_version" -k "$kernel_version" \
    --kernelsourcedir "$kernel_source" && return 0

  echo ""
  warn "DKMS build failed. Last 30 lines of make.log:"
  echo "─────────────────────────────────────────────"
  local missing="(log not found at ${makelog})"
  tail -30 "$makelog" 2>/dev/null || echo "$missing"  # readability-ok: tail
  echo "─────────────────────────────────────────────"
  echo ""
  error "DKMS build failed for ZFS ${zfs_version} / kernel ${kernel_version}.
  The most common cause is a ZFS version that does not yet support this kernel.
  Running kernel : ${kernel_version}
  ZFS source     : ${zfs_version}
  Full log       : ${makelog}
  Possible fixes :
    1. Use an Arch ISO with a kernel that archzfs already tracks.
       Check supported kernels:
       https://github.com/archzfs/archzfs/releases/tag/experimental
    2. Wait for archzfs to release a build for kernel ${kernel_version}.
    3. Try manually:
       dkms build zfs/${zfs_version} -k ${kernel_version} --kernelsourcedir ${kernel_source}"
}

zfs_load_module() {
  section "Loading ZFS Kernel Module"

  if lsmod | grep -q '^zfs '; then
    info "ZFS module already loaded."
    return
  fi

  local kernel_version
  kernel_version="$(uname -r)"

  # Rebuild module index so the kernel finds the newly compiled .ko
  info "Running depmod..."
  depmod -a

  info "Loading ZFS module..."
  modprobe zfs || error "modprobe zfs failed for kernel ${kernel_version}.
  DKMS should have built the module for this exact kernel — check the build log:
    /var/lib/dkms/zfs/*/$(uname -r)/$(uname -m)/log/make.log
  Or re-run: ./01-bootstrap-zfs.sh"

  local zfs_version
  zfs_version="$(modinfo zfs 2>/dev/null | awk '/^version:/{print $2}')"
  info "ZFS module loaded. Version: ${zfs_version:-unknown}"
}
