# 01 — Expand the seed to tolerate a `conf.d/` tree

**What to build:** The curated-config seed path learns to deliver a `conf.d/`
part-file tree, without requiring one yet. `noctalia_preset_install` seeds the
compositor entry file **plus** a sibling `conf.d/` directory *when that
directory is present in the staged curated dir*, and points the VM-only
software-cursor override at `conf.d/environment.<ext>` when the tree exists,
falling back to today's behavior (single entry file, override appended to the
entry file) when it does not. `chroot.sh` staging likewise copies a `conf.d/`
tree into each curated dir when present. No repo config is split in this
ticket — both `config.kdl` and `hyprland.lua` still ship as single files — so a
fresh install is byte-identical to today and the whole existing suite stays
green. This is the expand step (ADR 0107): the new shape is added beside the old
so nothing breaks.

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [ ] `noctalia_preset_install` seeds the entry file and, when a sibling
      `conf.d/` exists in the curated dir, the whole `conf.d/` tree into
      `/etc/skel`; when absent, it seeds only the entry file exactly as before.
- [ ] The VM software-cursor override appends to the seeded
      `conf.d/environment.<ext>` when the tree is present, else to the seeded
      entry file (unchanged branch-by-extension: niri `debug{ … }`, Hyprland
      `hl.config({ cursor = … })`).
- [ ] `chroot.sh` stages a `conf.d/` tree into the niri and Hyprland curated
      dirs when one is present in the repo, alongside the entry file; no-op when
      absent.
- [ ] The adapter tests gain coverage proving the tree path: a fixture curated
      dir with a `conf.d/` seeds the tree to skel and lands the VM override in
      `conf.d/environment`.
- [ ] Every pre-existing bats test (`niri-adapter`, `hyprland-adapter`,
      `noctalia-stow`) stays green — no repo config changed, so the single-file
      path is unchanged.
