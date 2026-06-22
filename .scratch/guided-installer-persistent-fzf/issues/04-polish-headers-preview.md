# Polish: per-screen headers + disk-pick preview

Status: ready-for-agent
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

- [ ] Each screen shows context-appropriate header / prompt text.
- [ ] The post-menu disk pick shows the lsblk / SMART preview with sensible
      window sizing.
- [ ] Any edge-case seams from slices 01–03 are smoothed; the live draw is
      exercised by the guided VM smoke.
- [ ] Full suite green; shellcheck clean.

## Blocked by

- `.scratch/guided-installer-persistent-fzf/issues/01-spine-persistent-fzf-install.md`
  (benefits from slices 02 and 03)
