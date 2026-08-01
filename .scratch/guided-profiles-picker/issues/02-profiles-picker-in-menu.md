# Profiles picker in the guided menu

Status: done

## Parent

.scratch/guided-profiles-picker/PRD.md
ADR: docs/adr/0055-guided-profiles-picker-and-default-secret-posture.md

## What to build

The in-menu Profiles picker on top of the ticket-01 helpers. Bare `install.sh`
opens the guided menu as it does today; a **`Profiles ▸`** entry is the **first
top-screen row, above the category divider**. Enter drills to a dedicated
**Profiles screen** listing the enumerated profiles, with the selected profile's
`//` header comment in the preview pane (a missing/thin header shows the dim
`(no description — hosts/<name>/profile.jsonc)` fallback). `Esc` returns to the
top screen. Picking a profile applies the seed-merge, so every category now
reflects that profile; the operator may tweak or Proceed. Disks stay
operator-picked at Proceed. When enumeration is empty the `Profiles` entry is
omitted and the menu behaves exactly as before.

## Acceptance criteria

- [ ] `Profiles ▸` is the first top-screen row, above the terminal/category divider
- [ ] Entering it drills to a screen listing the enumerated profiles, alphabetical
- [ ] The preview pane shows the selected profile's header comment; missing/thin
      headers show the dim `(no description — …)` fallback
- [ ] `Esc` on the Profiles screen returns to the top menu (non-committal)
- [ ] Picking a profile seeds the Config State (categories reflect it) and returns
      to the top screen
- [ ] After picking, the operator can tweak any value and/or Proceed; disks are
      resolved interactively at Proceed
- [ ] The `Profiles` entry is hidden when no installable profile exists
- [ ] Menu-model behaviour covered by bats (`guided-menu.bats` prior art); the fzf
      Profiles screen is smoke-only (`tools/guided-fzf-smoke.py` prior art)

## Blocked by

- 01 — Pure core: profile enumeration + seed-merge
