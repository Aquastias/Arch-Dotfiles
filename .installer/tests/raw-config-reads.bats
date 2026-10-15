#!/usr/bin/env bats
# Gate for the Raw Config Read Lint (ADR 0154): a field the Install Config
# schema owns is read through the reader, never as a raw `.<path> // <literal>`
# jq read that restates its Install Default.
# The headline test runs the lint against THIS repo; the rest build throwaway
# git repos to prove each rule.

CHECK="$BATS_TEST_DIRNAME/raw-config-reads.sh"

# make_repo: cd into a fresh git repo with a small schema (one row split
# across lines, as the real one does at 80 columns).
make_repo() {
  REPO="$(mktemp -d)"
  cd "$REPO"
  git init -q
  mkdir -p .installer/tests .installer/lib/config
  printf '%s\n' '_INSTALL_CONFIG_SCHEMA=(' \
    '  "bootloader|.options.bootloader|scalar|systemd-boot"' \
    '  "filesystem|.filesystem|scalar|zfs"' \
    '  "users_first|"\' '".users|array|"' ')' \
    > .installer/lib/config/install-config.sh
}
check_repo() {
  git add -A
  run bash -c "cd '$REPO' && bash '$CHECK' $*"
}
teardown() { [[ -n "${REPO:-}" ]] && rm -rf "$REPO"; return 0; }

@test "this repo passes the Raw Config Read Lint" {
  run bash "$CHECK"
  [ "$status" -eq 0 ]
}

@test "catches a new raw read with an inline default" {
  make_repo
  printf 'jq -r %s <<<"$c"\n' "'.options.bootloader // \"grub\"'" \
    > .installer/lib/a.sh
  check_repo
  [ "$status" -ne 0 ]
  [[ "$output" == *"raw config read: .installer/lib/a.sh:1:"* ]]
}

@test "a file reading through the reader passes" {
  make_repo
  printf 'install_config_bootloader\n' > .installer/lib/a.sh
  check_repo
  [ "$status" -eq 0 ]
}

@test "the Install Config Reader itself is exempt" {
  make_repo
  printf 'jq %s\n' "'.options.bootloader // \"x\"'" \
    > .installer/lib/config/install-config.sh
  check_repo
  [ "$status" -eq 0 ]
}

@test "a raw-config-ok line is exempt" {
  make_repo
  printf 'jq %s  # raw-config-ok: a profile\n' \
    "'.options.kernel // \"lts\"'" > .installer/lib/a.sh
  check_repo
  [ "$status" -eq 0 ]
}

@test "--list prints every raw read and never fails" {
  make_repo
  printf 'jq %s\n' "'.filesystem // \"zfs\"'" > .installer/lib/a.sh
  check_repo --list
  [ "$status" -eq 0 ]
  [[ "$output" == *".installer/lib/a.sh:1: jq '.filesystem"* ]]
}

@test "coalescing without a literal default is not a raw read" {
  make_repo
  printf 'jq %s\n' "'.users // [] | .[]'" "'.options.fonts // empty'" \
    "'(.packages // {}) | keys'" "'.options.bootloader // \"\"'" \
    > .installer/lib/a.sh
  check_repo
  [ "$status" -eq 0 ]
}

@test "a field the schema does not own is not a raw read" {
  make_repo
  printf 'jq %s\n' "'.mode // \"single\"'" \
    "'.data_pools[0].filesystem // \"zfs\"'" "'.os_pool.topology // \"?\"'" \
    > .installer/lib/a.sh
  check_repo
  [ "$status" -eq 0 ]
}

@test "a schema field read off a jq variable is a raw read" {
  make_repo
  printf 'jq %s\n' "'(\$m.filesystem // \"zfs\") as \$fs'" > .installer/lib/a.sh
  check_repo
  [ "$status" -ne 0 ]
}

@test "a non-empty array default is a raw read" {
  make_repo
  printf 'jq %s\n' "'(.options.bootloader // [\"a\"])'" > .installer/lib/a.sh
  check_repo
  [ "$status" -ne 0 ]
}

@test "extras/ and programs/ scripts are scanned too" {
  make_repo
  mkdir -p .installer/extras/desktop/x .installer/programs/dev/y
  printf 'jq %s\n' "'.filesystem // \"zfs\"'" \
    > .installer/extras/desktop/x/audit.sh
  check_repo
  [ "$status" -ne 0 ]
  printf 'install_config_filesystem\n' > .installer/extras/desktop/x/audit.sh
  printf 'jq %s\n' "'.filesystem // \"zfs\"'" \
    > .installer/programs/dev/y/install.sh
  check_repo
  [ "$status" -ne 0 ]
}
