#!/usr/bin/env bats
# Tests for profiles.sh secrets wire-up (_profiles_resolve_user_secrets)

setup() {
  TEST_DIR="$(mktemp -d)"
  export MOUNT_ROOT="$TEST_DIR/mnt"
  mkdir -p "$MOUNT_ROOT"

  mkdir -p "$TEST_DIR/bin"
  PATH="$TEST_DIR/bin:$PATH"

  # Stubs for functions sourced from common.sh
  info()  { :; }
  warn()  { :; }
  error() { echo "[error] $*" >&2; exit 1; }
  export -f info warn error

  # shellcheck source=../../lib/profiles/runner.sh
  source "$BATS_TEST_DIRNAME/../../lib/profiles/runner.sh"
}

teardown() { rm -rf "$TEST_DIR"; }

# ── _profiles_resolve_user_secrets ────────────────────────────────────────────

@test "returns chroot path and stages file when user secrets present" {
  local host_sec="$TEST_DIR/alice-secrets.json"
  printf '{"password":"s3cr3t"}\n' > "$host_sec"
  printf '{"secrets":{"users":{"alice":"%s"}}}\n' "$host_sec" \
    > "$MOUNT_ROOT/install-state.json"

  run _profiles_resolve_user_secrets "alice"
  [ "$status" -eq 0 ]
  [ "$output" = "${_PROFILES_RUNTIME_DIR}/secrets/alice-secrets.json" ]
  [ -f "${MOUNT_ROOT}${_PROFILES_RUNTIME_DIR}/secrets/alice-secrets.json" ]
}

@test "returns empty when user has no secrets entry" {
  printf '{"secrets":{"users":{}}}\n' > "$MOUNT_ROOT/install-state.json"

  run _profiles_resolve_user_secrets "alice"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "returns empty when secrets entry points to missing file" {
  printf '{"secrets":{"users":{"alice":"/nonexistent/alice-secrets.json"}}}\n' \
    > "$MOUNT_ROOT/install-state.json"

  run _profiles_resolve_user_secrets "alice"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "returns empty when install-state.json absent" {
  run _profiles_resolve_user_secrets "alice"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ── _profiles_host_uses_secrets ───────────────────────────────────────────────

@test "_profiles_host_uses_secrets is false for empty install-state" {
  printf '{}\n' > "$MOUNT_ROOT/install-state.json"

  run _profiles_host_uses_secrets "$MOUNT_ROOT/install-state.json"
  [ "$status" -eq 1 ]
}

@test "_profiles_host_uses_secrets is true when .secrets.host is set" {
  printf '{"secrets":{"host":"/run/x/host-secrets.json"}}\n' \
    > "$MOUNT_ROOT/install-state.json"

  run _profiles_host_uses_secrets "$MOUNT_ROOT/install-state.json"
  [ "$status" -eq 0 ]
}

@test "_profiles_host_uses_secrets is true when .secrets.users non-empty" {
  printf '{"secrets":{"users":{"alice":"/run/x/alice.json"}}}\n' \
    > "$MOUNT_ROOT/install-state.json"

  run _profiles_host_uses_secrets "$MOUNT_ROOT/install-state.json"
  [ "$status" -eq 0 ]
}

@test "_profiles_host_uses_secrets is false for empty .secrets.users map" {
  printf '{"secrets":{"users":{}}}\n' > "$MOUNT_ROOT/install-state.json"

  run _profiles_host_uses_secrets "$MOUNT_ROOT/install-state.json"
  [ "$status" -eq 1 ]
}

@test "_profiles_host_uses_secrets is false when state file is missing" {
  run _profiles_host_uses_secrets "$MOUNT_ROOT/nonexistent.json"
  [ "$status" -eq 1 ]
}

# ── _profiles_sops_selection ──────────────────────────────────────────────────

@test "_profiles_sops_selection appends sops when active and absent" {
  run _profiles_sops_selection 1 cups base
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'cups\nbase\nsops')" ]
}

@test "_profiles_sops_selection dedupes when sops already declared" {
  run _profiles_sops_selection 1 sops cups
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'sops\ncups')" ]
}

@test "_profiles_sops_selection leaves list untouched when inactive" {
  run _profiles_sops_selection 0 cups base
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'cups\nbase')" ]
}

@test "_profiles_sops_selection yields just sops when active and list empty" {
  run _profiles_sops_selection 1
  [ "$status" -eq 0 ]
  [ "$output" = "sops" ]
}

# ── _profiles_create_user wire-up ─────────────────────────────────────────────

_setup_archroot_capture() {
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@" > "%s/archroot_args"\n' \
    "$TEST_DIR" > "$TEST_DIR/bin/arch-chroot"
  chmod +x "$TEST_DIR/bin/arch-chroot"
}

@test "_profiles_create_user passes secrets path as 5th arg when present" {
  _setup_archroot_capture
  local host_sec="$TEST_DIR/alice-secrets.json"
  printf '{"password":"s3cr3t"}\n' > "$host_sec"
  printf '{"secrets":{"users":{"alice":"%s"}}}\n' "$host_sec" \
    > "$MOUNT_ROOT/install-state.json"

  _profiles_create_user "alice" '{"shell":"/bin/bash","sudo":false}'
  grep -qF "${_PROFILES_RUNTIME_DIR}/secrets/alice-secrets.json" \
    "$TEST_DIR/archroot_args"
}

@test "_profiles_create_user omits secrets arg when user has no entry" {
  _setup_archroot_capture
  printf '{"secrets":{"users":{}}}\n' > "$MOUNT_ROOT/install-state.json"

  _profiles_create_user "alice" '{"shell":"/bin/bash","sudo":false}'
  # last arg should be the default password, not a path
  local last_arg
  last_arg="$(tail -1 "$TEST_DIR/archroot_args")"
  [ "$last_arg" = "$_PROFILES_DEFAULT_PASSWORD" ]
}
