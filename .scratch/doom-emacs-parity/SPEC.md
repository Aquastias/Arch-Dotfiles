# Spec: Doom Emacs as an opt-in parity twin of the Neovim Config

Status: done (fleet Audit Run pending — see issues/08)

Anchors: ADR 0160 (this decision), ADR 0148 (the parity contract, VSCodium
precedent), ADR 0134 (program `home/` + Config Apply), ADR 0135/0140
(system-package toolchain), ADR 0141 (Language Registry), ADR 0104
(seed-only Noctalia outputs). Glossary: [[Emacs Config]], [[Editor Coverage
Map]], [[Neovim Config]], [[VSCodium Config]], [[Language Registry]],
[[User Program]].

## Problem Statement

The operator wants Emacs, specifically Doom Emacs, on the desktop and laptop,
behaving like the [[Neovim Config]] they already know: same languages, same
toolchain, same `SPC` leader muscle memory. Today the fleet installs no Emacs
at all, and a hand-installed Doom would use its own key map, download its own
language servers, ignore Noctalia and drift from nvim the moment a language is
added. VSCodium already solved this for a GUI editor; Emacs has no equivalent.

## Solution

A new opt-in `dev/emacs` [[User Program]] in the operator's User Profile, so
it lands on desktop, laptop and the VM fixtures carrying that user. It
installs the Wayland Emacs build from `extra`, clones Doom at a pinned commit,
seeds a Doom user config from the program's `home/`, and runs `doom sync` at
install time so first launch is ready. The config holds Emacs to the same
parity contract as VSCodium: same Registry languages, LSP via eglot on the
system servers, conform's formatters on save, dape on nvim-dap's adapters, and
the nvim `SPC` map winning wherever Doom's own map collides. Unlike VSCodium
it follows Noctalia live, like nvim, and closes gaps VSCodium had to list
(harpoon, undotree, which-key, org, inlay-hint toggle). A coverage map keeps
it in step with the Registry; a Feature Audit probe proves it on the target.

## User Stories

1. As the operator, I want Emacs installed on my desktop and laptop by the
   installer, so that I never hand-install it again.
2. As the operator, I want Emacs to be opt-in per user, so that nvim stays the
   one default editor and other users are unaffected.
3. As the operator, I want the Wayland (pgtk) Emacs build, so that it renders
   natively on niri, Hyprland, KDE and Umbriel.
4. As the operator, I want Doom Emacs rather than a hand-rolled config, so
   that I get a maintained distro with evil and a `SPC` leader out of the box.
5. As the operator, I want Doom pinned to a known commit, so that an upstream
   breakage on Doom master never breaks a fresh install.
6. As the operator, I want to move the pin with a one-line commit, so that
   upgrading Doom is deliberate and reviewable.
7. As the operator, I want `doom sync` run at install time, so that my first
   launch does not stall fetching ~200 packages.
8. As the operator, I want a failed `doom sync` to warn instead of failing the
   install, so that a network blip leaves a usable system and a clear message.
9. As the operator, I want my Doom user config seeded from the repo, so that
   every host gets the same Emacs.
10. As the operator, I want the Emacs config not stowed by default, so that an
    existing Emacs config on a host is never adopted or overwritten.
11. As the operator, I want to stow the Emacs config when I name it, so that I
    can opt a host into repo-managed Emacs on purpose.
12. As the operator, I want every [[Language Registry]] language covered in
    Emacs, so that switching editors never loses a language.
13. As a maintainer, I want a test that fails when the Registry and the Emacs
    coverage map disagree, so that a language added to nvim cannot silently
    go missing in Emacs.
14. As the operator, I want LSP through eglot using servers on PATH, so that
    Emacs uses the same system language servers as nvim.
15. As the operator, I want Emacs never to offer to download its own language
    servers, so that there is one toolchain, not two.
16. As the operator, I want format on save with the same formatter per
    language that nvim uses, so that files come out identical from either
    editor.
17. As the operator, I want no fix-all or organize-imports on save, so that
    saving behaves exactly like nvim; organize imports stays on `SPC c o`.
18. As the operator, I want linting via flymake fed by the same servers and
    linters, so that diagnostics match nvim's.
19. As the operator, I want `]d`/`[d` to jump diagnostics, so that navigation
    matches nvim.
20. As the operator, I want debugging through dape on the same adapters as
    nvim-dap (debugpy, codelldb, dlv, js-debug), so that debug sessions work
    the same in both editors.
21. As the operator, I want the `SPC d` debug map (breakpoint, conditional,
    continue, step into/over/out, REPL, run last, terminate, UI) to match
    nvim's, so that my debug muscle memory carries over.
22. As the operator, I want nvim's leader map to win wherever Doom binds the
    same key differently, so that one set of muscle memory drives both.
23. As the operator, I want Doom to keep every binding nvim does not use, so
    that I still get Doom's extras.
24. As the operator, I want `SPC g g` to open lazygit, so that it matches nvim.
25. As the operator, I want magit on `SPC g m`, so that Doom's best git tool
    is still one key away.
26. As the operator, I want the rest of nvim's `SPC g` map (hunks, blame,
    history, diff) mirrored where Emacs backs it, so that git work matches.
27. As the operator, I want `s` to jump like flash (avy), with evil-snipe off,
    so that motion matches nvim.
28. As the operator, I want `gs` surround (`gsa`/`gsd`/`gsr`), so that
    surround matches nvim's mini.surround.
29. As the operator, I want `-` to open the current file's directory in dired,
    editable like oil, so that the oil workflow carries over.
30. As the operator, I want `SPC e` to toggle a file tree on the right, so
    that it matches nvim's explorer key and VSCodium's sidebar side.
31. As the operator, I want the `SPC f` and `SPC s` pickers (files, grep,
    buffers, recent, help, symbols, commands, keymaps) to match nvim, so that
    finding things is identical.
32. As the operator, I want `SPC s r` project search and replace, so that it
    matches grug-far.
33. As the operator, I want harpoon on `SPC a`, `C-e` and `SPC 1..N`, so that
    file marks work like nvim's harpoon.
34. As the operator, I want an undo tree on `SPC U`, so that it matches
    undotree.
35. As the operator, I want a which-key popup on `SPC`, so that I can discover
    binds like in nvim.
36. As the operator, I want `SPC u h` to toggle inlay hints, so that it
    matches nvim.
37. As the operator, I want the `SPC x` diagnostics/todo/quickfix lists
    mirrored where Emacs backs them, so that Trouble's workflow carries over.
38. As the operator, I want the `SPC r` refactor binds where eglot offers the
    actions, so that refactoring matches nvim as far as is honest.
39. As the operator, I want a REST client on `SPC R s`/`SPC R c`, so that I
    can send requests and copy them as curl like in nvim.
40. As the operator, I want the REST client listed as a loose match, so that I
    know its file format is close to, not identical with, rest.nvim's.
41. As the operator, I want nvim's core binds (`SPC w`, `SPC q`, `Tab`/`S-Tab`,
    `C-h/j/k/l`, `SPC b d`, `SPC y p`, visual `J`/`K`, `SPC p`, `C-Space`/
    `BS` selection) mirrored, so that basic editing feels the same.
42. As the operator, I want a terminal toggle on `C-/`, so that it matches
    nvim.
43. As the operator, I want Emacs to follow the live Noctalia palette, so that
    it matches nvim and the rest of the desktop.
44. As the operator, I want Emacs to fall back to Catppuccin Mocha with the
    sapphire accent when Noctalia has not rendered a theme, so that KDE and
    first boot still look right.
45. As the operator, I want `SPC u C` to pick among nvim's five palettes and
    `SPC u N` to toggle Noctalia follow, so that theme control matches nvim.
46. As the operator, I want a palette change to reach an already-open Emacs,
    so that I do not restart Emacs to see the new theme.
47. As the operator, I want no Emacs daemon started at login, so that Emacs
    costs nothing until I open it.
48. As the operator, I want FiraCode Nerd Font 12 with ligatures and
    nerd-icons, so that Emacs matches kitty, nvim and VSCodium.
49. As the operator, I want Doom org to use the same org directory, agenda
    files and refile file as nvim's orgmode, so that both editors work on the
    same notes.
50. As the operator, I want a Feature Audit probe for Emacs, so that an Audit
    Run proves Emacs works on a real host.
51. As the operator, I want the audit to check `doom doctor`, the pinned
    commit and the seeded config, so that a broken sync or a drifted pin is
    caught.
52. As the operator, I want the audit to probe that the planned binds are
    live, so that a Doom upgrade that clobbers a bind is caught.
53. As a maintainer, I want parity gaps listed in the ADR rather than faked,
    so that nobody mistakes a missing feature for a bug.
54. As a later-created user, I want to know Doom's core is not pre-installed
    for me, so that I run `doom install` myself instead of hitting an error.
55. As a maintainer, I want the Noctalia-rendered theme file never tracked or
    stowed, so that a palette change never dirties the repo.
56. As a maintainer, I want every new package grounded on the Arch Wiki, so
    that package choices follow the repo's grounding rule.

## Implementation Decisions

- **New User Program `dev/emacs`**, `kind: user`, installed by the profile
  runner as the owning user, shaped like `dev/vscodium`: metadata, an
  `install.sh`, a `home/` tree applied by Config Apply (owning user +
  `/etc/skel`), a coverage map, a Doom pin data file, an audit probe with an
  audit-fixtures set and a binds file.
- **User Profile**: `emacs` appended to the operator's `programs` list after
  `vscodium`. Not in User Core; nothing in Host Core.
- **Packages**: `emacs-wayland` from `extra`. Doom's vterm module needs
  `cmake` and `libvterm`; add whatever the Arch Wiki grounds, via the program,
  not Host Core. Doom's own prerequisites (git, ripgrep, fd) are already in
  the fleet; verify.
- **install.sh**: installs the package; clones Doom into the owning user's
  Emacs config dir and checks out the commit from the pin file (re-run safe:
  an existing clone is fetched and re-pinned, never deleted); runs the Doom
  installer/sync non-interactively; warns on sync failure instead of failing;
  never writes `home/` (Config Apply owns that). Uses Installer Stdlib status
  helpers like the vscodium installer.
- **Pin data file**: one commit SHA, comments allowed, read by install.sh and
  the audit.
- **Doom user config** (`init.el`, `config.el`, `packages.el` in `home/`):
  - `init.el` modules: evil (everywhere), vertico, corfu, which-key, doom
    UI/modeline, treemacs, vterm, `lsp +eglot`, `format +onsave`,
    `checkers syntax +flymake`, `undo +tree`, magit, `lang` modules per
    Registry row with `+lsp`, `org`. No lsp-mode, no `:tools debugger`.
  - `packages.el`: dape, harpoon, avy, restclient, catppuccin-theme, plus any
    language package a Registry row needs that Doom lacks.
  - `config.el`: formatter map mirroring conform per language; eglot server
    commands pointing at the system binaries where Doom's defaults differ;
    dape configs on nvim-dap's adapters; the key map with nvim winning
    (lazygit on `SPC g g`, magit on `SPC g m`, avy on `s`, evil-snipe off,
    `gs` surround, `-` dired-jump, `SPC e` treemacs right, harpoon, `SPC U`,
    `SPC u h/C/N`, REST, debug, diagnostics); theme logic; `server-start`
    when no server runs; font; org paths.
- **Theme contract**: follow on → load Noctalia's rendered theme when its
  file exists, else Catppuccin Mocha + sapphire; follow off → the picked
  static palette. Palette set = nvim's five. Noctalia's built-in `emacs`
  template is already enabled fleet-wide and targets the Doom config dir
  first; its apply hook reaches the open Emacs through `emacsclient`.
- **Noctalia output hygiene**: the rendered theme file under the Doom config
  dir is git-ignored and excluded from stow (seed-only, ADR 0104).
- **Stow opt-in**: `stow-configs.sh` treats emacs like vscodium — skipped
  unless named.
- **Coverage map**: same row format as VSCodium's (Registry key → Doom
  module/package or `n/a <reason>`, a key may span rows).
- **Audit probe**: requires the package, runs as the user; checks emacs runs,
  the seeded config exists, the Doom clone is at the pinned commit, `doom
  doctor` reports no errors, and each planned bind in the binds file resolves
  to its command via `emacs --batch` with Doom loaded.
- **Docs**: ADR 0160 and the glossary are written; on completion, flip ADR
  0160's status to implemented and record any Behaviour differences / gaps
  found, as ADR 0148 did.

## Testing Decisions

- Good tests assert committed, externally visible artefacts and observable
  target behaviour — program files, parsed values, selection output, live
  binds — never how `install.sh` is written line by line.
- **Static program test** (new bats file; prior art: the vscodium and nvim
  program tests): program metadata and install.sh shape (no `home/` seeding,
  no AUR, reads the pin); the pin file holds exactly one 40-hex SHA;
  `init.el` enables `lsp +eglot`, `format +onsave`, flymake, `undo +tree`
  and omits lsp-mode/`:tools debugger`; `packages.el` declares dape,
  harpoon, avy, restclient, catppuccin-theme; `config.el` carries the
  nvim-wins binds, `server-start`, the five palettes, FiraCode Nerd Font and
  nvim's org paths. Text assertions with awk/grep — no Emacs runtime on the
  host or in CI.
- **Coverage map test** (same file): Registry keys, extracted from the nvim
  language registry with awk, equal the coverage map keys.
- **Selection goldens**: the existing desktop, laptop and VM fixture goldens
  gain the `emacs` user program.
- **Stow opt-in**: extend the existing config-apply test — emacs skipped with
  no args, honoured when named, unaffected by `--except`.
- **No-python / readability lints** already cover the new files.
- **Feature Audit probe** (prior art: nvim and vscodium `audit.sh` and nvim's
  binds file) runs in Audit Runs on the target.
- **VM acceptance** via vm-agent on `arch-combined`: Emacs launches themed
  from Noctalia; a palette change reaches the open Emacs; format on save in a
  TS and a Rust file uses the system formatters; eglot attaches the
  `/usr/bin` servers; a dape breakpoint hits in Python; `SPC g g`, `s`, `-`,
  `gsa` behave as specified; screenshot recorded in the ticket.

## Out of Scope

- Touching any existing Emacs config on an operator host.
- An `emacs.service` login daemon.
- Making Emacs a User Core default or a `host_programs` entry.
- Installing Doom's core for users created later from `/etc/skel`.
- Swift support (not a Registry row).
- Spacemacs, vanilla hand-rolled config, lsp-mode, dap-mode.
- Byte-identical `.http` compatibility with rest.nvim.
- Changing nvim or VSCodium behaviour.

## Further Notes

- Doom is not in the AUR; upstream installs by git clone only.
- Doom's sync needs network at install time; a failed sync leaves Emacs
  installed and Doom re-syncable by hand.
- Unverified until implementation: which Registry rows Doom's `lang` modules
  cover vs need extra packages; whether every formatter maps cleanly onto
  apheleia; exact vterm build deps (ground on the Arch Wiki).
- Fork this into tickets with `/to-issues`; prior art for the slicing is the
  vscodium-parity ticket set (stow opt-in, tracer program + look + VM smoke,
  languages + coverage map, keymaps + palettes, debuggers, close-out).

## Outcome (post-implementation)

- **Post-Config Hook** (new, amends ADR 0134): Doom bakes its config dir's
  path into its generated profile and the Runner places config after every
  install.sh, so `doom install` runs from `post-config.sh`, a generic hook
  the Runner runs as the user after Config Apply.
- Noctalia follow defaults **off**, matching nvim (`SPC u N` turns it on);
  four of nvim's five palettes (no maintained rose-pine Emacs theme).
- `.tsx`/`.jsx` get modes of their own (Doom maps them only with
  +tree-sitter; Arch packages no TypeScript grammar).
- The audit judges every bind (90+), not a representative set: emacs is a
  registered bind source; binds into packages that do not autoload their
  command are autoloaded (the probe's `commandp` check found 18).
- VM checks found and fixed: the evil cursor color, lazygit's vterm runner,
  missing autoloads, the snippets dir. Gaps, loose matches and displaced
  Doom keys are in ADR 0160.
- The fleet `desktop` Audit Run is blocked by AUR vetting of nixfmt (a
  maintainer change); verified on non-fleet arch-kde instead. Rerun after
  the 14-day window.
