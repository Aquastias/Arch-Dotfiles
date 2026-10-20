#!/usr/bin/env bats
# Tests: login-shell derived set (split from resolver-derived-sets.bats;
# shared setup in resolver-helpers.bash)

load resolver-helpers

@test "changing a user's login shell changes the shell package" {
  local test_directory; test_directory="$(mktemp -d)"
  mkdir -p "$test_directory/users/core" "$test_directory/users/alice"
  printf '{"shell":"/bin/zsh"}\n'  > "$test_directory/users/core/profile.jsonc"
  printf '{"shell":"/bin/fish"}\n' > "$test_directory/users/alice/profile.jsonc"
  INSTALLER_DIR="$test_directory" run bash -c "
    source '$BATS_TEST_DIRNAME/../../lib/common.sh'
    source '$BATS_TEST_DIRNAME/../../lib/packages/package-resolver.sh'
    package_resolver_resolve '{\"users\":[\"alice\"]}' \
      | awk -F'\t' '\$1 == \"login-shell\" { print \$3 }'"
  [ "$output" = "fish" ]
  rm -rf "$test_directory"
}

@test "a VM user's shell is read from users/vm/<name>" {
  # Every other loader falls back to users/vm/; this one did not, so VM
  # users reported User Core's shell.
  local test_directory; test_directory="$(mktemp -d)"
  mkdir -p "$test_directory/users/core" "$test_directory/users/vm/tester"
  printf '{"shell":"/bin/bash"}\n' > "$test_directory/users/core/profile.jsonc"
  printf '{"shell":"/bin/fish"}\n' \
    > "$test_directory/users/vm/tester/profile.jsonc"
  INSTALLER_DIR="$test_directory" run bash -c "
    source '$BATS_TEST_DIRNAME/../../lib/common.sh'
    source '$BATS_TEST_DIRNAME/../../lib/packages/package-resolver.sh'
    package_resolver_resolve '{\"users\":[\"tester\"]}' \
      | awk -F'\t' '\$1 == \"login-shell\" { print \$3 }'"
  [ "$output" = "fish" ]
  rm -rf "$test_directory"
}

@test "a user with no profile falls back to User Core's shell" {
  local test_directory; test_directory="$(mktemp -d)"
  mkdir -p "$test_directory/users/core"
  printf '{"shell":"/bin/zsh"}\n' > "$test_directory/users/core/profile.jsonc"
  INSTALLER_DIR="$test_directory" run bash -c "
    source '$BATS_TEST_DIRNAME/../../lib/common.sh'
    source '$BATS_TEST_DIRNAME/../../lib/packages/package-resolver.sh'
    package_resolver_resolve '{\"users\":[\"bob\"]}' \
      | awk -F'\t' '\$1 == \"login-shell\" { print \$3 }'"
  [ "$output" = "zsh" ]
  rm -rf "$test_directory"
}
