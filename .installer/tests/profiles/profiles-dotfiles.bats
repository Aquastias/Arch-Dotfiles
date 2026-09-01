#!/usr/bin/env bats
# Tests for _profiles_clone_dotfiles. Regression: the mktemp'd clone script is
# root-owned 0600, so it must be made readable before the su'd user runs it —
# else "bash: <tmp>: Permission denied" aborts the install (dotfiles_repo path).

setup() {
  TEST_DIR="$(mktemp -d)"
  export MOUNT_ROOT="$TEST_DIR/mnt"
  mkdir -p "$MOUNT_ROOT" "$TEST_DIR/bin"
  PATH="$TEST_DIR/bin:$PATH"

  info()  { :; }
  warn()  { :; }
  error() { echo "[error] $*" >&2; exit 1; }
  export -f info warn error

  # Stub arch-chroot: emit the heredoc script (its stdin) for inspection.
  printf '#!/usr/bin/env bash\ncat\n' > "$TEST_DIR/bin/arch-chroot"
  chmod +x "$TEST_DIR/bin/arch-chroot"

  # shellcheck source=../../lib/profiles/runner.sh
  source "$BATS_TEST_DIRNAME/../../lib/profiles/runner.sh"
}

teardown() { rm -rf "$TEST_DIR"; }

@test "makes the clone script readable before running it as the user" {
  run _profiles_clone_dotfiles aquastias https://example/repo.git
  [ "$status" -eq 0 ]
  [[ "$output" == *'chmod 0644 "$CLONE_SCRIPT"'* ]]
  # chmod must come BEFORE the su that runs it as the user.
  local chmod_ln su_ln
  chmod_ln="$(grep -n 'chmod 0644' <<<"$output" | head -1 | cut -d: -f1)"
  su_ln="$(grep -n 'su - "\$USER_NAME" -c "bash' <<<"$output" | head -1 \
    | cut -d: -f1)"
  [ -n "$chmod_ln" ] && [ -n "$su_ln" ] && [ "$chmod_ln" -lt "$su_ln" ]
}

@test "no-op when the host declares no dotfiles_repo" {
  run _profiles_clone_dotfiles aquastias ""
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
