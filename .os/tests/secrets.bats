#!/usr/bin/env bats
# Tests for lib/secrets.sh — Secrets Module

setup() {
  TEST_DIR="$(mktemp -d)"
  export OS_DIR="$TEST_DIR"
  export INSTALL_STATE="$TEST_DIR/install-state.json"
  printf '{}' > "$INSTALL_STATE"

  mkdir -p "$TEST_DIR/bin"

  # Redirect mktemp output into TEST_DIR so teardown cleans everything up
  printf '#!/usr/bin/env bash\n/usr/bin/mktemp "$@" -p "%s"\n' \
    "$TEST_DIR" > "$TEST_DIR/bin/mktemp"

  printf '#!/usr/bin/env bash\ntouch "%s/mount_called"\nexit 0\n' \
    "$TEST_DIR" > "$TEST_DIR/bin/mount"
  printf '#!/usr/bin/env bash\ntouch "%s/umount_called"\nexit 0\n' \
    "$TEST_DIR" > "$TEST_DIR/bin/umount"

  chmod +x "$TEST_DIR/bin/mktemp" "$TEST_DIR/bin/mount" "$TEST_DIR/bin/umount"
  PATH="$TEST_DIR/bin:$PATH"

  # shellcheck source=../lib/secrets.sh
  source "$BATS_TEST_DIRNAME/../lib/secrets.sh"
}

teardown() {
  secrets_cleanup 2>/dev/null || true
  rm -rf "$TEST_DIR"
}

_write_age_stub() {
  local ec="${1:-0}"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'output=""; input=""; skip_next=0\n'
    printf 'for arg; do\n'
    printf '  if [[ $skip_next -eq 1 ]]; then output="$arg"; skip_next=0; continue; fi\n'
    printf '  case "$arg" in --decrypt|-d) ;; -o) skip_next=1 ;; *) input="$arg" ;; esac\n'
    printf 'done\n'
    if [[ $ec -eq 0 ]]; then
      printf '[[ -n "$output" ]] && cat "$input" > "$output" || cat "$input"\n'
    fi
    printf 'exit %d\n' "$ec"
  } > "$TEST_DIR/bin/age"
  chmod +x "$TEST_DIR/bin/age"
}

_write_sops_stub() {
  local ec="${1:-0}"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'for arg; do input="$arg"; done\n'
    if [[ $ec -eq 0 ]]; then
      printf 'cat "$input"\n'
    fi
    printf 'exit %d\n' "$ec"
  } > "$TEST_DIR/bin/sops"
  chmod +x "$TEST_DIR/bin/sops"
}

# ── no-op ─────────────────────────────────────────────────────────────────────

@test "no-op when no secrets files exist" {
  run secrets_load "myhostname"
  [ "$status" -eq 0 ]
  [ "$(cat "$INSTALL_STATE")" = '{}' ]
}

# ── correct key: host secrets ─────────────────────────────────────────────────

@test "writes secrets.host path to install-state.json when host secrets.json exists" {
  mkdir -p "$OS_DIR/hosts/myhostname"
  printf '{"root_password":"s3cr3t"}\n' > "$OS_DIR/hosts/myhostname/secrets.json"
  mkdir -p "$TEST_DIR/usb/age"
  printf 'AGE-SECRET-KEY-PLACEHOLDER\n' > "$TEST_DIR/usb/age/key.age"
  export SECRETS_KEY_DEVICE="$TEST_DIR/usb"
  _write_age_stub 0
  _write_sops_stub 0

  run secrets_load "myhostname"
  [ "$status" -eq 0 ]
  local host_path
  host_path="$(jq -r '.secrets.host' "$INSTALL_STATE")"
  [ "$host_path" != "null" ]
  [ -f "$host_path" ]
}

# ── correct key: user secrets ─────────────────────────────────────────────────

@test "writes secrets.users.<name> path to install-state.json when user secrets.json exists" {
  mkdir -p "$OS_DIR/users/alice"
  printf '{"password":"s3cr3t"}\n' > "$OS_DIR/users/alice/secrets.json"
  mkdir -p "$TEST_DIR/usb/age"
  printf 'AGE-SECRET-KEY-PLACEHOLDER\n' > "$TEST_DIR/usb/age/key.age"
  export SECRETS_KEY_DEVICE="$TEST_DIR/usb"
  _write_age_stub 0
  _write_sops_stub 0

  run secrets_load "myhostname"
  [ "$status" -eq 0 ]
  local user_path
  user_path="$(jq -r '.secrets.users.alice' "$INSTALL_STATE")"
  [ "$user_path" != "null" ]
  [ -f "$user_path" ]
}

# ── wrong passphrase ──────────────────────────────────────────────────────────

@test "exits non-zero with clear message when age decryption fails" {
  mkdir -p "$OS_DIR/hosts/myhostname"
  printf '{"root_password":"s3cr3t"}\n' > "$OS_DIR/hosts/myhostname/secrets.json"
  mkdir -p "$TEST_DIR/usb/age"
  printf 'AGE-SECRET-KEY-PLACEHOLDER\n' > "$TEST_DIR/usb/age/key.age"
  export SECRETS_KEY_DEVICE="$TEST_DIR/usb"
  _write_age_stub 1
  _write_sops_stub 0

  run secrets_load "myhostname"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "wrong passphrase" ]]
}

# ── tmpfs cleanup ─────────────────────────────────────────────────────────────

@test "secrets_cleanup unmounts and removes tmpfs after successful load" {
  mkdir -p "$OS_DIR/hosts/myhostname"
  printf '{"root_password":"s3cr3t"}\n' > "$OS_DIR/hosts/myhostname/secrets.json"
  mkdir -p "$TEST_DIR/usb/age"
  printf 'AGE-SECRET-KEY-PLACEHOLDER\n' > "$TEST_DIR/usb/age/key.age"
  export SECRETS_KEY_DEVICE="$TEST_DIR/usb"
  _write_age_stub 0
  _write_sops_stub 0

  secrets_load "myhostname"
  [ -f "$TEST_DIR/mount_called" ]
  local tmpfs_dir="$_SECRETS_TMPFS"
  [ -d "$tmpfs_dir" ]

  secrets_cleanup
  [ -f "$TEST_DIR/umount_called" ]
  [ ! -d "$tmpfs_dir" ]
  [ -z "$_SECRETS_TMPFS" ]
}
