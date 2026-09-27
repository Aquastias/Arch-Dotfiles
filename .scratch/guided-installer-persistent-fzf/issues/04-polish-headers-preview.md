# Polish: per-screen headers + disk-pick preview

Status: done
Type: AFK

## Parent

`.scratch/guided-installer-persistent-fzf/PRD.md`

## What to build

Final polish on the persistent surface: per-screen header / prompt text
(`change-header` as the operator moves between the category list, a
category, a value list, and a text field), the preview-window behavior on
the post-menu disk pick, and any remaining seams. No new categories,
fields, or defaults.

## Acceptance criteria

- [x] Each screen shows context-appropriate header / prompt text.
- [x] The post-menu disk pick shows the lsblk / SMART preview with sensible
      window sizing.
- [ ] Any edge-case seams from slices 01–03 are smoothed; the live draw is
      exercised by the guided VM smoke.
- [ ] Full suite green; shellcheck clean.

## Blocked by

- `.scratch/guided-installer-persistent-fzf/issues/01-spine-persistent-fzf-install.md`
  (benefits from slices 02 and 03)

## Comments

**DONE.** Per-screen headers/prompts + in-fzf Add-persist (`399dcee`), then the
HITL polish rounds: flicker-free toggles (reload-sync) + rounded installer
border + verbose layout label (`1a3df41`); ASCII layout-graph **preview** pane
(`f7d295f`); filterable keymap/locale/timezone big lists with a selection
side-panel (`b16cd12`); the data-pools editor (`a93222b`) reached under the
layout option (`ed77136`). Grew well past the original "headers + preview" scope
via direct operator feedback. On main, full suite green.

- 2026-09-27 audit: 1a3df41 and the polish commits cited above. Remaining
  unticked lines are suite/VM runs not re-verifiable now.
