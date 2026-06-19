# Host breadth II — Pacman + Packages + program promotion

Status: ready-for-agent

## Parent

`.scratch/guided-installer/PRD.md`

## What to build

Add the **Pacman**, **Packages**, and **Host ▸ Advanced** content.

Pacman: `options.mirror_countries` (fzf-multi, default
Germany/Switzerland/Sweden/France/Romania) feeding `reflector --country`
in `install_base`, plus an `options.multilib` toggle (default `true`)
that makes the currently-unconditional `enable_multilib` honour the flag.

Packages: `packages.extra` typed inline, with **program promotion** — a
typed name that resolves to a `programs/<category>/<name>/` is promoted
to `system_programs` (installed via the Program Runner); non-matches stay
repo packages; a name that is both resolves as the program. Resolution is
TUI-side; the back-end contract is unchanged.

Host ▸ Advanced: `system_programs` (fzf-multi over `programs/*/*/`),
`sysctl` (swappiness pre-set to 10 from Host Core + add/override any
`key=value`), Persist Extensions, `post_install` toggles, `dotfiles_repo`.

## Acceptance criteria

- [~] `options.mirror_countries` (default 5) is emitted and drives
      `reflector --country`; offline, the picker falls back to the
      default list plus free-text. (Pass A: accessor + closed-schema +
      `reflector_country_args` wired into `install_base`. The fzf country
      picker + offline free-text fallback are Pass B.)
- [x] `options.multilib` (default true) gates `enable_multilib`.
- [x] A typed `packages.extra` name matching a program is promoted to
      `system_programs`; a non-match stays a package; an ambiguous name
      resolves as the program.
- [ ] Host ▸ Advanced edits `system_programs`, `sysctl` (swappiness 10
      default), Persist Extensions, `post_install`, `dotfiles_repo`.
      (Pass B.)
- [x] bats: emitter promotion split + the new accessors.

## Blocked by

- `01-guided-install-tracer-bullet`

## Comments

**Pass A (the tested heart) DONE via /tdd (2026-06-20); Pass B (the Guided
menu surface) deferred — user-approved scope split, mirroring issues 03/04.**

Schema/accessors (lockstep, drift-guard green): `multilib` schema row
(bool, default true) + `install_config_mirror_countries` special (string|
array union, default Germany/Switzerland/Sweden/France/Romania, one per
line). Closed schema (`profile.sh`) gains `options.multilib` +
`options.mirror_countries[]`.

Back-end (`lib/packages/list.sh`): `enable_multilib` now gates on
`install_config_multilib` (false → skips, before any pacman.conf touch);
new pure `reflector_country_args` builds `--country <comma-list>` from the
Mirror Countries selection, wired into `install_base` (offline reflector
failure still falls back to the existing mirrorlist).

Emitter (`lib/config/emit.sh`): `emit_promote_programs` — the program-
promotion split. A typed `packages.extra` name resolving to a
`programs/<cat>/<name>/` with `system:true` moves into `system_programs`
(order-preserving dedup); non-matches and `system:false` programs stay
packages; program wins on an ambiguous name. Wired into `emit_effective`
(TUI-side; back-end System-Program contract untouched). New
`tests/config/guided-promote.bats` (6).

Tests: install-config (+3 mirror_countries), packages (+3 multilib gate +
reflector args), guided-promote (6), guided-emit (+1 promotion integration)
= +13. Full suite **1191 bats**, shellcheck clean.

**Pass B (remaining):** Guided menu rows + edits — Pacman section
(mirror_countries multi, multilib bool), Packages (`packages.extra` typed
inline → promotion at emit), Host ▸ Advanced subgroup (`system_programs`
multi, `sysctl` key=value, Persist Extensions [already built], `post_install`
toggles, `dotfiles_repo`), loop label-dispatch + replay integration. fzf
shell stays smoke-only; menu-model rows are bats-tested.
