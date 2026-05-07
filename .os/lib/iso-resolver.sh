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
#         - the HEAD redirect cannot be resolved
#         - the download fails
#
#       No checksum verification — pacstrap will surface a corrupted ISO at
#       use time, and the cost of GPG/sha256 plumbing is not worth the win.
#
# Test seam:
#   _iso_resolver_resolve_url URL
#       Echo the final, redirect-followed URL of the ISO. Default
#       implementation uses `curl`. Tests override this function to return a
#       deterministic URL without hitting the network.
#
#   _iso_resolver_download URL DEST
#       Fetch URL into DEST atomically. Default implementation uses `curl`.
#       Tests override this function to simulate cache-miss without a real
#       download.
# =============================================================================

# Latest-ISO redirect target. Always resolves to a versioned filename of the
# form `archlinux-YYYY.MM.DD-x86_64.iso` on a chosen mirror.
ISO_RESOLVER_LATEST_URL="https://archlinux.org/iso/latest/archlinux-x86_64.iso"

# ── Internal seams (override in tests) ───────────────────────────────────────

_iso_resolver_resolve_url() {
  local url="$1"
  # -s silent, -I HEAD, -L follow redirects, -o /dev/null discard headers,
  # -w '%{url_effective}' print the final URL after all redirects.
  curl -sILo /dev/null -w '%{url_effective}' "$url"
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
  final_url="$(_iso_resolver_resolve_url "$ISO_RESOLVER_LATEST_URL")" || {
    echo "iso-resolver: HEAD failed for $ISO_RESOLVER_LATEST_URL" >&2
    return 1
  }
  [[ -n "$final_url" ]] || {
    echo "iso-resolver: empty redirect from $ISO_RESOLVER_LATEST_URL" >&2
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

  _iso_resolver_download "$ISO_RESOLVER_LATEST_URL" "$target" || {
    echo "iso-resolver: download failed: $ISO_RESOLVER_LATEST_URL → $target" >&2
    return 1
  }
  printf '%s\n' "$target"
}
