# Menu-Owned Programs and the Software area redesign

The Guided Installer's **Packages** category conflated five surfaces on one
screen — `repo`, `aur`, `derived`, a `host_programs` picker, and a free-text
`＋Add` that silently reclassified typed names by kind. Two symptoms drove this
ADR: a registry Program whose install is already governed by a dedicated control
(e.g. `grub` by the Bootloader enum, `clamav` by Security→antivirus) still
appeared *again* in a Programs picker, and the `＋Add` route reclassified names
invisibly. The fix is **menu-only** (the stored slots `host_programs` /
`packages.repo` / `packages.aur` / user `programs` are unchanged — they map to
real install mechanisms): make the menu express them consistently.

We introduce the **[[Menu-Owned Program]]**: a registry Program whose install is
governed by a dedicated menu control (Bootloader enum, Security/Backup/Services
toggles, or secrets activation). Its control is its **sole home** — never
default-installed as a program, never listed in either Programs picker. This
**generalizes** the `*_owned_programs` filter ADR 0079/0080 already applied to
`cups` / `bluetooth` / `power-profiles-daemon` / `tuned` into one
`menu_owned_programs` union, adding `grub`, the Security set (`firewalld`,
`ufw`, `clamav`, `rkhunter`, `apparmor`), the Backup set (`borg`,
`zfs-auto-snapshot`),
and `sops`. Because **every `kind: host` program is Menu-Owned**, no
free-standing Host Program remains, so the **Packages** category lists **no
Programs at all**: its `host programs` row is dropped and it drills only
`repo` / `aur` / `derived`. The category **keeps the name `Packages`** — once
the Programs row is gone it is no longer a misnomer (it holds only packages), a
`Software` name would merely echo the `SOFTWARE` bucket header it already sits
under. The five free-standing User Programs (`docker`, `podman`, `virt-manager`,
`searxng`, `teamspeak3`) stay in their one home, the [[User Editor]] under
**Users**.

The `＋Add` magic is replaced by an explicit **guard**. On `repo`, `＋Add` opens
a package browser — `pacman -Slq | fzf --multi --preview 'pacman -Si {}'`, the
installer's own fzf surface reproducing archinstall's browser UX (filter +
info-preview + multi-select). Each picked name is routed visibly: a Menu-Owned
name **informs** ("managed by \<Control\>", not added), a free-standing user
program **offers** to add under Users, anything else lands in
`packages.<slot>.extra`. Control defaults are untouched — delisting a program
never changes whether it installs.

## Considered options

- **Delist Menu-Owned programs** (chosen) over **keep listing them** — a program
  that a control already owns has exactly one correct home; listing it twice is
  the duplication that reads as inconsistent, and produces an invalid config if
  added to the wrong slot.
- **Packages = host-declared only, user programs in Users** (chosen) over a
  **symmetric Host/User Programs split in Packages** — the guided menu's spine
  is already "Users category = per-user, everything else = host-declared"; a
  second User-Programs editor in Packages would recreate the two-homes drift
  this ADR removes. It also makes the empty Host side honest: nothing to show.
- **`＋Add` browser via fzf + pacman** (chosen) over **reusing archinstall's own
  selector** or **free-text only**. archinstall 3.0 (PR #3196) loads the full
  sync DB into its bespoke Python `archinstall.tui.curses_menu`; shelling into
  Python internals is not viable for a bash installer and a heavy dep for one
  screen, whereas `pacman -Slq | fzf --preview 'pacman -Si {}'` gives the same
  UX on the surface the installer already standardises on. AUR is not in the
  sync DB (and paru is not yet bootstrapped at menu time), so the `aur` slot
  stays free-text — repo-only, matching archinstall's own scope.
- **Menu-only, keep the schema** (chosen) over **collapsing the slots** — the
  slots encode genuinely different install mechanisms (root/pacstrap vs per-user
  paru vs chroot Host Program); collapsing them is a large, riskier back-end
  change and the confusion lives in presentation, not storage.

## Consequences

- The `host_programs` picker is now always empty and the **Packages** category
  has no Programs child. A future free-standing `kind: host` program (not owned
  by any control) reintroduces the section — the filter, not a special case,
  decides.
- The guard preserves the config-load exclusivity invariant (a Program name may
  never sit in `packages.*`, which aborts at load) while making every
  reclassification explicit and consented — the old emit-path/entry-path magic
  is gone.
- The `repo` `＋Add` browser needs a synced pacman DB (`pacman -Sy`) or the list
  is empty, the same operational gotcha archinstall hit (issue #3307).
- Extends, does not supersede, ADR 0079/0080: those delisted three service
  programs; this folds them and ten more into one `menu_owned_programs` set.
- The redundant top-level **extra packages** row was removed: `repo` `＋Add`
  browses and `aur` `＋Add` types, both writing `packages.<slot>.extra`, so a
  third free-text path made no sense. The Packages category is now a pure
  repo/aur/derived drill with no field rows; its ● folds from the package
  override map instead of that row.
- **Category renames to stop bucket-header echoes:** any category whose name
  repeated its bucket was renamed — **Services → Daemons**, **Advanced →
  Expert** — and the `SYSTEM` bucket → **`GENERAL`** (keeping the `System`
  category, so ADR 0081's identity-anchor rename stands). `SECURITY & DATA` /
  `Security` is left as a partial, non-exact overlap.
- Design validated against a throwaway TUI prototype at
  `.scratch/software-menu-redesign/prototype-tui.html`.
