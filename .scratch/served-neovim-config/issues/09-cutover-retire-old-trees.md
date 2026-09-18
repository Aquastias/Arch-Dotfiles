# 09: Cutover — swap in the served config, retire old trees

**What to build:** Disposition (c)'s final step. Once the config passes the VM
gate, make it the served editor of record and remove the superseded trees, so
the served path is never broken before it is proven.

**Blocked by:** 08.

**Status:** ready-for-agent

- [ ] The verified config is the served `dev/nvim` source; stowing/seeding lands
      it at `~/.config/nvim`.
- [ ] The old LazyVim tree at repo-root `.config/nvim` is deleted.
- [ ] `.config/nvim.bak` is deleted.
- [ ] No repo-root nvim duplicate remains that could collide with the program's
      single-source config on stow.
- [ ] ADR 0135's "both prior configs deleted once the fresh one passes the VM
      gate" is satisfied and its Status reflects implemented.
