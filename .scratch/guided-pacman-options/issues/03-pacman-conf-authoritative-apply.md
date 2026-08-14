# 03 — Authoritative pacman.conf apply before pacstrap

**What to build:** the resolved Pacman options are written authoritatively into
the host `/etc/pacman.conf` before pacstrap, so both the base install and the
booted target reflect the operator's toggles. The apply step is authoritative
over the managed set only: an ON flag is uncommented/written, an OFF flag is
commented/removed, `ParallelDownloads` is set to the chosen N, and `ILoveCandy`
(absent from Arch's stock config) is appended when on and removed when off.
Unrelated lines (`SigLevel`, includes, optional-repo and custom-repo blocks) are
left untouched, and the mutated file is inherited by the target through the
existing chroot copy. See ADR 0074.

**Blocked by:** 01 — options.pacman.* config-state foundation.

**Status:** ready-for-agent

- [ ] A new apply step runs in `install_base` alongside `enable_optional_repos`,
      before pacstrap, editing the host `/etc/pacman.conf` `[options]` block.
- [ ] ON toggles produce their uncommented flag line; OFF toggles are commented
      out / absent — even when the ISO shipped the flag enabled (authoritative).
- [ ] `ParallelDownloads = N` reflects the operator's value.
- [ ] `ILoveCandy` is appended when on and removed/commented when off (it is not
      shipped in Arch's default `pacman.conf`).
- [ ] `SigLevel`, `Include` lines, optional-repo blocks, and custom-repo blocks
      are never modified by this step.
- [ ] The step is idempotent — running it twice yields the same file.
- [ ] The mutated host `pacman.conf` is inherited by the target (existing copy);
      no separate target-side pass is added.
- [ ] Seam 2: a new bats runs the apply function against a fixture `[options]`
      block and asserts the resulting file for on/off/numeric/append cases plus
      idempotency and the untouched-lines guarantee.
