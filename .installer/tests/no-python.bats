#!/usr/bin/env bats
# Gate for the "no Python, not even inline" policy (docs/agents/no-python.md).
# The headline test runs the checker against THIS repo and asserts it is clean;
# the rest build throwaway git repos to prove each check catches / allows the
# right thing — including the jq `def …:` look-alike that must NOT trip it.

CHECK="$BATS_TEST_DIRNAME/no-python.sh"

# mk_repo: cd into a fresh git repo. Write fixture files, then call check_repo.
mk_repo() {
  REPO="$(mktemp -d)"
  cd "$REPO"
  git init -q
  git config user.email t@t
  git config user.name t
}
check_repo() {
  git add -A
  run bash -c "cd '$REPO' && bash '$CHECK'"
}
teardown() { [[ -n "${REPO:-}" ]] && rm -rf "$REPO"; return 0; }

@test "this repo is clean" {
  run bash "$CHECK"
  [ "$status" -eq 0 ]
}

@test "catches a committed .py file" {
  mk_repo
  printf 'x=1\n' > tool.py
  check_repo
  [ "$status" -ne 0 ]
  [[ "$output" == *"committed Python file: tool.py"* ]]
}

@test "catches a python shebang" {
  mk_repo
  printf '#!/usr/bin/env python3\n' > run
  chmod +x run
  check_repo
  [ "$status" -ne 0 ]
  [[ "$output" == *"Python shebang: run"* ]]
}

@test "catches an inline python invocation in a shell script" {
  mk_repo
  printf '#!/bin/bash\npython3 -m http.server\n' > s.sh
  check_repo
  [ "$status" -ne 0 ]
  [[ "$output" == *"Python invocation: s.sh"* ]]
}

@test "catches pip and uv invocations" {
  mk_repo
  printf '#!/bin/bash\npip install x\nuv run y\n' > s.sh
  check_repo
  [ "$status" -ne 0 ]
}

@test "allows a jq def look-alike (regression: picker.sh)" {
  mk_repo
  cat > s.sh <<'EOF'
#!/bin/bash
jq -n 'def assign($k): .[$k] // [] end; {} | assign("a")'
EOF
  check_repo
  [ "$status" -eq 0 ]
}

@test "allows python package names as pacman args" {
  mk_repo
  printf '#!/bin/bash\npacman -S python-pip python-pygments python-debugpy\n' \
    > s.sh
  check_repo
  [ "$status" -eq 0 ]
}

@test "allows python named only in a comment" {
  mk_repo
  printf '#!/bin/bash\n# replaces python3 -m http.server (no python here)\n' \
    > s.sh
  check_repo
  [ "$status" -eq 0 ]
}

@test "the no-python-ok pragma exempts a line" {
  mk_repo
  printf '#!/bin/bash\npython3 gen  # no-python-ok: doc generator stub\n' > s.sh
  check_repo
  [ "$status" -eq 0 ]
}
