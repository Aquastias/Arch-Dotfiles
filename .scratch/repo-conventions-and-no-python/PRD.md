# PRD: Repo conventions + no-Python purge (retroactive)

Status: done

Retroactive record — shipped without a grill session. Anchored by
[[ADR 0092]] (`.os` → `.installer`); rules live in
`docs/agents/conventions.md` and `docs/agents/no-python.md`.

## What shipped

- `.os/` renamed `.installer/`, `OS_DIR` → `INSTALLER_DIR` (ADR 0092).
- `command_exists` helper replaces inline `command -v`.
- `guided-*` modules folded into `lib/guided/` (prefix dropped).
- Tooling scripts get a `.sh` extension (exceptions: git hooks,
  PATH-installed commands, `.zsh` config, bats `.bash` helpers).
- VM fixture users nested under `.installer/users/vm/`.
- All Python removed from the VM harness (reorder-disks, yaml parsing,
  http.server → socat, greetd path, PTY smoke harness); enforced by
  `.installer/tests/no-python.sh`.
- All shellcheck warnings cleared.

## Commits

4ca4dcc, 197598b, d48c26b, 46c9f44, 698d487, 5e7fce5, 7edb9b9, 30e2eca,
dbb6ff5, 51d7a0d, 7430f73, cfa9cb2, 0938a96, d7c3e82.
