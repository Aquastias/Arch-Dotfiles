# Free-text entry via the fzf query line

Status: done
Type: AFK

## Parent

`.scratch/guided-installer-persistent-fzf/PRD.md`

## What to build

Replace the temporary one-shot prompt from slice 01 with **in-window
free-text capture**. On a free-text field (hostname, swap / ESP sizes,
package names, sysctl pairs, persist paths, URLs), the controller switches
the prompt to the field's label and the operator types into fzf's own
query line; a `transform` bind captures the query into the override-state
file and re-paints back to the field list. Editing never leaves the
window.

## Acceptance criteria

- [ ] Every free-text field is editable by typing into the menu's input
      line; the value commits to the Config State on confirm.
- [ ] No free-text field drops to a separate prompt or flashes the
      terminal.
- [ ] The current value is shown as a hint while editing; empty input
      no-ops (keeps the prior / seeded value).
- [ ] Controller bats cover query-capture → setter → state (no fzf).
- [ ] The `--guided` replay path is unchanged; full suite green; shellcheck
      clean.

## Blocked by

- `.scratch/guided-installer-persistent-fzf/issues/01-spine-persistent-fzf-install.md`

## Comments

**DONE `35ac66c`.** Text fields type into fzf's own query line (an `enter`
transform passes `{q}`, captured by `_ctl_apply_text`) — no `execute()`, no
terminal drop. Per-screen `change-header`/`change-prompt` so every screen says
how to go back. Verified by `guided-controller.bats` + a headless walk through
the real entry script.
