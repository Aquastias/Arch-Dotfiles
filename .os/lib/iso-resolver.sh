#!/usr/bin/env bash
# =============================================================================
# lib/iso-resolver.sh — Latest-Arch-ISO resolver
# =============================================================================
# Public:
#   iso_resolver_get DOWNLOADS_DIR
#       Resolve the canonical filename of the current Arch Linux x86_64 ISO,
#       and either reuse a copy already in DOWNLOADS_DIR or download a fresh
#       one. Prints the absolute path of the usable ISO file on stdout.
#
#       Returns non-zero if:
#         - DOWNLOADS_DIR does not exist (the module does not create it)
#         - the latest-version lookup fails or returns no .iso filename
#         - the download fails
#
#       No checksum verification — pacstrap will surface a corrupted ISO at
#       use time, and the cost of GPG/sha256 plumbing is not worth the win.
#
# Source mirror:
#   archlinux.org currently returns 403 for /iso/ paths; the geo-routing
#   official mirror geo.mirror.pkgbuild.com serves the same tree. The
#   resolver scrapes its `latest/` directory listing for the versioned
#   filename rather than relying on a redirect, because the mirror exposes
#   `archlinux-x86_64.iso` as a 200-OK symlink with no Location header.
#
# Test seam:
#   _iso_resolver_resolve_url DIR_URL
#       Echo the full URL of the latest Arch x86_64 ISO. Default
#       implementation HTTP-GETs DIR_URL and greps for the versioned ISO
#       filename. Tests override this function to return a deterministic
#       URL without hitting the network.
#
#   _iso_resolver_download URL DEST
#       Fetch URL into DEST atomically. Default implementation uses `curl`.
#       Tests override this function to simulate cache-miss without a real
#       download.
# =============================================================================

# Directory URL whose listing contains the versioned latest ISO file.
ISO_RESOLVER_LATEST_DIR="https://geo.mirror.pkgbuild.com/iso/latest/"

# Pattern matching the versioned filename Arch publishes
# (e.g. `archlinux-2026.05.01-x86_64.iso`).
ISO_RESOLVER_FILENAME_REGEX='archlinux-[0-9]+\.[0-9]+\.[0-9]+-x86_64\.iso'

# ── Internal seams (override in tests) ───────────────────────────────────────

_iso_resolver_resolve_url() {
  local dir_url="$1"
  # Strip trailing slash so the join below produces a single slash.
  dir_url="${dir_url%/}"

  local listing
  listing="$(curl -fsSL "$dir_url/" 2>/dev/null)" || return 1

  local filename
  filename="$(echo "$listing" | grep -oE "$ISO_RESOLVER_FILENAME_REGEX" | head -1)"
  [[ -n "$filename" ]] || return 1

  printf '%s/%s\n' "$dir_url" "$filename"
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

# ── Public API ───────────────────────────────────────────────────────────────

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
