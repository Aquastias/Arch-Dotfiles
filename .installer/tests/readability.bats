#!/usr/bin/env bats
# Gate for the Readability Rules (ADR 0153, docs/agents/readability.md).
# The headline test runs the Readability Lint against THIS repo and asserts it
# is clean against the Readability Baseline; the rest build throwaway git repos
# to prove each rule catches / allows the right thing.

CHECK="$BATS_TEST_DIRNAME/readability.sh"

# make_repo: cd into a fresh git repo with an empty .installer/.
make_repo() {
  REPO="$(mktemp -d)"
  cd "$REPO"
  git init -q
  git config user.email t@t
  git config user.name t
  mkdir -p .installer/tests
}
check_repo() {
  git add -A
  run bash -c "cd '$REPO' && bash '$CHECK' $*"
}
teardown() { [[ -n "${REPO:-}" ]] && rm -rf "$REPO"; return 0; }

@test "this repo is clean against the Readability Baseline" {
  run bash "$CHECK"
  [ "$status" -eq 0 ]
}

@test "catches a single-letter local" {
  make_repo
  printf 'greet() {\n  local f="x"\n  echo "$f"\n}\n' > .installer/a.sh
  check_repo
  [ "$status" -ne 0 ]
  [[ "$output" == *"local-name: .installer/a.sh:2: f"* ]]
}

@test "catches an abbreviated function name" {
  make_repo
  printf '_ctl_pw_missing() { return 0; }\n' > .installer/a.sh
  check_repo
  [ "$status" -ne 0 ]
  [[ "$output" == *"function-name: .installer/a.sh:1: ctl pw"* ]]
}

@test "allows domain acronyms, counters and rc" {
  make_repo
  cat > .installer/a.sh <<'SH'
zfs_esp_gpu_mount() {
  local i j rc uid
  for i in 1 2; do rc=0; done
  return "$rc"
}
SH
  check_repo
  [ "$status" -eq 0 ]
}

@test "catches a function over 50 lines" {
  make_repo
  {
    printf 'long_function() {\n'
    for n in $(seq 51); do printf '  true\n'; done
    printf '}\n'
  } > .installer/a.sh
  check_repo
  [ "$status" -ne 0 ]
  [[ "$output" == *"function-length: .installer/a.sh:1: 53 lines"* ]]
}

@test "catches nesting deeper than 3" {
  make_repo
  cat > .installer/a.sh <<'SH'
deep_function() {
  if true; then
    for item in a; do
      while false; do
        case "$item" in
          a) true ;;
        esac
      done
    done
  fi
}
SH
  check_repo
  [ "$status" -ne 0 ]
  [[ "$output" == *"nesting: .installer/a.sh:1: depth 4"* ]]
}

@test "allows nesting of 3 and ignores keywords inside quoted programs" {
  make_repo
  cat > .installer/a.sh <<'SH'
shallow_function() {
  if true; then
    for item in a; do
      awk '
        { if ($1) { while (0) { } } }
      ' "$item"
    done
  fi
}
SH
  check_repo
  [ "$status" -eq 0 ]
}

@test "catches a file over 500 lines" {
  make_repo
  for n in $(seq 501); do printf 'true\n'; done > .installer/a.sh
  check_repo
  [ "$status" -ne 0 ]
  [[ "$output" == *"file-length: .installer/a.sh:1: 501 lines"* ]]
}

@test "catches replace-tier tools" {
  make_repo
  cat > .installer/a.sh <<'SH'
first_line() {
  printf 'a\nb\n' | head -n 1
  local parent
  parent="$(dirname /a/b)"
}
SH
  check_repo
  [ "$status" -ne 0 ]
  [[ "$output" == *"tool: .installer/a.sh:2: head"* ]]
  [[ "$output" == *"tool: .installer/a.sh:4: dirname"* ]]
}

@test "ignores tool names in strings, comments, case patterns and heredocs" {
  make_repo
  cat > .installer/a.sh <<'SH'
describe_tools() {
  # head and tail are replace-tier
  echo "use head instead"
  grep -E 'x|head' /dev/null
  case "$1" in
    tail) echo tail ;;
  esac
  cat <<EOT
head of the document
EOT
}
SH
  check_repo
  [ "$status" -eq 0 ]
}

@test "catches sed without -i and allows sed -i" {
  make_repo
  cat > .installer/a.sh <<'SH'
edit_files() {
  sed -i 's/a/b/' /tmp/file
  sed -Ei 's/a/b/' /tmp/file
  echo a | sed 's/a/b/'
}
SH
  check_repo
  [ "$status" -ne 0 ]
  [[ "$output" == *"sed-not-inplace: .installer/a.sh:4"* ]]
  [[ "$output" != *"a.sh:2"* ]]
  [[ "$output" != *"a.sh:3"* ]]
}

@test "the readability-ok pragma exempts a line" {
  make_repo
  printf 'pick_first() {\n  head -n 1  # readability-ok: stream cutoff\n}\n' \
    > .installer/a.sh
  check_repo
  [ "$status" -eq 0 ]
}

@test "bats @test titles are free text" {
  make_repo
  printf '@test "a b c d e" {\n  true\n}\n' > .installer/tests/a.bats
  check_repo
  [ "$status" -eq 0 ]
}

@test "ignores program home payloads" {
  make_repo
  mkdir -p .installer/programs/system/zsh/home
  printf 'f() { head -1; }\n' > .installer/programs/system/zsh/home/x.sh
  check_repo
  [ "$status" -eq 0 ]
}

@test "allows a jq def look-alike" {
  make_repo
  cat > .installer/a.sh <<'SH'
assign_keys() {
  jq -n 'def assign($k): .[$k] // [] end; {} | assign("a")'
}
SH
  check_repo
  [ "$status" -eq 0 ]
}

@test "a baselined violation passes" {
  make_repo
  printf 'pick_first() {\n  head -n 1\n}\n' > .installer/a.sh
  printf 'tool\t.installer/a.sh\tpick_first:head\n' \
    > .installer/tests/readability-baseline.txt
  check_repo
  [ "$status" -eq 0 ]
}

@test "a new violation beside a baselined one fails" {
  make_repo
  printf 'pick_first() {\n  head -n 1\n  head -n 2\n}\n' > .installer/a.sh
  printf 'tool\t.installer/a.sh\tpick_first:head\n' \
    > .installer/tests/readability-baseline.txt
  check_repo
  [ "$status" -ne 0 ]
  [[ "$output" == *"tool: .installer/a.sh:"* ]]
}

@test "a stale baseline entry fails" {
  make_repo
  printf 'pick_first() {\n  true\n}\n' > .installer/a.sh
  printf 'tool\t.installer/a.sh\tpick_first:head\n' \
    > .installer/tests/readability-baseline.txt
  check_repo
  [ "$status" -ne 0 ]
  [[ "$output" == *"stale-baseline: tool .installer/a.sh pick_first:head"* ]]
}

@test "--write-baseline records current violations" {
  make_repo
  printf 'pick_first() {\n  head -n 1\n}\n' > .installer/a.sh
  check_repo --write-baseline
  [ "$status" -eq 0 ]
  grep -q $'tool\t.installer/a.sh\tpick_first:head' \
    .installer/tests/readability-baseline.txt
  check_repo
  [ "$status" -eq 0 ]
}

@test "reads only the declaration on a 'local x; x=…' line" {
  make_repo
  printf 'need_size() {\n  local need; need="$(echo "$1")"\n}\n' \
    > .installer/a.sh
  check_repo
  [ "$status" -eq 0 ]
}

# make_adr_repo: a repo with ADR 0001 and ADR 0002 to link to.
make_adr_repo() {
  make_repo
  mkdir -p docs/adr
  printf '# ADR 0001: First\n\nSee ADR 0002.\n' > docs/adr/0001-first.md
  printf '# ADR 0002: Second\n' > docs/adr/0002-second.md
}

@test "catches an unlinked ADR mention in a doc" {
  make_adr_repo
  printf 'Why: ADR 0001.\n' > README.md
  check_repo
  [ "$status" -ne 0 ]
  [[ "$output" == *"adr-link: README.md:1: ADR 0001 is not a link"* ]]
}

@test "--fix-adr-links links mentions with a definition block" {
  make_adr_repo
  mkdir -p .installer
  printf 'Why: ADR 0001 (and ADR-0002).\n' > .installer/README.md
  check_repo --fix-adr-links
  [ "$status" -eq 0 ]
  run cat .installer/README.md
  [[ "${lines[0]}" == "Why: [ADR 0001] (and [ADR-0002])." ]]
  [[ "$output" == *"[ADR 0001]: ../docs/adr/0001-first.md"* ]]
  [[ "$output" == *"[ADR-0002]: ../docs/adr/0002-second.md"* ]]
  check_repo
  [ "$status" -eq 0 ]
}

@test "--fix-adr-links is idempotent" {
  make_adr_repo
  printf 'Why: ADR 0001.\n' > README.md
  check_repo --fix-adr-links
  cp README.md once.md
  check_repo --fix-adr-links
  run diff once.md README.md
  [ "$status" -eq 0 ]
}

@test "an ADR's own number, code, and .scratch mentions need no link" {
  make_adr_repo
  printf '# ADR 0002: Second\n' > docs/adr/0002-second.md
  printf 'Run `ADR 0001`.\n\n```\nADR 0001\n```\n' > README.md
  mkdir -p .scratch/x
  printf 'ADR 0001\n' > .scratch/x/spec.md
  check_repo --fix-adr-links
  check_repo
  [ "$status" -eq 0 ]
  run cat README.md
  [[ "$output" != *"[ADR 0001]"* ]]
}

@test "a bracketed mention without a definition fails" {
  make_adr_repo
  printf 'Why: [ADR 0001].\n' > README.md
  check_repo
  [ "$status" -ne 0 ]
  [[ "$output" == *"adr-link: README.md:1: [ADR 0001] has no definition"* ]]
}

@test "--fix-adr-links rewraps a pushed line without splitting a link" {
  make_adr_repo
  local words="aaaa bbbb cccc dddd eeee ffff gggg hhhh iiii jjjj kkkk llll"
  words+=" mmmm xxxx"
  printf "%s\n%s\n" "$words ADR 0001." "next line." > README.md
  check_repo --fix-adr-links
  run cat README.md
  [ "${lines[0]}" = "$words" ]
  [ "${lines[1]}" = "[ADR 0001]. next line." ]
  check_repo
  [ "$status" -eq 0 ]
}

@test "--fix-adr-links uses bare file names between ADRs" {
  make_adr_repo
  check_repo --fix-adr-links
  run cat docs/adr/0001-first.md
  [[ "$output" == *"[ADR 0002]: 0002-second.md"* ]]
}

@test "--fix-adr-links links each number of a chained mention" {
  make_adr_repo
  printf 'Why: ADR 0001/0002.\n' > README.md
  check_repo --fix-adr-links
  run cat README.md
  [ "${lines[0]}" = "Why: [ADR 0001]/[0002]." ]
  [[ "$output" == *"[0002]: docs/adr/0002-second.md"* ]]
  check_repo
  [ "$status" -eq 0 ]
}

@test "--fix-adr-links never wraps a marker to a line start" {
  make_adr_repo
  local words="aaaa bbbb cccc dddd eeee ffff gggg hhhh iiii jjjj kkkk llll"
  printf "%s\n%s\n" "$words mmmm nnnn ADR 0001 + x" "next." > README.md
  check_repo --fix-adr-links
  run cat README.md
  [ "${lines[1]}" = "[ADR 0001] + x next." ]
  check_repo
  [ "$status" -eq 0 ]
}

@test "--fix-adr-links never turns a line-start mention into a definition" {
  make_adr_repo
  printf 'Noted in\nADR 0001: the seam.\n' > README.md
  check_repo --fix-adr-links
  run cat README.md
  [ "${lines[1]}" = "[ADR 0001][]: the seam." ]
  check_repo
  [ "$status" -eq 0 ]
}
