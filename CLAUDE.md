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

### VM sandbox

`vm.sh`/`virsh` talk to libvirtd over a socket the command sandbox often blocks. On a `libvirt unreachable (sandbox?)` signal, retry the same command with the sandbox disabled. See `docs/agents/vm-sandbox.md`.
