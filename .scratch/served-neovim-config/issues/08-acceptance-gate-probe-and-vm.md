# 08: Acceptance gate — headless probe + VM verify-block

**What to build:** Seam B. A single `nvim --headless -l <probe>` entrypoint that
boots the real served config and asserts observable state, wired into the VM
harness verify-block so the arch-combined VM is the acceptance gate and its
screenshots match the approved prototype.

**Blocked by:** 02, 03, 04, 05, 06, 07.

**Status:** ready-for-agent

- [ ] Probe asserts `follow_noctalia == false`, active colorscheme is Catppuccin
      Mocha, and the accent highlight resolves to sapphire `#74c7ec`.
- [ ] Probe asserts that rewriting the generated theme file re-applies it (the
      follow path from ticket 07).
- [ ] VM verify-block runs `:checkhealth` and asserts **zero ERROR** and every
      in-scope LSP resolves on `PATH`; benign WARNs (optional Swift, disabled
      providers) are allowed.
- [ ] Arch-combined VM screenshots match `.scratch/nvim-prototype/prototype.html`
      across the 13 screens.
