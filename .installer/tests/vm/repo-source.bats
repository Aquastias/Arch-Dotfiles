#!/usr/bin/env bats
# Tests for vm/lib/repo-source.sh — REPO_URL=local stages local HEAD on the
# harness HTTP root, and every run announces the source + commit it installs
# (a pushed-repo run once passed while local HEAD was broken).

setup() {
  info() { echo "INFO $*"; }
  warn() { echo "WARN $*"; }
  export -f info warn
  LIBVIRT_GATEWAY=192.168.122.1 HTTP_PORT=9876
  CACHE_DIR="$BATS_TEST_TMPDIR/cache"
  repo="$BATS_TEST_TMPDIR/repo"
  git init -q "$repo"
  mkdir -p "$repo/.installer"
  echo one > "$repo/.installer/file"
  git -C "$repo" add -A
  git -C "$repo" -c user.name=t -c user.email=t@t commit -qm one
  export INSTALLER_DIR="$repo/.installer"
  # shellcheck source=../../vm/lib/repo-source.sh
  source "$BATS_TEST_DIRNAME/../../vm/lib/repo-source.sh"
}

@test "stage_local: bare clone of HEAD, dumb-HTTP ready, URL on HTTP root" {
  run vm_repo_source_stage_local "$CACHE_DIR" local-repo.git
  [ "$status" -eq 0 ]
  [ "$output" = "http://192.168.122.1:9876/local-repo.git" ]
  [ -f "$CACHE_DIR/local-repo.git/info/refs" ]
  [ "$(git -C "$CACHE_DIR/local-repo.git" rev-parse HEAD)" \
    = "$(git -C "$repo" rev-parse HEAD)" ]
}

@test "stage_local: warns that uncommitted changes are not installed" {
  echo two > "$repo/.installer/file"
  run vm_repo_source_stage_local "$CACHE_DIR" local-repo.git
  [ "$status" -eq 0 ]
  [[ "$output" == *"Uncommitted changes are NOT installed"* ]]
}

@test "resolve: REPO_URL=local installs and announces local HEAD" {
  REPO_URL=local
  vm_repo_source_resolve > "$BATS_TEST_TMPDIR/out"
  [ "$REPO_URL" = "http://192.168.122.1:9876/local-repo.git" ]
  short="$(git -C "$repo" rev-parse --short HEAD)"
  grep -q "Repo source: local HEAD $short" "$BATS_TEST_TMPDIR/out"
}

@test "resolve: a pushed repo is announced as such, with its commit" {
  git clone -q --bare "$repo" "$BATS_TEST_TMPDIR/pushed.git"
  REPO_URL="file://$BATS_TEST_TMPDIR/pushed.git"
  run vm_repo_source_resolve
  [ "$status" -eq 0 ]
  short="$(git -C "$repo" rev-parse --short=7 HEAD)"
  [[ "$output" == *"at $short — the PUSHED repo"*"use --local"* ]]
}

@test "commit: an unreachable repo reports unknown" {
  run vm_repo_source_commit "file://$BATS_TEST_TMPDIR/missing.git"
  [ "$output" = unknown ]
}

@test "matrix: --local stages once and serves it for the whole run" {
  mkdir -p "$INSTALLER_DIR/vm/lib"
  printf '#!/usr/bin/env bash\necho "$@" > %s/served\n' "$BATS_TEST_TMPDIR" \
    > "$INSTALLER_DIR/vm/lib/serve-http.sh"
  chmod +x "$INSTALLER_DIR/vm/lib/serve-http.sh"
  # shellcheck source=../../lib/matrix/run.sh
  source "$BATS_TEST_DIRNAME/../../lib/matrix/run.sh"
  matrix_run_serve_local 2>/dev/null
  wait "$MATRIX_LOCAL_SERVER_PID"
  [ "$REPO_URL" = "http://192.168.122.1:9876/local-repo.git" ]
  [ -f "$CACHE_DIR/local-repo.git/info/refs" ]
  [ "$(cat "$BATS_TEST_TMPDIR/served")" = "$CACHE_DIR 192.168.122.1 9876" ]
}
