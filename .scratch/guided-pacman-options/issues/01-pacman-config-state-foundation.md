# 01 — options.pacman.* config-state foundation

**What to build:** the six `options.pacman.*` settings exist end-to-end at the
data layer, so the rest of the feature has a validated place to store and read
them. A hand-authored Host Profile carrying any of them validates against the
closed schema instead of aborting on an unknown key; the back-end reads each
option with its default; and the guided baseline seeds the intended defaults.
This is the shared foundation both the menu (02) and the apply step (03) build
on. See ADR 0074 and the **Pacman Options** glossary term.

The six keys (snake_case, matching `optional_repos` / `esp_size`):

- `options.pacman.ilovecandy` — bool, default `true`
- `options.pacman.color` — bool, default `true`
- `options.pacman.verbose_pkg_lists` — bool, default `true`
- `options.pacman.disable_download_timeout` — bool, default `false`
- `options.pacman.no_progress_bar` — bool, default `false`
- `options.pacman.parallel_downloads` — int, default `5`

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [ ] The closed-schema allowlist admits all six `options.pacman.*` paths; a
      profile carrying them validates, and an unknown `options.pacman.*` key
      still aborts with its path.
- [ ] Accessors expose each option (five bool, one scalar) returning the
      operator value when set and the documented default otherwise.
- [ ] Accessor read-paths and the closed-schema allowlist stay in lockstep — the
      existing schema drift guard passes with the new paths.
- [ ] The guided seed sets `ilovecandy`, `color`, `verbose_pkg_lists` on and
      `parallel_downloads = 5`; the two opt-in flags remain off/unseeded.
- [ ] If the combination-matrix registry gates operator-facing option paths, it
      carries `options.pacman.*` entries consistent with `options.optional_repos`.
- [ ] Bats cover: profile validation (accept + reject), accessor reads +
      defaults, and the seeded defaults. Prior art:
      `tests/config/install-config.bats`, `tests/config/guided-seed.bats`.
- [ ] `CheckSpace` and `multilib` are NOT added — excluded by design (ADR 0074).
