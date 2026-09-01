#!/usr/bin/env bash
# =============================================================================
# lib/packages/iso-resolver.sh — Arch ISO resolver (latest, or archzfs-compatible)
# =============================================================================
# Public:
#
#   iso_resolver_get DOWNLOADS_DIR
#       Resolve + download the *latest* Arch x86_64 ISO (reusing a cached copy).
#       Prints the ISO path on stdout. Source: geo.mirror.pkgbuild.com
#       (archlinux.org/iso 403s); the `archlinux-x86_64.iso` symlink 200s with no
#       Location header, so the resolver scrapes the directory listing.
#
#   iso_resolver_get_zfs_compatible DOWNLOADS_DIR
#       Resolve + download the newest archived ISO whose kernel matches one
#       archzfs has a prebuilt zfs-linux for — needed when the latest ISO's
#       kernel outruns archzfs (the DKMS path fails otherwise). Source:
#       archive.archlinux.org, walked newest-first. Match rule: ISO kernel
#       major.minor == an archzfs-supported major.minor (same API surface, so
#       DKMS builds even if patchlevels differ). Non-zero if archzfs lists none
#       or no archived ISO matches. Downloads only; sha256 is verified by
#       iso_resolver_verify_sha256 (ADR 0023).
#
# Dependencies: curl, jq, grep. Test seams (overridable in bats after sourcing):
#   _iso_resolver_resolve_url DIR_URL     — latest ISO URL (HTTP GET + grep)
#   _iso_resolver_fetch_archzfs_kernels   — one major.minor/line archzfs prebuilt
#   _iso_resolver_fetch_arch_releases     — raw releng releases JSON
#   _iso_resolver_download URL DEST       — atomic fetch (curl)
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

  # 01-bootstrap-zfs builds ZFS via DKMS against the ISO's OWN headers (the
  # prebuilt is almost never installed), so an ISO is usable whenever its kernel
  # is not NEWER than the newest kernel archzfs's ZFS source supports — the
  # prebuilt kernels give that ceiling. Matching only an exact prebuilt version
  # wrongly rejected a perfectly DKMS-buildable older ISO (e.g. archzfs at 7.2
  # while the newest published ISO is still 7.1), stalling every ZFS install
  # between an archzfs bump and the next monthly ISO.
  local max_mm
  max_mm="$(printf '%s\n' "$kernels_text" | sort -V | tail -1)"
  [[ -n "$max_mm" ]] || return 1

  # Walk releases newest-first; pick the first AVAILABLE one whose kernel
  # major.minor is <= the ceiling, compared numerically (so 6.190 does not
  # slip under a 6.19 cap, and 6.9 < 6.19).
  local picked
  picked="$(jq -r --arg max "$max_mm" '
    ($max | split(".") | map(tonumber)) as $cap
    | .releases
    | map(select(.available == true))
    | map(select(
        (.kernel_version | split(".") | map(tonumber)) as $k
        | ($k[0] < $cap[0]) or ($k[0] == $cap[0] and $k[1] <= $cap[1])
      ))
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
