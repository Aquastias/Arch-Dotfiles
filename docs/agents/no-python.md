# No Python

This repo's tooling is **bash + coreutils/awk/sed**, never Python. The installer
and VM harness must run on a minimal Arch live ISO / inside `arch-chroot`, where
assuming a Python interpreter and its stdlib is an avoidable dependency; keeping
one shell toolchain also removes a second language to maintain, lint, and reason
about.

## The rule

- **No committed `.py` files**, and no Python-shebang scripts, anywhere in the
  repo — not just `.installer/`.
- **No Python invocations** in any shell script: no `python`/`python3 -c`/`-m`,
  `pip`, `pipx`, `poetry`, `pyenv`, `uv`, or piping through a `.py`. Use bash with
  `awk`/`sed`/`grep`/coreutils; for driving an interactive TUI use the same
  approach the TUI tests use.
- Applies to tests too (`.installer/tests/**`): a bats test must not shell out to
  Python to build fixtures or parse output — do it in awk/sed.

## Enforcement

`.installer/tests/no-python.sh` is the gate (test: `no-python.bats`, in the
`--fast` set, so the pre-push hook runs it). It scans **tracked files only** for
the three signals above, keying on what *executes* python — extension, shebang,
command — never on syntax (jq's `def f($k): … end;` reads like Python but is
data to `jq`, so it passes). Package names, editor/prompt config, and
prose/comments naming python are untouched. A line the heuristic can't tell
apart is exempted with a trailing `no-python-ok` comment.

## Not covered (fine to keep)

- Python **package names** in host profiles / program specs — e.g.
  `python-pip`, `python-pipx`, `ruff` (a Python linter for the *user's* dev
  environment). Those provision the installed machine; they are not repo tooling.
- Neovim/editor config that references Python as a language (LSP, formatters).

## If you find Python

Convert it to bash+awk in place and update its callers + tests (the
`reorder-disks.sh` conversion — libvirt-XML surgery in awk — is the worked
example). A tool that
only made sense in Python and can't be cleanly ported (e.g. a PTY-driving smoke
harness) is removed rather than half-ported. If a conversion needs a tool that is
not already a repo dependency, ground the new dependency on the Arch Wiki first
(see `arch-wiki.md`) and flag it.
