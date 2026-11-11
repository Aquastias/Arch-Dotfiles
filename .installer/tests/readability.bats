#!/usr/bin/env bats
# Gate for the Readability Rules (ADR 0153, ADR 0167; rules in
# docs/agents/readability.md).
# The headline test runs the Readability Lint against THIS repo and asserts it
# is clean (the lint is strict); the rest build throwaway git repos
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
  # Non-prefix tests share a.sh; keep the Prefix rule out of their way.
  printf 'exempt-file .installer/a.sh\n' \
    > .installer/tests/readability-prefixes.txt
}
check_repo() {
  git add -A
  run bash -c "cd '$REPO' && bash '$CHECK' $*"
}
teardown() { [[ -n "${REPO:-}" ]] && rm -rf "$REPO"; return 0; }

@test "this repo passes the strict Readability Lint" {
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

@test "bats @test titles are free text" {
  make_repo
  printf '@test "a b c d e" {\n  true\n}\n' > .installer/tests/a.bats
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

@test "prefix: a public function must start with its file stem" {
  make_repo
  mkdir -p .installer/lib
  printf 'history_load() { :; }\nload_history() { :; }\n' \
    > .installer/lib/history.sh
  check_repo
  [ "$status" -ne 0 ]
  [[ "$output" == *"prefix: .installer/lib/history.sh:2: load_history"* ]]
  [[ "$output" != *"history_load"* ]]
}

@test "prefix: a private function uses _<stem>_ and the stem itself is fine" {
  make_repo
  mkdir -p .installer/lib
  printf 'finalize() { :; }\n_finalize_export() { :; }\n_export() { :; }\n' \
    > .installer/lib/finalize.sh
  check_repo
  [ "$status" -ne 0 ]
  [[ "$output" == *"prefix: .installer/lib/finalize.sh:3: _export"* ]]
  [[ "$output" != *":1: finalize"* ]]
  [[ "$output" != *"_finalize_export"* ]]
}

@test "prefix: a directory API lends its name; private keeps the subpath" {
  make_repo
  mkdir -p .installer/lib/layout/zfs
  printf 'api .installer/lib/layout/ layout_\n' \
    > .installer/tests/readability-prefixes.txt
  printf 'layout_suggest_pools() { :; }\n_zfs_multi_read() { :; }\n' \
    > .installer/lib/layout/zfs/multi.sh
  check_repo
  [ "$status" -eq 0 ]
}

@test "prefix: interface functions, exempt files and exempt names pass" {
  make_repo
  mkdir -p .installer/lib/layout/ext4 .installer/tools
  cat > .installer/tests/readability-prefixes.txt <<'RULES'
interface root_adapter_mkfs
exempt-file .installer/tools/*.sh
exempt-name .installer/lib/hook.sh run_hook
RULES
  printf 'root_adapter_mkfs() { :; }\n' > .installer/lib/layout/ext4/single.sh
  printf 'parse_options() { :; }\n' > .installer/tools/fetch.sh
  printf 'run_hook() { :; }\n' > .installer/lib/hook.sh
  check_repo
  [ "$status" -eq 0 ]
}

@test "prefix: an explicit file rule overrides the stem" {
  make_repo
  mkdir -p .installer/lib/guided
  printf 'file .installer/lib/guided/shell.sh guided_ _guided_shell_\n' \
    > .installer/tests/readability-prefixes.txt
  printf 'guided_run() { :; }\n_guided_shell_draw() { :; }\n' \
    > .installer/lib/guided/shell.sh
  check_repo
  [ "$status" -eq 0 ]
}

@test "heredoc bodies do not count toward function length" {
  make_repo
  {
    printf 'write_template() {\n  cat <<EOT\n'
    for n in $(seq 60); do printf 'template line\n'; done
    printf 'EOT\n}\n'
  } > .installer/a.sh
  check_repo
  [ "$status" -eq 0 ]
}

# ── doc-path (ADR 0156) ─────────────────────────────────────────────────────

@test "catches a backticked doc path that is not a tracked file" {
  make_repo
  printf 'Run `tools/gone.sh` first.\n' > README.md
  check_repo
  [ "$status" -ne 0 ]
  [[ "$output" == *"doc-path: README.md:1: tools/gone.sh is not a tracked"* ]]
}

@test "doc paths resolve by tracked tail; target paths and ADRs are skipped" {
  make_repo
  mkdir -p .installer/vm/lib docs/adr
  printf 'true\n' > .installer/vm/lib/core.sh
  printf 'See `vm/lib/core.sh`, `../.installer/vm/lib/core.sh`.\n' \
    > README.md
  printf 'Seeds `/usr/lib/x.sh`, `~/.zshrc.sh`, `<name>/a.sh`.\n' >> README.md
  printf 'Plain removed name: tools/gone.sh.\n' >> README.md
  printf '# ADR 0001: Old\n\nWas `tools/gone.sh`.\n' > docs/adr/0001-old.md
  check_repo
  [ "$status" -eq 0 ]
}

# ── Tool Reference: commands and flags (ADR 0167) ──────────────────────────

# make_reference_repo: a repo whose Tool Reference lists `cut` (with -d
# taking a value and -f) and `rm` (with -r, -f), and whose Migrated Areas
# list holds .installer/lib/.
make_reference_repo() {
  make_repo
  mkdir -p docs .installer/lib
  cat > docs/tool-reference.md <<'DOC'
# Tool Reference

```markdown
### `example`
- `-z` — inside a code block: not an entry
```

### `cut`
Prints selected fields.

- `-d <delimiter>` — the character between fields
- `-f <fields>` — which fields to print

### `rm`
- `-r` — directories too
- `-f` — no error when missing

### `sudo`
- `-u <user>` — run as this user
DOC
  printf '.installer/lib/*\n' > .installer/tests/readability-migrated.txt
}

@test "tool-reference: a command missing from the Tool Reference fails" {
  make_reference_repo
  printf 'cut -d: -f1 /etc/passwd\nwc -l /etc/passwd\n' \
    > .installer/lib/a.sh
  check_repo
  [ "$status" -ne 0 ]
  [[ "$output" == *"tool-reference: .installer/lib/a.sh:2: wc has no"* ]]
  [[ "$output" != *"a.sh:1"* ]]
}

@test "flag-reference: a flag missing from the Tool Reference fails" {
  make_reference_repo
  printf 'cut -s -f1 /etc/passwd\nrm -rf /tmp/x\nrm -rv /tmp/x\n' \
    > .installer/lib/a.sh
  check_repo
  [ "$status" -ne 0 ]
  [[ "$output" == *"flag-reference: .installer/lib/a.sh:1: cut -s has no"* ]]
  [[ "$output" == *"flag-reference: .installer/lib/a.sh:3: rm -rv has no"* ]]
  [[ "$output" != *"a.sh:2"* ]]
}

@test "flag-reference: a flag that takes a value ends a cluster" {
  make_reference_repo
  printf 'cut -d: -f1 /etc/passwd\ncut -fd /etc/passwd\n' \
    > .installer/lib/a.sh
  check_repo
  [ "$status" -eq 0 ]
}

@test "tool-reference: adding the entry makes the command pass" {
  make_reference_repo
  printf 'wc /etc/passwd\n' > .installer/lib/a.sh
  check_repo
  [ "$status" -ne 0 ]
  printf '\n### `wc`\nCounts lines.\n' >> docs/tool-reference.md
  check_repo
  [ "$status" -eq 0 ]
}

@test "tool-reference: entries inside a code block declare nothing" {
  make_reference_repo
  printf 'example\n' > .installer/lib/a.sh
  check_repo
  [ "$status" -ne 0 ]
  [[ "$output" == *"tool-reference: .installer/lib/a.sh:1: example has no"* ]]
}

@test "tool-reference: outside Migrated Areas findings are advisory" {
  make_reference_repo
  mkdir -p .installer/tools
  printf 'stow /etc/passwd\n' > .installer/tools/a.sh
  check_repo
  [ "$status" -eq 0 ]
  check_repo --list
  [[ "$output" == *"tool-reference: .installer/tools/a.sh:1: stow has no"* ]]
}

@test "tool-reference: repo functions, scripts and variables need no entry" {
  make_reference_repo
  cat > .installer/lib/words.sh <<'SH'
words_count() { cut -f1 "$1"; }
words_main() {
  words_count /etc/passwd
  ./run.sh
  "$HELPER" --flag
  .installer/tools/fetch.sh
}
SH
  check_repo
  [ "$status" -eq 0 ]
}

@test "tool-reference: a test stub does not hide the real command" {
  make_reference_repo
  mkdir -p .installer/tests
  printf 'wc() { :; }\n' > .installer/tests/stub.bash
  printf 'wc /etc/passwd\n' > .installer/lib/a.sh
  check_repo
  [ "$status" -ne 0 ]
  [[ "$output" == *"tool-reference: .installer/lib/a.sh:1: wc has no"* ]]
}

@test "tool-reference: words that are not commands are skipped" {
  make_reference_repo
  cat > .installer/lib/words.sh <<'SH'
words_walk() {
  local item
  for item in alpha beta; do
    rm -f "$item"
  done
  local -a names=(alpha beta)
  local -a more=(
    gamma
    delta
  )
  if [[ -n "$item" && $item == alpha ]]; then rm -f x; fi
  (( count = count + 1 ))
  case "$1" in
    start | stop) rm -f y ;;
    -h|--help) rm -f z ;;
  esac
  echo "wc $(cut -f1 x) $((1 + 2))"  # wc in text
  cat <<EOT
wc in a heredoc
EOT
}
SH
  printf '\n### `echo`\n\n### `cat`\n\n### `local`\n- `-a` — array\n' \
    >> docs/tool-reference.md
  check_repo
  [ "$status" -eq 0 ]
}

@test "tool-reference: a continued line is one command" {
  make_reference_repo
  printf 'cut -d: \\\n  -f1 \\\n  -s /etc/passwd\n' > .installer/lib/a.sh
  check_repo
  [ "$status" -ne 0 ]
  [[ "$output" == *"flag-reference: .installer/lib/a.sh:1: cut -s has no"* ]]
}

@test "tool-reference: a wrapper's command is checked too" {
  make_reference_repo
  printf 'sudo -u root wc /etc/passwd\n' > .installer/lib/a.sh
  check_repo
  [ "$status" -ne 0 ]
  [[ "$output" == *"tool-reference: .installer/lib/a.sh:1: wc has no"* ]]
  [[ "$output" != *"sudo"* ]]
}

@test "tool-reference: user scripts are scanned; notes, vendored skills not" {
  make_reference_repo
  mkdir -p .local/bin .scratch/x .agents/skills/x
  printf '#!/bin/sh\nwc /etc/passwd\n' > .local/bin/tool
  printf 'wc /etc/passwd\n' > .scratch/x/a.sh
  printf 'wc /etc/passwd\n' > .agents/skills/x/a.sh
  check_repo --list
  [[ "$output" == *"tool-reference: .local/bin/tool:2: wc has no"* ]]
  [[ "$output" != *".scratch"* && "$output" != *".agents"* ]]
}

@test "ADR 0153 rules are advisory outside .installer/ until migrated" {
  make_reference_repo
  mkdir -p .local/bin
  printf 'greet() {\n  local f=1\n}\n' > .local/bin/tool
  check_repo
  [ "$status" -eq 0 ]
  printf '.local/bin/*\n' >> .installer/tests/readability-migrated.txt
  check_repo
  [ "$status" -ne 0 ]
  [[ "$output" == *"local-name: .local/bin/tool:2: f"* ]]
}

# ── Bash Feature Tier and jq features (ADR 0167) ───────────────────────────

@test "bash-feature: each banned form is reported in a Migrated Area" {
  make_reference_repo
  cat > .installer/lib/a.sh <<'SH'
value="${!name}"
local -n target="$1"
eval "$command_text"
read -r first <<<"$text"
[[ "$x" =~ ^(a)$ ]] && echo "${BASH_REMATCH[1]}"
file="${path##*/}"
echo "${path%/*} ${text//a/b} ${name,,} ${name@Q}"
printf -v padded '%5s' "$x"
SH
  check_repo --list
  local line
  for line in 1 2 3 4 5 6 7 8; do
    [[ "$output" == *"bash-feature: .installer/lib/a.sh:$line:"* ]]
  done
  check_repo
  [ "$status" -ne 0 ]
}

@test "bash-feature: allowed forms and the bootstrap line pass" {
  make_reference_repo
  cat > .installer/lib/a.sh <<'SH'
script_path="${BASH_SOURCE[0]}"
script_directory="$(cd "${script_path%/*}" && pwd)"
count="${#names[@]}"
keys="${!names[@]}"
mode="${1:-fast}"
echo 'a ${x##*/} in single quotes' # and ${y%%z} in a comment
SH
  check_repo --list
  [[ "$output" != *"bash-feature"* ]]
}

@test "bash-feature: outside Migrated Areas it is advisory" {
  make_reference_repo
  mkdir -p .installer/tools
  printf 'eval "$x"\n' > .installer/tools/a.sh
  check_repo
  [ "$status" -eq 0 ]
  check_repo --list
  [[ "$output" == *"bash-feature: .installer/tools/a.sh:1: eval is banned"* ]]
}

@test "jq-feature: banned jq features are reported, also on later lines" {
  make_reference_repo
  cat > .installer/lib/a.sh <<'SH'
jq -n 'reduce range(3) as $n (0; . + $n)'
jq -r '
  .users
  | walk(.)
' "$file"
jq -r '.reduce_count, .paths, $def' "$file"
SH
  check_repo --list
  [[ "$output" == *"jq-feature: .installer/lib/a.sh:1: jq reduce is banned"* ]]
  [[ "$output" == *"jq-feature: .installer/lib/a.sh:4: jq walk is banned"* ]]
  [[ "$output" != *"jq-feature: .installer/lib/a.sh:6"* ]]
}

@test "jq-feature: single-quoted text of other commands is not jq" {
  make_reference_repo
  printf "echo 'reduce the walk'\n" > .installer/lib/a.sh
  check_repo --list
  [[ "$output" != *"jq-feature"* ]]
}

@test "program-header: a .jq or .awk file needs a header comment" {
  make_reference_repo
  printf '.users[]\n' > .installer/lib/plan.jq
  printf '# plan.awk — prints names\n{ print $1 }\n' > .installer/lib/plan.awk
  check_repo
  [ "$status" -ne 0 ]
  [[ "$output" == *"program-header: .installer/lib/plan.jq:1"* ]]
  [[ "$output" != *"plan.awk"* ]]
}

@test "tool-reference: words in strings, comments, cases and heredocs pass" {
  make_reference_repo
  cat > .installer/lib/a.sh <<'SH'
describe_tools() {
  # wc and stow are named here
  printf 'use wc instead'
  case "$1" in
    stow) rm -f x ;;
  esac
  cat <<EOT
wc of the document
EOT
}
SH
  check_repo --list
  [[ "$output" != *"wc has no"* && "$output" != *"stow has no"* ]]
}

@test "the readability-ok pragma exempts a line" {
  make_reference_repo
  printf 'wc /etc/passwd  # readability-ok: counting on purpose\n' \
    > .installer/lib/a.sh
  check_repo
  [ "$status" -eq 0 ]
}

@test "ignores program home payloads" {
  make_reference_repo
  mkdir -p .installer/programs/system/zsh/home
  printf 'wc /etc/passwd\n' > .installer/programs/system/zsh/home/x.sh
  check_repo --list
  [[ "$output" != *"zsh/home"* ]]
}

@test "a here-string is not a heredoc: code after it is still scanned" {
  make_reference_repo
  printf 'read -r first <<<"x y"\nwc /etc/passwd\n' > .installer/lib/a.sh
  check_repo --list
  [[ "$output" == *"tool-reference: .installer/lib/a.sh:2: wc has no"* ]]
}

# ── One step per line (ADR 0167) ───────────────────────────────────────────

# shape_repo: a reference repo that also lists the commands these tests use.
shape_repo() {
  make_reference_repo
  cat >> docs/tool-reference.md <<'DOC'

### `awk`
- `-f <file>` — the program file

### `sed`
- `-i` — in place

### `jq`
- `-r` — raw strings

### `sort`

### `grep`
- `-q` — quiet

### `printf`

### `true`
DOC
}

@test "inline-awk: an inline awk program fails; awk -f passes" {
  shape_repo
  cat > .installer/lib/a.sh <<'SH'
# Field one of each line.
awk '{ print $1 }' /etc/passwd
# Field one, from a commented program file.
awk -f fields.awk /etc/passwd
SH
  check_repo
  [ "$status" -ne 0 ]
  [[ "$output" == *"inline-awk: .installer/lib/a.sh:2:"* ]]
  [[ "$output" != *"a.sh:4"* ]]
}

@test "sed-form: only sed -i with one substitution passes" {
  shape_repo
  cat > .installer/lib/a.sh <<'SH'
# Turn colour on.
sed -i 's/^#Color/Color/' /etc/pacman.conf
# Print the first line.
sed -n '1p' /etc/pacman.conf
# Two edits.
sed -i 's/a/b/; s/c/d/' /etc/pacman.conf
# A pipe-delimited substitution, every match.
sed -i 's|/a|/b|g' /etc/pacman.conf
SH
  check_repo
  [ "$status" -ne 0 ]
  [[ "$output" == *"sed-form: .installer/lib/a.sh:4:"* ]]
  [[ "$output" == *"sed-form: .installer/lib/a.sh:6:"* ]]
  [[ "$output" != *"a.sh:2:"* && "$output" != *"a.sh:8:"* ]]
}

@test "pipeline-length: three pipes fail, also over continued lines" {
  shape_repo
  cat > .installer/lib/a.sh <<'SH'
# Sorted names.
printf '%s\n' b a | sort | grep -q a
printf '%s\n' b a | sort | sort | grep -q a
printf '%s\n' b a |
  sort |
  sort | grep -q a
SH
  check_repo
  [ "$status" -ne 0 ]
  [[ "$output" == *"pipeline-length: .installer/lib/a.sh:3: 3 |"* ]]
  [[ "$output" == *"pipeline-length: .installer/lib/a.sh:4: 3 |"* ]]
  [[ "$output" != *"pipeline-length: .installer/lib/a.sh:2"* ]]
}

@test "pipeline-length: a command substitution is its own pipeline" {
  shape_repo
  cat > .installer/lib/a.sh <<'SH'
# Sorted names.
names="$(printf '%s\n' b a | sort | sort)"
SH
  check_repo --list
  [[ "$output" != *"pipeline-length"* ]]
}

@test "chain-length: three && or || fail" {
  shape_repo
  cat > .installer/lib/a.sh <<'SH'
true && true || true
true && true && true || true
[[ -n x && -n y && -n z ]] && true
SH
  check_repo
  [ "$status" -ne 0 ]
  [[ "$output" == *"chain-length: .installer/lib/a.sh:2: 3 &&/||"* ]]
  [[ "$output" != *"a.sh:1:"* ]]
  [[ "$output" != *"chain-length: .installer/lib/a.sh:3"* ]]
}

@test "program-length: a long or multi-line inline jq program fails" {
  shape_repo
  cat > .installer/lib/a.sh <<'SH'
# Each user's name.
jq -r '.users[].name' "$profile"
# Each admin user's name and shell.
jq -r '.users[] | select(.admin) | .name + " " + .shell' "$profile"
# Each user's name.
jq -r '
  .users[].name
' "$profile"
SH
  check_repo
  [ "$status" -ne 0 ]
  [[ "$output" == *"program-length: .installer/lib/a.sh:4:"* ]]
  [[ "$output" == *"program-length: .installer/lib/a.sh:6:"* ]]
  [[ "$output" != *"a.sh:2:"* ]]
}

@test "what-comment: a program or a two-pipe pipeline needs a comment" {
  shape_repo
  cat > .installer/lib/a.sh <<'SH'
jq -r '.name' "$profile"
printf '%s\n' b a | sort | grep -q a
printf '%s\n' b a | sort
# shellcheck disable=SC2016
jq -r '.name' "$profile"
SH
  check_repo
  [ "$status" -ne 0 ]
  [[ "$output" == *"what-comment: .installer/lib/a.sh:1:"* ]]
  [[ "$output" == *"what-comment: .installer/lib/a.sh:2:"* ]]
  [[ "$output" == *"what-comment: .installer/lib/a.sh:5:"* ]]
  [[ "$output" != *"a.sh:3:"* ]]
}

@test "perf-reason: a perf exemption needs a measurement" {
  shape_repo
  cat > .installer/lib/a.sh <<'SH'
wc /etc/passwd  # readability-ok: perf 300ms→20ms per redraw
wc /etc/passwd  # readability-ok: perf faster
SH
  check_repo
  [ "$status" -ne 0 ]
  [[ "$output" == *"perf-reason: .installer/lib/a.sh:2:"* ]]
  [[ "$output" != *"a.sh:1:"* ]]
}
