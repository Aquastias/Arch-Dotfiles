# 07: Feature Audit probe

**What to build:** An Audit Run proves the [[Emacs Config]] on a real host
(ADR 0152 contract, prior art: the nvim and vscodium probes). The probe
requires the package, runs as the user, and checks: Emacs runs; the seeded
Doom config exists; the Doom clone is at the pinned commit; `doom doctor`
reports no errors; each planned bind in an audit binds file resolves to its
command via `emacs --batch` with Doom loaded.

**Blocked by:** 03 (Keymaps), 04 (Theme), 05 (Org and REST), 06 (Debuggers).

**Status:** ready-for-agent

- [x] Probe follows the program-spec audit contract; skips cleanly when emacs
      is not installed
- [x] Pin check reads the same pin data file install.sh uses
- [x] Binds file covers representative binds from tickets 03–06
- [ ] Known-noise entries (if any) documented like other probes'
- [ ] Audit Run on the VM: all emacs checks pass; output in Comments

## Comments

- emacs is a registered program bind source: `binds-emacs.awk` parses
  config.el's `map!` forms (state keywords, `:leader`, `nil` unbinds), so
  every shipped bind (90) is planned — not a representative subset — and
  `check` fails on one without an expectation.
- One catch-all expectation, `resolves` = the chord's `key-binding` (in a
  buffer in that evil state, unremapped) is the configured command. Judged
  in one throwaway `emacs --daemon` running the user's real Doom
  (`audit-fixtures/binds.el`).
- `doom doctor` always exits 0, so the probe judges its summary
  ("There is/are N error(s)!", "Attempt to load DOOM failed"); warnings pass.
- The pin reaches the probe as `audit-fixtures/doom-ref`, a symlink to the
  program's pin (staged with `cp -rL`, vscodium's pattern).
- Probe dry-run with stubs (no Emacs on the host): plan → 90 TSV rows, ids
  unique (`gsa` is bound in normal and visual). Known noise: none yet; the
  VM Audit Run decides.
