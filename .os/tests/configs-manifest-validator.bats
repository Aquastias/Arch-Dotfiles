#!/usr/bin/env bats
# Tests for lib/configs-generator.sh — Manifest Validator.

setup() {
  TEST_DIR="$(mktemp -d)"
  MAN="$TEST_DIR/configs/manifest.jsonc"
  mkdir -p "$TEST_DIR/configs"
  printf 'placeholder\n' > "$TEST_DIR/configs/greeting"
  # shellcheck source=../lib/configs-generator.sh
  source "$BATS_TEST_DIRNAME/../lib/configs-generator.sh"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# ── happy path ────────────────────────────────────────────────────────────────

@test "validator: parses JSONC with files[{src,dst}] and returns 0" {
  cat > "$MAN" <<'JSONC'
{
  // hello fixture
  "files": [
    { "src": "greeting", "dst": "~/.config/hello/greeting" }
  ]
}
JSONC

  run cg_validate_manifest "$MAN"
  [ "$status" -eq 0 ]
}

@test "validator: accepts mode in 0600/600/0644/644/4755 forms" {
  cat > "$MAN" <<'JSONC'
{
  "files": [
    { "src": "greeting", "dst": "~/a", "mode": "0600" },
    { "src": "greeting", "dst": "~/b", "mode": "600"  },
    { "src": "greeting", "dst": "~/c", "mode": "0644" },
    { "src": "greeting", "dst": "~/d", "mode": "644"  },
    { "src": "greeting", "dst": "~/e", "mode": "4755" }
  ]
}
JSONC

  run cg_validate_manifest "$MAN"
  [ "$status" -eq 0 ]
}

# ── top-level schema ──────────────────────────────────────────────────────────

@test "validator: malformed JSONC fails and names the manifest path" {
  printf '%s\n' '{ "files": [ this is not json' > "$MAN"

  run cg_validate_manifest "$MAN"
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"$MAN"* ]] || [[ "$output" == *"$MAN"* ]]
}

@test "validator: missing files array fails" {
  printf '%s\n' '{}' > "$MAN"

  run cg_validate_manifest "$MAN"
  [ "$status" -ne 0 ]
  [[ "$stderr" == *files* ]] || [[ "$output" == *files* ]]
}

@test "validator: unknown top-level key fails and names key" {
  cat > "$MAN" <<'JSONC'
{
  "files": [ { "src": "greeting", "dst": "~/x" } ],
  "meta":  { "version": 1 }
}
JSONC

  run cg_validate_manifest "$MAN"
  [ "$status" -ne 0 ]
  [[ "$stderr" == *meta* ]] || [[ "$output" == *meta* ]]
}

# ── per-entry required fields ────────────────────────────────────────────────

@test "validator: entry missing src fails and names entry index" {
  cat > "$MAN" <<'JSONC'
{ "files": [ { "dst": "~/x" } ] }
JSONC

  run cg_validate_manifest "$MAN"
  [ "$status" -ne 0 ]
  [[ "$stderr" == *src* ]] || [[ "$output" == *src* ]]
  [[ "$stderr" == *"[0]"* ]] || [[ "$output" == *"[0]"* ]]
}

@test "validator: entry missing dst fails and names entry index" {
  cat > "$MAN" <<'JSONC'
{ "files": [ { "src": "greeting" } ] }
JSONC

  run cg_validate_manifest "$MAN"
  [ "$status" -ne 0 ]
  [[ "$stderr" == *dst* ]] || [[ "$output" == *dst* ]]
  [[ "$stderr" == *"[0]"* ]] || [[ "$output" == *"[0]"* ]]
}

@test "validator: src not found relative to manifest dir fails" {
  cat > "$MAN" <<'JSONC'
{ "files": [ { "src": "missing", "dst": "~/x" } ] }
JSONC

  run cg_validate_manifest "$MAN"
  [ "$status" -ne 0 ]
  [[ "$stderr" == *missing* ]] || [[ "$output" == *missing* ]]
}

# ── dst rules ────────────────────────────────────────────────────────────────

@test "validator: dst not starting with ~/ fails" {
  cat > "$MAN" <<'JSONC'
{ "files": [ { "src": "greeting", "dst": "/tmp/x" } ] }
JSONC

  run cg_validate_manifest "$MAN"
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"~/"* ]] || [[ "$output" == *"~/"* ]]
}

@test "validator: dst containing .. segment fails" {
  cat > "$MAN" <<'JSONC'
{ "files": [ { "src": "greeting", "dst": "~/../etc/x" } ] }
JSONC

  run cg_validate_manifest "$MAN"
  [ "$status" -ne 0 ]
  [[ "$stderr" == *".."* ]] || [[ "$output" == *".."* ]]
}

@test "validator: dst expanding under /etc/ fails" {
  HOME="/etc/fake" cat > "$MAN" <<'JSONC'
{ "files": [ { "src": "greeting", "dst": "~/foo" } ] }
JSONC

  HOME="/etc/fake" run cg_validate_manifest "$MAN"
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"/etc/"* ]] || [[ "$output" == *"/etc/"* ]]
}

@test "validator: dst expanding under /usr/ fails" {
  cat > "$MAN" <<'JSONC'
{ "files": [ { "src": "greeting", "dst": "~/foo" } ] }
JSONC

  HOME="/usr/fake" run cg_validate_manifest "$MAN"
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"/usr/"* ]] || [[ "$output" == *"/usr/"* ]]
}

# ── mode rules ───────────────────────────────────────────────────────────────

@test "validator: mode rwxr fails" {
  cat > "$MAN" <<'JSONC'
{ "files": [ { "src": "greeting", "dst": "~/x", "mode": "rwxr" } ] }
JSONC

  run cg_validate_manifest "$MAN"
  [ "$status" -ne 0 ]
  [[ "$stderr" == *mode* ]] || [[ "$output" == *mode* ]]
}

@test "validator: mode 999 fails" {
  cat > "$MAN" <<'JSONC'
{ "files": [ { "src": "greeting", "dst": "~/x", "mode": "999" } ] }
JSONC

  run cg_validate_manifest "$MAN"
  [ "$status" -ne 0 ]
  [[ "$stderr" == *mode* ]] || [[ "$output" == *mode* ]]
}

@test "validator: mode 08 fails" {
  cat > "$MAN" <<'JSONC'
{ "files": [ { "src": "greeting", "dst": "~/x", "mode": "08" } ] }
JSONC

  run cg_validate_manifest "$MAN"
  [ "$status" -ne 0 ]
  [[ "$stderr" == *mode* ]] || [[ "$output" == *mode* ]]
}

# ── unknown per-entry key ────────────────────────────────────────────────────

@test "validator: unknown per-entry key fails and names key + index" {
  cat > "$MAN" <<'JSONC'
{
  "files": [
    { "src": "greeting", "dst": "~/x", "template": true }
  ]
}
JSONC

  run cg_validate_manifest "$MAN"
  [ "$status" -ne 0 ]
  [[ "$stderr" == *template* ]] || [[ "$output" == *template* ]]
  [[ "$stderr" == *"[0]"* ]] || [[ "$output" == *"[0]"* ]]
}
