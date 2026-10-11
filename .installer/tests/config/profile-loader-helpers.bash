# profile-loader-helpers.bash — shared setup for the profile-loader-*.bats parts
# Tests for .installer/lib/config/profile-loader.sh — Profile Loader + closed-schema
# validation + transient migration assembler (ADR 0036, issue
# unified-host-profile/01).
#
# Behaviour under test (external only — the effective config a loader
# produces, the errors a validator emits), never internal structure:
#   1. profile_loader_load merges a real host profile.jsonc with core.
#   2. The loader reads ONLY profile.jsonc — a sibling legacy config.jsonc
#      is ignored, and a missing host profile.jsonc yields core-only (rc 1),
#      never a synthesized config (the transient scaffold is gone, issue 10).
#   3. The user path merges user profile.jsonc + user core.
#   4. Closed-schema validation rejects unknown keys at any depth (top
#      level, nested objects, arrays-of-objects), in host profile + core,
#      user profile + core, and program config.jsonc, reporting the
#      offending path before any disk-touching phase.

setup() {
  TEST_DIR="$(mktemp -d)"
  export INSTALLER_DIR="$TEST_DIR"

  info()    { :; }
  warn()    { :; }
  error()   { echo "[error] $*" >&2; return 1; }
  section() { :; }
  export -f info warn error section

  # shellcheck source=../../lib/config/profile-loader.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/profile-loader.sh"
}

teardown() { rm -rf "$TEST_DIR"; }

write_jsonc() {
  local path="$1" content="$2"
  mkdir -p "${path%/*}"
  printf '%s\n' "$content" > "$path"
}

