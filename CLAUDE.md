## Agent skills

### Issue tracker

Issues live as markdown files under `.scratch/` in this repo. See `docs/agents/issue-tracker.md`.

### Triage labels

Default label strings (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context repo: one `CONTEXT.md` + `docs/adr/` at root. See `docs/agents/domain.md`.

### Comment style

Installer (`.os/`) comments are compact: keep the non-obvious *why* + its `(ADR NNNN)` anchor, cut code-restatement and ADR duplication. See `docs/agents/comment-style.md`.

### Arch Wiki grounding

Package/config/service decisions trace to the Arch Wiki — fetch the page, don't recall it. Covers program specs (`.os/programs/`, per `PROGRAM_SPEC.md`) and bare `packages.*` additions. See `docs/agents/arch-wiki.md`.
