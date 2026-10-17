## Agent skills

### Issue tracker

Issues live as markdown files under `.scratch/` in this repo. See `docs/agents/issue-tracker.md`.

### Triage labels

Default label strings (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context repo: one `CONTEXT.md` + `docs/adr/` at root. See `docs/agents/domain.md`.

### Coding standards

Review judgement calls (comments, helper placement, ADRs, docs) live in
`CODING_STANDARDS.md`. Mechanical rules are lints the pre-commit gate runs
(`.githooks/pre-commit`); when it fails, fix the reported `rule: file:line`.
Installer naming/size/tool rules: `docs/agents/readability.md`. Tooling is
bash + awk/sed, never Python (`docs/agents/no-python.md`). Layout: one
`.claude/`, `.sh` on tooling scripts (`docs/agents/conventions.md`).

### Arch Wiki grounding

Package/config/service decisions trace to the Arch Wiki — fetch the page, don't recall it. Covers program specs (`.installer/programs/`, per `PROGRAM_SPEC.md`) and bare `packages.*` additions. See `docs/agents/arch-wiki.md`.

### Shell commons

Reuse a Commons helper before writing a new one, in the right world (Installer
Stdlib vs Shell Stdlib). See `docs/agents/shell-commons.md`.

### VM work

You verify in the VM yourself, one VM at a time: `vm-agent.sh status` first,
reuse the VM it shows, `stop` it when done. Drive it with
`.installer/vm/vm-agent.sh` (session, screenshot, apps; Qt tests use Dolphin):
`docs/agents/vm-agent-control.md`. Run VM commands with the sandbox disabled —
it hides `/dev/kvm` and guest SSH: `docs/agents/vm-sandbox.md`.
