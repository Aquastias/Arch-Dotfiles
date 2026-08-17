Status: ready-for-agent

# Font Catalog: curated multi-select under General

## Parent

`.scratch/bluetooth-power-fonts-toggles/spec.md` (ADR 0080)

## What to build

Add `options.fonts` — a curated multi-select font list modelled on the
Kernels multi-select — as a leaf in the **General Category** of the Guided
Installer. The operator TAB-checks fonts from an enumerated option set; some
are pre-checked, and default-off fonts still appear as unchecked-but-checkable
rows. The selection resolves to packages before pacstrap.

This **replaces** `packages.repo.fonts` as the single font home: remove that
block from Host Core so the catalog's defaults are the shared baseline, and
the desktop/laptop profiles inherit fonts through it. The font resolver is
repo+AUR aware — repo fonts join the pacstrap set, and the lone AUR entry
(`ttf-ms-fonts`) routes to the Primary User's paru pass.

Default-checked: `noto-fonts`, `noto-fonts-emoji`, `noto-fonts-cjk`,
`noto-fonts-extra`, `ttf-liberation`, `ttf-dejavu`, `ttf-ms-fonts`,
`ttf-jetbrains-mono-nerd`, `ttf-iosevka-nerd`, `ttf-firacode-nerd`.
Selectable-but-off: `otf-monaspace-nerd`, `ttf-sazanami`. Plain
`ttf-fira-code` is dropped in favour of `ttf-firacode-nerd`.

End-to-end path: schema allowlist key → typed accessor → seed default →
menu field (General leaf) + `menu_enum_options` entry → pure resolver →
package resolution incl. AUR routing → matrix Axis Registry classification.

## Acceptance criteria

- [ ] `options.fonts` is a General-Category leaf rendering as a multi-select
      of the enumerated catalog, comma-joined, with override dots.
- [ ] The default-checked set matches the spec; `otf-monaspace-nerd` and
      `ttf-sazanami` appear unchecked but selectable.
- [ ] Checked repo fonts land in the pacstrap set; `ttf-ms-fonts` is routed
      to the Primary User's paru pass (not pacstrap).
- [ ] `packages.repo.fonts` is removed from Host Core; a default install
      still yields the default font set through the catalog.
- [ ] Plain `ttf-fira-code` no longer installs; `ttf-firacode-nerd` does.
- [ ] `options.fonts` is classified `inert|light` in the matrix Axis
      Registry (generator no longer aborts).
- [ ] Choices equal to defaults normalise out; a saved profile stores only
      the delta over Host Core.
- [ ] `fonts.bats` (pure resolver spec) and a `guided-menu.bats` extension
      pass under `tests/run.sh --fast`.

## Blocked by

- None - can start immediately
