# 04 — Contract: drop the single-file seed fallback

**What to build:** With both compositors now shipping a `conf.d/` tree, remove
the tolerate-both branch added in ticket 01. `noctalia_preset_install` always
seeds the entry file plus its `conf.d/` tree, and the VM software-cursor
override always targets `conf.d/environment.<ext>`; the `chroot.sh` staging
always copies the tree. This is the contract step (ADR 0107): once no caller
relies on the old single-file shape, delete it so the seam is single-shaped with
no dead path. Pure cleanup — no behavior change for either compositor.

**Blocked by:** 02 and 03 — both compositors must be on `conf.d/` before the
fallback can be removed.

**Status:** ready-for-agent

- [ ] The single-file / entry-file-override fallback branch is removed from
      `noctalia_preset_install`; the seed unconditionally copies the entry file +
      `conf.d/` tree and appends the VM override to `conf.d/environment.<ext>`.
- [ ] The `chroot.sh` "when present" guard around `conf.d/` staging is dropped
      (or reduced to the single-source repo check), since the tree now always
      exists.
- [ ] Any adapter-test fixture still exercising the single-file path is removed
      or converted to the tree path; the full bats suite stays green.
- [ ] `niri validate` and `Hyprland --verify-config` still pass; a fresh box of
      either compositor seeds and boots unchanged.
