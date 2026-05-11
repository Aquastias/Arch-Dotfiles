#!/usr/bin/env bash
# =============================================================================
# lib/jsonc.sh — JSONC parsing primitives
# =============================================================================
# Pure — no dependencies, no error() calls.
# Sourced by lib/common.sh and lib/configs.sh.
# =============================================================================

# jsonc_strip FILE → strips // line-comments, emits plain JSON on stdout.
jsonc_strip() {
  sed \
    -e 's|[[:space:]]*//$||' \
    -e 's|[[:space:]]//[^"]*$||' \
    -e '/^[[:space:]]*\/\//d' \
    "$1" 2>/dev/null
}

# jsonc FILE → alias for jsonc_strip; retained for callers predating the rename.
jsonc() { jsonc_strip "$1"; }

# jsonc_read FILE PATH → raw jq read; jq null for missing fields.
jsonc_read() { jsonc_strip "$1" | jq -r "$2"; }

# jsonc_read_opt FILE PATH → empty string if field is missing or null.
jsonc_read_opt() { jsonc_strip "$1" | jq -r "$2 // empty"; }
