#!/usr/bin/env bats
# vm/lib/serve-http.sh's per-connection handler (no socket): a request in,
# an HTTP response out.

setup() {
  T="$(mktemp -d)"
  S="$BATS_TEST_DIRNAME/../../vm/lib/serve-http.sh"
}

teardown() { rm -rf "$T"; }

@test "a symlink is served with its target's length (repo-add's .db)" {
  # Audit Run 20261004: audit-aur.db → .db.tar.gz arrived truncated
  head -c 5000 /dev/zero > "$T/r.db.tar.gz"
  ln -s r.db.tar.gz "$T/r.db"
  printf 'GET /r.db HTTP/1.0\r\n\r\n' \
    | SERVE_DIR="$T" bash "$S" --handle > "$T/resp"
  grep -aq 'Content-Length: 5000' "$T/resp"
}
