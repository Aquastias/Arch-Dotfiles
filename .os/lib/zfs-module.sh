#!/usr/bin/env bash
# =============================================================================
# lib/zfs-module.sh — shared ZFS kernel-module install/load for the live ISO
# =============================================================================
# Single source of truth for getting a working ZFS module on the running
# live-ISO kernel. Sourced by BOTH 01-bootstrap-zfs.sh (the normal path) and
# 03-install.sh (the fallback in lib/zfs-pools.sh, when bootstrap was skipped
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
#   _remove_stale_archzfs_testing — drop a stale [archzfs-testing] pacman block
#   zfs_add_archzfs_repo          — add archzfs repo + signing key (idempotent)
#   zfs_install_dkms <kver>       — DKMS-build ZFS against the EXACT running
#                                   kernel, using the ISO's own headers
#   zfs_load_module               — depmod + modprobe the freshly built module
# =============================================================================

# Guard against double-sourcing (03-install.sh and a future direct source).
[[ -n "${_ZFS_MODULE_SH_SOURCED:-}" ]] && return 0
_ZFS_MODULE_SH_SOURCED=1

_remove_stale_archzfs_testing() {
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

zfs_add_archzfs_repo() {
  section "Adding archzfs Repository"

  # Remove any stale [archzfs-testing] block before touching the DB.
  # pacman -Sy would fail trying to fetch archzfs-testing.db if it's present.
  _remove_stale_archzfs_testing

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
  pacman -Sy --noconfirm archlinux-keyring

  # ── archzfs repository setup ──────────────────────────────────────────────
  # IMPORTANT: archzfs.com went stale in early 2026. The project moved to
  # GitHub Releases. The new repo is actively maintained and ships current
  # ZFS builds (2.4.x as of April 2026).
  # New repo URL:
  # https://github.com/archzfs/archzfs/releases/download/experimental
  # New signing key: 3A9917BF0DED5C13F69AC68FABEC0A1208037BE9

  local ARCHZFS_KEY="3A9917BF0DED5C13F69AC68FABEC0A1208037BE9"
  local ARCHZFS_SERVER=\
"https://github.com/archzfs/archzfs/releases/download/experimental"

  # Import the new archzfs signing key from keyserver
  info "Importing archzfs signing key (${ARCHZFS_KEY:0:16}...)..."
  if ! pacman-key --recv-keys "$ARCHZFS_KEY" 2>/dev/null; then
    pacman-key --keyserver hkps://keyserver.ubuntu.com \
      --recv-keys "$ARCHZFS_KEY" ||
      error "Failed to import archzfs GPG key.
  Try manually: pacman-key --recv-keys ${ARCHZFS_KEY}"
  fi
  pacman-key --lsign-key "$ARCHZFS_KEY"

  # Add [archzfs] repository to pacman.conf if not already present.
  # SigLevel=Never is the current recommendation from the archzfs project
  # while their signing infrastructure is being finalized (see archzfs wiki).
  if grep -q '\[archzfs\]' /etc/pacman.conf; then
    info "[archzfs] repo already present in /etc/pacman.conf"
    # Update stale archzfs.com URL if still present
    if grep -q 'archzfs.com' /etc/pacman.conf; then
      warn "Updating stale archzfs.com repo URL to GitHub ..."
      sed -i "s|Server = https://archzfs.com/.*|Server = ${ARCHZFS_SERVER}|" \
        /etc/pacman.conf
      sed -i '/\[archzfs\]/{n; s/SigLevel.*/SigLevel = Never/}' \
        /etc/pacman.conf 2>/dev/null || true
      info "archzfs repo URL updated."
    fi
  else
    cat >>/etc/pacman.conf <<EOF

# archzfs — ZFS packages for Arch Linux
# Moved from archzfs.com to GitHub Releases in Feb 2026.
# SigLevel=Never is per official archzfs recommendation while signing
# is finalised.
[archzfs]
SigLevel = Never
Server = ${ARCHZFS_SERVER}
EOF
    info "[archzfs] repo added (GitHub, current)."
  fi

  info "Syncing pacman package databases..."
  pacman -Sy --noconfirm # refresh db after adding archzfs
}

zfs_install_dkms() {
  # DKMS build from source against the EXACT running kernel.
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

  local kver="$1"

  info "Falling back to DKMS build for kernel ${kver} ..."
  warn "This will take 5–30 minutes depending on CPU speed."
  info "cowspace has been pre-expanded for this build (~900 MB needed)."

  # ── Locate kernel headers for the EXACT running kernel ──────────────────────
  # DKMS needs headers that match the running kernel version precisely.
  # The build directory is /usr/lib/modules/<kver>/build (a symlink to the
  # kernel source tree). Three scenarios:
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

  # ZFS_MODULES_DIR defaults to the real path; tests override it to a temp dir.
  local kernel_src="${ZFS_MODULES_DIR:-/usr/lib/modules}/${kver}/build"

  if [[ -d "$kernel_src" ]]; then
    info "Kernel headers already present: ${kernel_src}"

  else
    warn "Kernel headers not found at ${kernel_src}."
    warn "The running kernel (${kver}) does not match the installed headers."

    # Determine the correct headers package name for this kernel flavour
    local headers_pkg="linux-headers"
    case "$kver" in
    *-lts*)      headers_pkg="linux-lts-headers"      ;;
    *-hardened*) headers_pkg="linux-hardened-headers" ;;
    *-zen*)      headers_pkg="linux-zen-headers"     ;;
    esac

    # Build the exact pkgver string pacman/archive uses.
    # Arch kernel version strings are like: 6.19.10-arch1-1
    # The package version is:               6.19.10.arch1-1
    # (dot not dash before arch)
    # Convert kernel release string to pacman package version.
    # Kernel: 6.19.10-arch1-1  →  Package: 6.19.10.arch1-1
    # (the hyphen before "arch" becomes a dot in the package version)
    local pkg_ver
    pkg_ver="${kver/-arch/.arch}"

    info "Need ${headers_pkg}=${pkg_ver}"

    # ── Scenario B: try the current mirror first ──────────────────────────
    info "Attempting to install ${headers_pkg} from current mirror ..."
    if pacman -S --noconfirm --needed "${headers_pkg}=${pkg_ver}" 2>/dev/null &&
      [[ -d "$kernel_src" ]]; then
      info "Headers installed from mirror."

    else
      # ── Scenario C: fetch exact version from Arch Linux Archive ──────
      warn "Exact version not on mirror. Fetching from Arch Linux Archive..."
      warn "URL: https://archive.archlinux.org/packages/"

      # The archive path uses the package name's first letter as a subdir.
      # linux-headers →
      # l/linux-headers/linux-headers-6.19.10.arch1-1-x86_64.pkg.tar.zst
      local arch="x86_64"
      local pkg_file="${headers_pkg}-${pkg_ver}-${arch}.pkg.tar.zst"
      local first_char="${headers_pkg:0:1}"
      local archive_base="https://archive.archlinux.org/packages"
      local archive_url
      archive_url="${archive_base}/${first_char}/${headers_pkg}/${pkg_file}"

      info "Downloading: ${pkg_file}"
      local tmp_pkg="/tmp/${pkg_file}"
      curl -fL --progress-bar "$archive_url" -o "$tmp_pkg" ||
        error "Failed to download headers from Arch Linux Archive.
  URL tried: ${archive_url}
  Check the archive manually:
  https://archive.archlinux.org/packages/l/${headers_pkg}/
  Then install manually: pacman -U /path/to/${pkg_file}"

      info "Installing headers from archive package ..."
      pacman -U --noconfirm "$tmp_pkg" ||
        error "pacman -U failed for ${tmp_pkg}"
      rm -f "$tmp_pkg"

      [[ -d "$kernel_src" ]] ||
        error "Headers installed but ${kernel_src} still missing.
  This should not happen. Check: ls /usr/lib/modules/${kver}/"
      info "Headers installed from Arch Linux Archive."
    fi
  fi

  # Install the DKMS framework and the ZFS source package.
  # Install DKMS framework and ZFS source package from the archzfs GitHub repo.
  info "Installing dkms + zfs-dkms from archzfs ..."
  if ! pacman -S --noconfirm --needed dkms zfs-dkms zfs-utils 2>/dev/null; then
    warn "zfs-dkms install failed. Retrying after cleanup ..."
    _remove_stale_archzfs_testing
    pacman -Sy --noconfirm # refresh DB after cleanup
    pacman -S --noconfirm --needed dkms zfs-dkms zfs-utils ||
      error "Failed to install zfs-dkms from archzfs.
  Check: pacman -Ss zfs-dkms
  Check: df -h /run/archiso/cowspace  (need ~900 MB free)"
  fi

  # Determine the ZFS version from the installed source directory.
  # zfs-dkms always installs its source to /usr/src/zfs-<version>/.
  # This is more reliable than parsing `dkms status`, whose output format
  # changed in DKMS 3.x (Arch ships DKMS 3.x) from:
  #   old: "zfs, 2.1.x, ..."
  #   new: "zfs/2.1.x, 6.10.x-arch1-1, x86_64: added"
  # SC2012 fix: avoid `ls | grep | sort | tail` — use a glob expansion to
  # collect zfs-* directories, then version-sort with sort -V.
  # ZFS_SRC_DIR defaults to the real path; tests override it to a temp dir.
  local zfs_ver
  local -a _zfs_src_dirs=()
  shopt -s nullglob
  _zfs_src_dirs=("${ZFS_SRC_DIR:-/usr/src}"/zfs-*)
  shopt -u nullglob
  if ((${#_zfs_src_dirs[@]} == 0)); then
    error "zfs-dkms installed but /usr/src/zfs-* source directory not found.
  This means the zfs-dkms package did not install correctly.
  Try: pacman -S --noconfirm zfs-dkms && ls /usr/src/zfs-*"
  fi
  # Pick the highest version directory: strip path, sort -V,
  # take last, strip prefix.
  zfs_ver="$(printf '%s\n' "${_zfs_src_dirs[@]##*/}" | sort -V | tail -1)"
  zfs_ver="${zfs_ver#zfs-}"
  if [[ -z "$zfs_ver" ]]; then
    error "Could not determine ZFS version from /usr/src/zfs-* directory names."
  fi
  info "ZFS source version: ${zfs_ver}"

  # Register the module with DKMS if not already registered.
  # `dkms add` is idempotent — safe to call even if already added.
  dkms add -m zfs -v "$zfs_ver" 2>/dev/null || true

  # Build explicitly against the ISO kernel source tree.
  # --kernelsourcedir overrides DKMS's default header search so it always
  # uses the headers that match the RUNNING kernel, not whatever linux-headers
  # pacman installed (which may be a newer version).
  info "Building ZFS ${zfs_ver} against kernel ${kver} ..."
  info "Build log:" \
       "/var/lib/dkms/zfs/${zfs_ver}/${kver}/$(uname -m)/log/make.log"

  if ! dkms build -m zfs -v "$zfs_ver" -k "$kver" \
         --kernelsourcedir "$kernel_src"; then
    local makelog
    makelog="/var/lib/dkms/zfs/${zfs_ver}/${kver}/$(uname -m)/log/make.log"
    echo ""
    warn "DKMS build failed. Last 30 lines of make.log:"
    echo "─────────────────────────────────────────────"
    tail -30 "$makelog" 2>/dev/null || echo "(log not found at ${makelog})"
    echo "─────────────────────────────────────────────"
    echo ""
    error "DKMS build failed for ZFS ${zfs_ver} / kernel ${kver}.
  The most common cause is a ZFS version that does not yet support this kernel.
  Running kernel : ${kver}
  ZFS source     : ${zfs_ver}
  Full log       : ${makelog}
  Possible fixes :
    1. Use an Arch ISO with a kernel that archzfs already tracks.
       Check supported kernels:
       https://github.com/archzfs/archzfs/releases/tag/experimental
    2. Wait for archzfs to release a build for kernel ${kver}.
    3. Try manually:
       dkms build zfs/${zfs_ver} -k ${kver} --kernelsourcedir ${kernel_src}"
  fi

  # Install the built module into /lib/modules/<kver>/
  dkms install -m zfs -v "$zfs_ver" -k "$kver" ||
    error "DKMS install failed — module built but could not be installed.
  Try manually: dkms install zfs/${zfs_ver} -k ${kver}"

  info "DKMS build and install complete (ZFS ${zfs_ver})."
}

zfs_load_module() {
  section "Loading ZFS Kernel Module"

  if lsmod | grep -q '^zfs '; then
    info "ZFS module already loaded."
    return
  fi

  local kver
  kver="$(uname -r)"

  # Rebuild module index so the kernel finds the newly compiled .ko
  info "Running depmod..."
  depmod -a

  info "Loading ZFS module..."
  modprobe zfs || error "modprobe zfs failed for kernel ${kver}.
  DKMS should have built the module for this exact kernel — check the build log:
    /var/lib/dkms/zfs/*/$(uname -r)/$(uname -m)/log/make.log
  Or re-run: ./01-bootstrap-zfs.sh"

  local zver
  zver="$(modinfo zfs 2>/dev/null | awk '/^version:/{print $2}')"
  info "ZFS module loaded. Version: ${zver:-unknown}"
}
