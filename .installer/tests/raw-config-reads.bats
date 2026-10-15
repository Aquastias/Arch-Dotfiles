#!/usr/bin/env bats
# Gate for the Raw Config Read Lint (install-config-reader/03): an Effective
# Config field is read through the Install Config Reader (bound to JSON where
# the module holds JSON), never as a raw `.<path> // <default>` jq read that
# re-declares its default. Today's raw reads are a per-file baseline that may
# only shrink. The headline test runs the lint against THIS repo; the rest
# build throwaway git repos to prove each rule.

CHECK="$BATS_TEST_DIRNAME/raw-config-reads.sh"

# make_repo: cd into a fresh git repo with an empty baseline and a two-row
# schema (one row split across lines, as the real one does at 80 columns).
make_repo() {
  REPO="$(mktemp -d)"
  cd "$REPO"
  git init -q
  mkdir -p .installer/tests .installer/lib/config
  : > .installer/tests/raw-config-reads-baseline.txt
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
  [[ "$output" == *".installer/lib/a.sh: 1 raw config read(s), baseline 0"* ]]
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

@test "a baselined read passes; a stale (too high) baseline fails" {
  make_repo
  printf 'jq %s\n' "'.filesystem // \"zfs\"'" > .installer/lib/a.sh
  printf '.installer/lib/a.sh\t1\n' \
    > .installer/tests/raw-config-reads-baseline.txt
  check_repo
  [ "$status" -eq 0 ]
  printf 'install_config_filesystem\n' > .installer/lib/a.sh
  check_repo
  [ "$status" -ne 0 ]
  [[ "$output" \
    == *"stale baseline: .installer/lib/a.sh: 0 now, baseline 1"* ]]
}

@test "--update rewrites the baseline to today's counts" {
  make_repo
  printf 'jq %s\n' "'.users[0] // \"root\"'" > .installer/lib/a.sh
  check_repo --update
  [ "$status" -eq 0 ]
  [ "$(cat .installer/tests/raw-config-reads-baseline.txt)" \
    = "$(printf '.installer/lib/a.sh\t1')" ]
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
