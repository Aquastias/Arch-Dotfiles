# Guided Installer: Pacman Options category

Status: ready-for-agent

Adds a dedicated **Pacman** Configuration Category to the Guided Installer,
surfacing the pacman `[options]` block flags as toggle/text rows and applying
them authoritatively to `/etc/pacman.conf`. See ADR 0074 and the **Pacman
Options** glossary term in `CONTEXT.md`.

## Problem Statement

As an operator using the Guided Installer, I can already tune mirrors, optional
repos, and custom repos — but I have no way to set the ordinary pacman
`[options]` niceties (the Pac-Man progress bar, coloured output, verbose package
lists, parallel downloads). After every install I edit `/etc/pacman.conf` by
hand to turn on `ILoveCandy` and friends. The installer should let me pick these
up front, the same way every other section is configured, so a fresh system
already has my preferred pacman behaviour.

## Solution

A new top-level **Pacman** Configuration Category, placed immediately after
Mirrors & Repositories (both edit `pacman.conf`). It lists the pacman
`[options]` flags as rows in the same style as other sections — bool toggles
plus one numeric field — with sensible defaults, `ILoveCandy` on out of the box.
The chosen values are written authoritatively into the host `/etc/pacman.conf`
before pacstrap and inherited by the target via the existing pacman.conf copy,
so the installed system boots with exactly the pacman behaviour selected.

## User Stories

1. As an operator, I want a Pacman category in the Guided Installer menu, so
   that pacman `[options]` settings live in one obvious place like every other
   section.
2. As an operator, I want the Pacman category to sit right after Mirrors &
   Repositories, so that all `pacman.conf` concerns are adjacent in the menu.
3. As an operator, I want `ILoveCandy` enabled by default, so that a fresh
   install has the Pac-Man progress bar without me touching anything.
4. As an operator, I want `Color` enabled by default, so that pacman output is
   coloured (and `ILoveCandy` renders as intended).
5. As an operator, I want `VerbosePkgLists` enabled by default, so that upgrade
   and downgrade tables are detailed from the first boot.
6. As an operator, I want `DisableDownloadTimeout` available but off by default,
   so that I can opt into tolerating slow mirrors without it being forced on.
7. As an operator, I want `NoProgressBar` available but off by default, so that
   I keep progress bars unless I deliberately silence them.
8. As an operator, I want a `ParallelDownloads` numeric field defaulting to 5,
   so that pacman downloads several packages at once without me editing config.
9. As an operator, I want each Pacman row rendered like the toggles in the
   Security section, so that the interaction is familiar (Enter to flip, Esc to
   go back).
10. As an operator, I want the `ParallelDownloads` row to be a free-text/numeric
    field like `esp size`, so that I can type the exact concurrency I want.
11. As an operator, I want an overridden Pacman value to show the `●` override
    marker, so that I can see at a glance which pacman settings I have changed
    from the defaults.
12. As an operator, I want my Pacman choices persisted in the Config State under
    `options.pacman.*`, so that they survive a save/replay of the guided config.
13. As an operator authoring a Host Profile by hand, I want `options.pacman.*`
    to validate against the closed schema, so that a typo in a pacman key aborts
    with its path instead of being silently ignored.
14. As an operator, I want the installer to apply my Pacman toggles
    authoritatively to `/etc/pacman.conf`, so that an OFF toggle actually
    disables a flag the ISO shipped enabled, not just fails to enable it.
15. As an operator, I want Pacman options applied before pacstrap, so that
    `Color`, `ParallelDownloads`, and `ILoveCandy` take effect during the base
    install, not only afterwards.
16. As an operator, I want the applied `pacman.conf` inherited by the installed
    target, so that the system I boot into keeps the same pacman behaviour
    without a second configuration pass.
17. As an operator, I do NOT want a `CheckSpace` toggle, so that the Pacman
    section never fights the installer's deliberate `disable_checkspace` on the
    ZFS path.
18. As an operator, I want `multilib` to stay under Optional Repositories, so
    that repo selection is not duplicated across two sections.
19. As an operator, I want unrelated `pacman.conf` lines (`SigLevel`, includes,
    custom repos) left untouched by the Pacman apply step, so that mirror and
    repo configuration is never clobbered.
20. As an operator running the guided flow in replay/non-interactive mode, I
    want the Pacman fields editable via the same replay editors as other
    fields, so that scripted installs can set them too.
21. As a maintainer, I want the Pacman rows driven by the existing menu field
    table, so that adding the category is data, not a new rendering path.
22. As a maintainer, I want the apply step to be idempotent, so that re-running
    the installer converges `pacman.conf` to the same state.

## Implementation Decisions

- **New Configuration Category "Pacman"**, inserted in the menu model's category
  list directly after "Mirrors & Repositories". The category name matches the
  `section` on its field rows, so the category aggregates its rows exactly like
  every other section (ADR 0071 taxonomy).
- **Config State schema** — a new `options.pacman` object with snake_case
  leaves, matching the existing convention (`optional_repos`, `esp_size`):
  - `options.pacman.ilovecandy` — bool, default `true`
  - `options.pacman.color` — bool, default `true`
  - `options.pacman.verbose_pkg_lists` — bool, default `true`
  - `options.pacman.disable_download_timeout` — bool, default `false`
  - `options.pacman.no_progress_bar` — bool, default `false`
  - `options.pacman.parallel_downloads` — int, default `5`
- **Menu field table** gains six rows (`section|path|label|default`) under the
  Pacman section — five bool toggles and one numeric/text field. Defaults live
  here as the single source of truth for the displayed value.
- **Accessor layer** gains matching `_INSTALL_CONFIG_SCHEMA` entries (five
  `bool`, one `scalar`) plus read accessors, so the back-end reads each pacman
  option with its default. Accessor read-paths and the closed-schema allowlist
  must stay in lockstep (an existing drift guard enforces this).
- **Closed-schema allowlist** (host profile schema) gains the six
  `options.pacman.*` paths, so hand-authored profiles validate.
- **Guided seed defaults** seed the three on-by-default toggles and
  `parallel_downloads = 5`, so the guided baseline reflects the intended
  defaults before any operator edit.
- **Controller field-kind dispatch** maps the five bool paths to the `toggle`
  editor and `parallel_downloads` to the `text` editor (the same kind as
  `esp_size`). Replay editors gain the corresponding bool/numeric editors so the
  non-interactive guided path can set them.
- **Apply step** — a new function in the package-install module, invoked in
  `install_base` alongside `enable_optional_repos`, before pacstrap. It is
  **authoritative** over the managed set only: for each of the five flags it
  uncomments/writes the line when the option is on and comments it out when off;
  it sets `ParallelDownloads = N`; it appends `ILoveCandy` (not shipped in
  Arch's default `pacman.conf`) when on and removes/comments it when off. It
  edits the `[options]` block in place and never touches `SigLevel`, includes,
  optional-repo blocks, or custom-repo blocks. The mutated host `pacman.conf` is
  inherited by the target through the existing chroot copy.
- **Explicit exclusions**: `CheckSpace` is not exposed (the ZFS path
  force-disables it via `disable_checkspace`); `multilib` stays under Optional
  Repositories (ADR 0072).
- **Combination matrix**: if the matrix registry gates new operator-facing
  option paths, add `options.pacman.*` entries consistent with how
  `options.optional_repos` is registered.

## Testing Decisions

Good tests here assert **external behaviour** at a seam, not internals: given a
Config State (or a fixture `pacman.conf`), assert the observable output (the
menu rows, or the resulting file contents). No test should reach into private
helpers.

- **Seam 1 — Menu model** (`menu_rows` / `menu_categories`, pure JSON→JSON).
  Assert the Pacman category appears after Mirrors & Repositories; that its six
  rows surface with the right labels, kinds, and defaults; that an override sets
  the `●` flag; and that an unset field shows its default with no `●`. Prior
  art: `tests/config/guided-menu.bats`, `tests/config/menu-enum.bats`.
- **Seam 2 — `pacman.conf` apply** (new). Run the apply function against a
  fixture `[options]` block and assert the resulting file: ON flags uncommented/
  present, OFF flags commented/absent, `ParallelDownloads` set to the chosen N,
  `ILoveCandy` appended when on and gone when off, and `SigLevel`/includes/repo
  blocks untouched. Assert idempotency (running twice yields the same file).
  This is a new bats file; prior art for file-mutation-against-fixture style:
  the chroot/impermanence bats and the pacman.conf handling already exercised in
  the package module.
- **Existing data-driven seams auto-cover the rest** with added cases, not new
  files: the closed-schema drift guard (accessor read-paths ⊆ schema allowlist),
  the guided seed defaults (`tests/config/guided-seed.bats`), the accessor reads
  (`tests/config/install-config.bats`), and controller kind dispatch
  (`tests/config/guided-controller.bats`).

## Out of Scope

- Any pacman `[options]` key not in the agreed set: `CheckSpace` (ZFS
  force-disables), `UseSyslog`, `NoProgressBar`... — only the six listed fields.
  (`NoProgressBar` IS in scope; `UseSyslog`, `DownloadUser`, `DisableSandbox`,
  `CleanMethod` are not.)
- `multilib` / testing repos — owned by Optional Repositories (ADR 0072).
- `CleanMethod` — already managed by the installer post-pacstrap; not exposed.
- Custom mirror servers / custom repositories — already shipped (ADR 0072).
- Per-repo `[options]` beyond the global block.
- Validating that a mirror actually honours `DisableDownloadTimeout` at runtime.

## Further Notes

- ADR 0074 records the category placement and the authoritative-apply decision;
  the **Pacman Options** glossary term in `CONTEXT.md` is the canonical
  vocabulary.
- Arch's stock `pacman.conf` ships `Color`, `VerbosePkgLists`, and
  `ParallelDownloads` as commented/`ParallelDownloads = 5` lines but does NOT
  ship `ILoveCandy` at all — the apply step must append it rather than
  uncomment, and comment/remove it when the toggle is off.
