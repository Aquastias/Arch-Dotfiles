#!/usr/bin/env bats
# Tests for emit_promote_programs (lib/config/emit.sh) — the Guided Installer's
# program-promotion split (ADR 0039, issue 06). A typed packages.extra name that
# resolves to a programs/<category>/<name>/ with system:true is moved into
# system_programs (installed via the Program Runner); non-matches stay repo
# packages; a name that is both a program and a package resolves as the program.
# Resolution is TUI-side — the back-end's System-Program-vs-package contract is
# untouched.
#
# Pure: a config JSON in → a config JSON out, no TTY, no disk writes (beyond the
# fixture program tree the test builds under a temp OS_DIR).

setup() {
  TEST_DIR="$(mktemp -d)"
  export OS_DIR="$TEST_DIR"

  info()    { :; }
  warn()    { :; }
  error()   { echo "[error] $*" >&2; return 1; }
  section() { :; }
  export -f info warn error section

  mkdir -p "$OS_DIR/hosts/core"
  printf '%s\n' '{}' > "$OS_DIR/hosts/core/profile.jsonc"

  # shellcheck source=../../lib/config/emit.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/emit.sh"
}

teardown() { rm -rf "$TEST_DIR"; }

# make_program <category> <name> <system-bool> — a minimal resolvable program.
make_program() {
  local cat="$1" name="$2" sys="$3" dir="$OS_DIR/programs/$1/$2"
  mkdir -p "$dir"
  printf '{"name":"%s","system":%s}\n' "$name" "$sys" > "$dir/config.jsonc"
  : > "$dir/install.sh"
}

# ── tracer: a typed extra that names a system program is promoted ───────────

@test "emit_promote_programs: a matching system program moves to system_programs" {
  make_program security wireguard true
  config='{"packages":{"extra":["wireguard","htop"]}}'

  run emit_promote_programs "$config"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.system_programs | index("wireguard")'
  echo "$output" | jq -e '.packages.extra | index("wireguard") | not'
}

# ── a non-matching name stays a plain repo package ──────────────────────────

@test "emit_promote_programs: a non-program name stays in packages.extra" {
  make_program security wireguard true
  config='{"packages":{"extra":["wireguard","htop"]}}'

  run emit_promote_programs "$config"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.packages.extra | index("htop")'
  echo "$output" | jq -e '.system_programs | (index("htop") | not)'
}

# ── ambiguous: a name that is also a real repo package → the program wins ───

@test "emit_promote_programs: a program-resolving name promotes (program wins)" {
  make_program cli git true     # git is also a repo package — program wins
  config='{"packages":{"extra":["git"]}}'

  run emit_promote_programs "$config"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.system_programs | index("git")'
  echo "$output" | jq -e '.packages.extra | (index("git") | not)'
}

# ── a user-level (system:false) program is NOT host-promoted ────────────────

@test "emit_promote_programs: a system:false program stays a package" {
  make_program editors nvim false
  config='{"packages":{"extra":["nvim"]}}'

  run emit_promote_programs "$config"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.packages.extra | index("nvim")'
  echo "$output" | jq -e '.system_programs | (index("nvim") | not)'
}

# ── promotion preserves pre-declared system_programs, deduped ───────────────

@test "emit_promote_programs: keeps existing system_programs, no duplicates" {
  make_program security wireguard true
  config='{"system_programs":["cups","wireguard"],"packages":{"extra":["wireguard"]}}'

  run emit_promote_programs "$config"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.system_programs == ["cups","wireguard"]'   # deduped
  echo "$output" | jq -e '.packages.extra | (index("wireguard") | not)'
}

# ── no extras → the config is returned unchanged ────────────────────────────

@test "emit_promote_programs: a config without packages.extra is unchanged" {
  config='{"system_programs":["cups"]}'

  run emit_promote_programs "$config"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '. == {"system_programs":["cups"]}'
}
