# No Python

This repo's tooling is **bash + coreutils/awk/sed**, never Python. The installer
and VM harness must run on a minimal Arch live ISO / inside `arch-chroot`, where
assuming a Python interpreter and its stdlib is an avoidable dependency; keeping
one shell toolchain also removes a second language to maintain, lint, and reason
about.

## The rule

- **No committed `.py` files**, and no Python-shebang scripts, anywhere under the
  repo's own tooling (`.installer/`, `docs/`, helper scripts).
- **No Python invocations** in that tooling: no `python3 -c …`, `python3 -m …`,
  or piping through a `.py`. Use bash with `awk`/`sed`/`grep`/coreutils; for
  driving an interactive TUI use the same approach the TUI tests use.
- Applies to tests too (`.installer/tests/**`): a bats test must not shell out to
  Python to build fixtures or parse output — do it in awk/sed.

## Not covered (fine to keep)

- Python **package names** in host profiles / program specs — e.g.
  `python-pip`, `python-pipx`, `ruff` (a Python linter for the *user's* dev
  environment). Those provision the installed machine; they are not repo tooling.
- Neovim/editor config that references Python as a language (LSP, formatters).

## If you find Python

Convert it to bash+awk in place and update its callers + tests (the reorder-disks
and guided-fzf-smoke conversions are the worked examples). If a conversion needs
a tool that is not already a repo dependency, ground the new dependency on the
Arch Wiki first (see `arch-wiki.md`) and flag it.
