#!/usr/bin/env bats
# Tests for the Runner's Security & Backup Extras union — M4, ADR 0041
# (_profiles_resolve_post_install in lib/profiles/runner.sh).
#
# Pure list-shaper: resolves the host post_install.{security,backup} object to
# its Program names (via post_install_programs), then unions them into the
# Primary User's program list — the user's declared programs first (their
# order), then the resolved extras not already present (canonical order). A
# tool in both installs once. Asserts on the resolved list; paru never runs.

setup() {
  error() { echo "[error] $*" >&2; return 1; }
  export -f error

  # shellcheck source=../../lib/config/post-install.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/post-install.sh"
  # shellcheck source=../../lib/profiles/runner.sh
  source "$BATS_TEST_DIRNAME/../../lib/profiles/runner.sh"
}

@test "a tool in both post_install and the user's programs installs once" {
  run _profiles_resolve_post_install "$(post_install_default)" firewalld docker
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '%s\n' firewalld docker clamav rkhunter apparmor \
    zfs-auto-snapshot borg)" ]
}

@test "no user programs → the resolved extras in canonical order" {
  run _profiles_resolve_post_install '{"security":{"firewall":"ufw","rootkit":true}}'
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '%s\n' ufw rkhunter)" ]
}

@test "empty post_install passes the user's programs through unchanged" {
  run _profiles_resolve_post_install '{}' docker searxng
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '%s\n' docker searxng)" ]
}

@test "empty selection and no users → empty list" {
  run _profiles_resolve_post_install '{}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
