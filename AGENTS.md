## Agent skills

### Issue tracker

Issues live as markdown files under `.scratch/` in this repo. See `docs/agents/issue-tracker.md`.

### Triage labels

Default label strings (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context repo: one `CONTEXT.md` + `docs/adr/` at root. See `docs/agents/domain.md`.

### Comment style

Installer (`.installer/`) comments are compact: keep the non-obvious *why* + its `(ADR NNNN)` anchor, cut code-restatement and ADR duplication. See `docs/agents/comment-style.md`.

### Arch Wiki grounding

Package/config/service decisions trace to the Arch Wiki — fetch the page, don't recall it. Covers program specs (`.installer/programs/`, per `PROGRAM_SPEC.md`) and bare `packages.*` additions. See `docs/agents/arch-wiki.md`.

### Shell commons

Reuse a Commons helper before writing a new one; put new helpers in the right world (Installer Stdlib vs Shell Stdlib) and don't merge across execution-context boundaries. See `docs/agents/shell-commons.md`.

### No Python

Repo tooling is bash + awk/sed/coreutils — never Python. No committed `.py` files, no `python3 -c`/`-m` in `.installer/` (incl. tests). Python package names in host profiles are fine. See `docs/agents/no-python.md`.

### Repo conventions

Exactly one `.claude/` (repo root; the dev/claude `home/.claude/` seed payload is the sole exception). Shell scripts the tooling runs/sources end in `.sh` — except git hooks, PATH-installed commands, `.zsh` config, and bats `.bash` `load` helpers. See `docs/agents/conventions.md`.

### VM sandbox

`vm.sh`/`virsh` talk to libvirtd over a socket the command sandbox often blocks. On a `libvirt unreachable (sandbox?)` signal, retry the same command with the sandbox disabled. See `docs/agents/vm-sandbox.md`.

### VM agent control

Drive a persistent debug VM (login/logout/reboot, session-switch, screenshot, run/launch apps, lock) via `.installer/vm/vm-agent.sh` instead of hand-rolling `virsh`/`ssh`/`grim`. Qt theming tests use a KDE app (Dolphin); GTK tests use any GTK app. See `docs/agents/vm-agent-control.md`.
