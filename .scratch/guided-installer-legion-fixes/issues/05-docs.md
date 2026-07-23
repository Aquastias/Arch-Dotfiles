# 05 — Documentation: ADR, glossary, memory notes

Status: ready-for-agent
Type: AFK

## Parent

`.scratch/guided-installer-legion-fixes/PRD.md`

## What to build

Record the decisions once the code lands (docs follow code, per the reporter).

- A new ADR that supersedes the post-menu-password portion of ADR 0042:
  credentials are entered inside the menu and handed to the back-end via a
  dedicated tmpfs secrets file that never touches the Config State. Note the
  rejected alternatives (hashing in-menu; storing in the Config State).
- A CONTEXT.md glossary entry for **Display Label** (the human-facing name of
  a menu item, distinct from its stored Config State value). Keep it a
  glossary term only — no implementation detail.
- Update the guided-installer memory / notes to reflect: in-menu credentials,
  hybrid GPU multi-select, the latency fast-path, and the casing formatter.

## Acceptance criteria

- [ ] New ADR added, cross-referencing ADR 0042 as superseded on the
      post-menu-password point, with alternatives recorded.
- [ ] CONTEXT.md defines `Display Label` (glossary-only, no implementation).
- [ ] Guided-installer notes mention all four changes.
- [ ] No behavior change — documentation only.

## Blocked by

- `.scratch/guided-installer-legion-fixes/issues/01-display-label-formatter.md`
- `.scratch/guided-installer-legion-fixes/issues/02-hybrid-gpu-multiselect.md`
- `.scratch/guided-installer-legion-fixes/issues/03-in-menu-credentials.md`
- `.scratch/guided-installer-legion-fixes/issues/04-fzf-latency-fast-path.md`
