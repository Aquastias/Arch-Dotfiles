#!/usr/bin/env bats
# lib/shell/runtime.sh — stage_shell_stdlib: the whole Shell Stdlib (facade +
# shell/ modules) for scripts a unit runs after boot. Regression (Audit Run
# 20260929): clamav/rkhunter staged only the facade, whose module sources then
# failed ("cd: /usr/local/lib/shell: No such file or directory").

setup() {
  source "$BATS_TEST_DIRNAME/../../lib/shell/runtime.sh"
  export SHELL_COMMONS="$BATS_TEST_DIRNAME/../../lib"
  DEST="$BATS_TEST_TMPDIR/usr-local-lib"
  # run as the test user: drop sudo and root ownership
  sudo() {
    local a=() skip=0 x
    for x in "$@"; do
      ((skip)) && { skip=0; continue; }
      [[ "$x" == -o || "$x" == -g ]] && { skip=1; continue; }
      a+=("$x")
    done
    "${a[@]}"
  }
}

@test "stages the facade and every module so it sources standalone" {
  stage_shell_stdlib "$DEST"
  [ -f "$DEST/shell-stdlib.sh" ]
  local m
  for m in "$SHELL_COMMONS"/shell/*.sh; do [ -f "$DEST/shell/${m##*/}" ]; done
  run bash -c "unset SHELL_COMMONS; source '$DEST/shell-stdlib.sh' \
    && declare -F print_status >/dev/null"
  [ "$status" -eq 0 ]
}
