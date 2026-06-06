#!/usr/bin/env bash
# =============================================================================
# lib/packages/iso-resolver.sh — Arch ISO resolver (latest, or archzfs-compatible)
# =============================================================================
# Public:
#
#   iso_resolver_get DOWNLOADS_DIR
#       Resolve and download the *latest* Arch x86_64 ISO. Reuses a cached
#       copy if one is already in DOWNLOADS_DIR. Prints the absolute path
#       of the usable ISO file on stdout.
#
#       Source: geo.mirror.pkgbuild.com (archlinux.org/iso returns 403).
#       The mirror exposes `archlinux-x86_64.iso` as a 200-OK symlink with
#       no Location header, so the resolver scrapes the directory listing
#       to find the versioned filename.
#
#   iso_resolver_get_zfs_compatible DOWNLOADS_DIR
#       Resolve and download the *newest available* archived ISO whose
#       kernel matches a kernel archzfs has prebuilt zfs-linux for. Use
#       this when the latest ISO has a kernel newer than archzfs supports
#       — the installer's DKMS path will fail without a matching prebuilt.
#
#       Source: archive.archlinux.org keeps every monthly ISO; the picker
#       walks releases newest-first and returns the first match.
#
#       Compatibility rule: the ISO's kernel major.minor must equal an
#       archzfs-supported major.minor (e.g. archzfs `6.19.14` matches ISO
#       `6.19.x`). Same major.minor means same upstream kernel API surface
#       — DKMS for ZFS 2.4.1 then builds successfully against the headers
#       even if the patchlevels differ.
#
#       Returns non-zero if archzfs lists no supported kernels (e.g. API
#       outage), or if no available archived ISO matches.
#
#       No checksum verification — pacstrap will surface a corrupted ISO
#       at use time, and the cost of GPG/sha256 plumbing is not worth the
#       win.
#
# Dependencies: curl, jq, grep. Tests stub the network seams.
#
# Test seams (each function is overridable in bats by re-defining it after
# sourcing this module):
#
#   _iso_resolver_resolve_url DIR_URL
#       Echo the full URL of the latest Arch x86_64 ISO. Default
#       implementation HTTP-GETs DIR_URL and greps for the versioned
#       filename.
#
#   _iso_resolver_fetch_archzfs_kernels
#       Echo one `major.minor` per line for each kernel archzfs has a
#       prebuilt zfs-linux package for. Default implementation queries the
#       archzfs `experimental` GitHub release.
#
#   _iso_resolver_fetch_arch_releases
#       Echo the raw releases JSON from archlinux.org/releng. Default
#       implementation fetches the canonical URL.
#
#   _iso_resolver_download URL DEST
#       Fetch URL into DEST atomically. Default implementation uses curl.
# =============================================================================

# Directory URL whose listing contains the versioned latest ISO file.
ISO_RESOLVER_LATEST_DIR="https://geo.mirror.pkgbuild.com/iso/latest/"

# archive.archlinux.org keeps every monthly ISO indefinitely. The releases
# JSON below returns iso_url paths relative to this host.
ISO_RESOLVER_ARCHIVE_BASE="https://archive.archlinux.org"

# Official Arch releng releases manifest. One entry per monthly ISO with
# kernel_version, iso_url, and an `available` flag.
ISO_RESOLVER_ARCH_RELEASES_JSON="https://archlinux.org/releng/releases/json/"

# archzfs experimental release — the source of truth for which kernels
# currently have a prebuilt zfs-linux package.
ISO_RESOLVER_ARCHZFS_API=\
"https://api.github.com/repos/archzfs/archzfs/releases/tags/experimental"

# Pattern matching the versioned filename Arch publishes
# (e.g. `archlinux-2026.05.01-x86_64.iso`).
ISO_RESOLVER_FILENAME_REGEX='archlinux-[0-9]+\.[0-9]+\.[0-9]+-x86_64\.iso'

# ── Internal seams (override in tests) ───────────────────────────────────────

_iso_resolver_resolve_url() {
  local dir_url="$1"
  dir_url="${dir_url%/}"

  local listing
  listing="$(curl -fsSL "$dir_url/" 2>/dev/null)" || return 1

  local filename
  filename="$(echo "$listing" \
    | grep -oE "$ISO_RESOLVER_FILENAME_REGEX" | head -1)"
  [[ -n "$filename" ]] || return 1

  printf '%s/%s\n' "$dir_url" "$filename"
}

_iso_resolver_fetch_archzfs_kernels() {
  # Asset names look like:
  #   zfs-linux-2.4.1_6.19.14.arch1.1-1-x86_64.pkg.tar.zst
  # We extract the kernel major.minor — `6.19` here.
  curl -fsSL "$ISO_RESOLVER_ARCHZFS_API" 2>/dev/null |
    jq -r '.assets[]?.name
      | select(test("^zfs-linux-[0-9.]+_[0-9]+\\.[0-9]+\\.[0-9]+\\.arch"))' |
    sed -E 's/^zfs-linux-[0-9.]+_([0-9]+\.[0-9]+)\.[0-9]+\.arch.*/\1/' |
    sort -uV
}

_iso_resolver_fetch_arch_releases() {
  curl -fsSL "$ISO_RESOLVER_ARCH_RELEASES_JSON" 2>/dev/null
}

_iso_resolver_fetch_sha256sums() {
  # Echo the release's sha256sums.txt. The releng JSON's per-release
  # sha256_sum is null for archived releases, so the per-release sums file
  # on the archive is the authoritative source (see ADR 0023).
  local version="$1"
  curl -fsSL \
    "${ISO_RESOLVER_ARCHIVE_BASE}/iso/${version}/sha256sums.txt" 2>/dev/null
}

_iso_resolver_download() {
  local url="$1" dest="$2"
  local tmp="${dest}.partial"
  if curl -fSL --retry 2 -o "$tmp" "$url"; then
    mv -f "$tmp" "$dest"
    return 0
  fi
  rm -f "$tmp"
  return 1
}

# ── Internal: pick newest available release matching kernel set ──────────────
# Args:
#   $1 — newline-separated archzfs-supported kernel major.minor list
#   $2 — releases JSON text
# Output:
#   The chosen iso_url path (relative, e.g. /iso/2026.04.01/...iso) on stdout.
# Exit:
#   0 on match, 1 if no available release's kernel matches.

_iso_resolver_pick_compatible_release() {
  local kernels_text="$1" releases_json="$2"

  [[ -n "$kernels_text" ]] || return 1
  [[ -n "$releases_json" ]] || return 1

  # Build a `^(6\.19|6\.18)\.` regex that anchors to the kernel string's
  # start and forces a literal dot after the major.minor — this prevents
  # `6.19` from matching `6.190.x`.
  local k_alt
  k_alt="$(echo "$kernels_text" \
    | sed 's/\./\\./g' | tr '\n' '|' | sed 's/|$//')"
  [[ -n "$k_alt" ]] || return 1

  local picked
  picked="$(jq -r --arg re "^($k_alt)\\." '
    .releases
    | map(select(.available == true))
    | map(select(.kernel_version | test($re)))
    | (.[0].iso_url // empty)
  ' <<<"$releases_json")"

  [[ -n "$picked" ]] || return 1
  printf '%s\n' "$picked"
}

# ── Public API: latest ISO ───────────────────────────────────────────────────

iso_resolver_get() {
  local downloads_dir="$1"
  [[ -d "$downloads_dir" ]] || {
    echo "iso-resolver: downloads directory does not exist: $downloads_dir" >&2
    return 1
  }

  local final_url
  final_url="$(_iso_resolver_resolve_url "$ISO_RESOLVER_LATEST_DIR")" || {
    echo "iso-resolver: lookup failed at $ISO_RESOLVER_LATEST_DIR" >&2
    return 1
  }
  [[ -n "$final_url" ]] || {
    echo "iso-resolver: empty result from $ISO_RESOLVER_LATEST_DIR" >&2
    return 1
  }

  local filename="${final_url##*/}"
  [[ "$filename" == *.iso ]] || {
    echo "iso-resolver: resolved URL has no .iso filename: $final_url" >&2
    return 1
  }

  local target="${downloads_dir%/}/${filename}"
  if [[ -f "$target" ]]; then
    printf '%s\n' "$target"
    return 0
  fi

  _iso_resolver_download "$final_url" "$target" || {
    echo "iso-resolver: download failed: $final_url → $target" >&2
    return 1
  }
  printf '%s\n' "$target"
}

# ── Public API: latest archzfs-compatible ISO ────────────────────────────────

iso_resolver_get_zfs_compatible() {
  local downloads_dir="$1"
  [[ -d "$downloads_dir" ]] || {
    echo "iso-resolver: downloads directory does not exist: $downloads_dir" >&2
    return 1
  }

  local kernels
  kernels="$(_iso_resolver_fetch_archzfs_kernels)" || {
    echo "iso-resolver: archzfs supported-kernel lookup failed" >&2
    return 1
  }
  [[ -n "$kernels" ]] || {
    echo "iso-resolver: no archzfs prebuilt kernels detected" \
         "— refusing to guess" >&2
    return 1
  }

  local releases_json
  releases_json="$(_iso_resolver_fetch_arch_releases)" || {
    echo "iso-resolver: archlinux.org releases lookup failed" >&2
    return 1
  }
  [[ -n "$releases_json" ]] || {
    echo "iso-resolver: empty releases JSON from archlinux.org" >&2
    return 1
  }

  local iso_path
  iso_path="$(_iso_resolver_pick_compatible_release \
    "$kernels" "$releases_json")" || {
    local k_csv
    k_csv="$(echo "$kernels" | tr '\n' ',' | sed 's/,$//')"
    echo "iso-resolver: no available archived ISO matches" \
         "archzfs kernels: ${k_csv}" >&2
    return 1
  }

  local filename="${iso_path##*/}"
  local full_url="${ISO_RESOLVER_ARCHIVE_BASE}${iso_path}"
  local target="${downloads_dir%/}/${filename}"

  if [[ -f "$target" ]]; then
    printf '%s\n' "$target"
    return 0
  fi

  _iso_resolver_download "$full_url" "$target" || {
    echo "iso-resolver: download failed: $full_url → $target" >&2
    return 1
  }
  printf '%s\n' "$target"
}

# ── Public API: verify a downloaded ISO's sha256 ──────────────────────────────

iso_resolver_verify_sha256() {
  local file="$1"

  local filename version sums expected actual
  filename="${file##*/}"
  version="$(sed -E 's/^archlinux-(.+)-x86_64\.iso$/\1/' <<<"$filename")"

  if ! sums="$(_iso_resolver_fetch_sha256sums "$version")"; then
    echo "iso-resolver: failed to fetch sha256sums for ${filename}" >&2
    return 1
  fi
  expected="$(awk -v f="$filename" '$2 == f {print $1; exit}' <<<"$sums")"
  [[ -n "$expected" ]] || {
    echo "iso-resolver: no sha256sums line for ${filename}" >&2
    return 1
  }
  actual="$(sha256sum "$file" | awk '{print $1}')"

  if [[ "$actual" != "$expected" ]]; then
    echo "iso-resolver: sha256 mismatch for ${filename}" >&2
    echo "  expected: ${expected}" >&2
    echo "  actual:   ${actual}" >&2
    return 1
  fi
}
