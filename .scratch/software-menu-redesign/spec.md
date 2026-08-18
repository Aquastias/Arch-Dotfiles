# Software-options redesign: Menu-Owned Programs + Software area

Status: ready-for-agent

Reference: ADR 0086 (Menu-Owned Programs and the Software area redesign).
Glossary: [[Menu-Owned Program]], [[Host Program]], [[User Program]],
[[User Editor]], [[Program Registry]], [[Package Resolver]]. Menu-only change —
the stored slots (`host_programs`, `packages.repo`, `packages.aur`, user
`programs`) are unchanged.

## Problem Statement

In the Guided Installer the **Packages** category piles five unlike surfaces on
one screen — `repo`, `aur`, `derived`, a `host_programs` picker, and a free-text
`＋Add` that silently reclassifies a typed name by kind. Two things read as
inconsistent to the operator:

1. A registry Program already governed by a dedicated control still appears
   *again* as a pickable Program — `grub` shows next to the Bootloader that owns
   it, `clamav` shows as a program though Security→antivirus already installs
   it. The operator cannot tell the duplicate from the real control.
2. `＋Add` reclassifies invisibly: typing `docker` silently creates a user
   program on the Primary User, typing `grub` silently becomes a host program.
   The operator never sees where their name went.

## Solution

Reframe the whole software surface around one honest rule and one clear home per
concept, without touching the stored schema.

- Introduce the **[[Menu-Owned Program]]**: a registry Program whose install is
  governed by a dedicated menu control (Bootloader enum, Security/Backup/Services
  toggles, or secrets activation). Its control is its **sole home** — never
  default-listed as a program, never shown in a Programs picker. `grub` is chosen
  under Bootloader, `clamav` under Security, and nowhere else.
- Because **every `kind: host` program is Menu-Owned**, no free-standing Host
  Program remains: rename the **Packages** category to **Software**, which drills
  only `repo` / `aur` / `derived` — no Programs row. The five free-standing
  [[User Program]]s (`docker`, `podman`, `virt-manager`, `searxng`, `teamspeak3`)
  keep their one home, the [[User Editor]] under **Users**.
- Replace the `＋Add` magic with an explicit, visible guard. On `repo`, `＋Add`
  opens an archinstall-style package browser built from the installer's own fzf
  surface (`pacman -Slq | fzf --multi --preview 'pacman -Si {}'`): filter,
  info-preview, multi-select. Every picked name is routed *visibly* — a
  Menu-Owned name informs ("managed by \<Control\>", not added), a free-standing
  user program offers to add under Users, anything else lands in
  `packages.<slot>.extra`. The `aur` slot stays free-text.
- Control defaults are untouched: delisting a program never changes whether it
  installs.

## User Stories

1. As an operator, I want `grub` to not appear as a selectable Program, so that
   the Bootloader choice is its single, unambiguous home.
2. As an operator, I want `clamav`, `rkhunter`, `firewalld`, `ufw`, `apparmor`,
   `borg`, and `zfs-auto-snapshot` absent from every Programs picker, so that a
   Security/Backup toggle is the only place they are chosen.
3. As an operator, I want `cups`, `bluetooth`, `power-profiles-daemon`, and
   `tuned` to stay filtered (as today), so that the generalized rule is
   consistent with the existing Services behaviour.
4. As an operator, I want `sops` never listed as a pickable program, so that its
   secrets-activation remains its sole trigger.
5. As an operator, I want the software category named **Software**, not
   Packages, so that its name matches what it now contains.
6. As an operator, I want the Software category to drill into exactly `repo`,
   `aur`, and `derived`, so that there is no empty or misleading Programs row.
7. As an operator, I want the Software category summary to read
   `repo, aur, derived`, so that the top-screen label reflects the new contents.
8. As an operator, I want free-standing user programs (`docker`, `podman`,
   `virt-manager`, `searxng`, `teamspeak3`) to be pickable only under
   Users → \<user\> → programs, so that a program has exactly one home.
9. As an operator, I want the User Editor's programs picker to also exclude
   Menu-Owned programs, so that I cannot double-add `clamav` there either.
10. As an operator, I want `repo → ＋Add` to open a filterable list of all repo
    packages with an info preview, so that I can discover and add packages the
    way archinstall lets me.
11. As an operator, I want to multi-select packages in that browser with a
    per-item preview (description, deps, size), so that I can add several at once
    with context.
12. As an operator, I want to type to filter the package browser, so that I can
    find a package among thousands quickly.
13. As an operator, when I pick a Menu-Owned name in the browser, I want to be
    told it is managed by its control and not have it added as a package, so that
    I am never silently redirected and never build an invalid config.
14. As an operator, when I pick a free-standing user program in the browser, I
    want it routed to Users → \<user\> with a visible message, so that I know
    where it went.
15. As an operator, when I pick an ordinary package, I want it added to
    `packages.<slot>.extra`, so that plain packages behave predictably.
16. As an operator, I want the `aur` `＋Add` to remain a free-text entry, so that
    I can still add AUR names even though they are not in the sync DB.
17. As an operator, I want the `derived` section to stay read-only and fenced,
    so that I can see why a package installs without mistaking it for something I
    edit.
18. As an operator, I want the `derived` section to name the control behind each
    package, so that "why is this installing?" is answered in place.
19. As an operator, I want my Security/Backup/Services defaults unchanged by this
    work, so that removing the duplicate listing does not silently alter what
    installs.
20. As an operator, I want a typed name that resolves to a Program to never end
    up in `packages.*`, so that config-load never aborts on an exclusivity
    violation.
21. As a maintainer, I want the owned sets unified into one `menu_owned_programs`
    function, so that adding a future control-owned program updates one place.
22. As a maintainer, I want a future free-standing `kind: host` program to
    reintroduce the Host Programs section automatically, so that the empty state
    is a consequence of the filter, not a special case.
23. As an operator installing off-target with `--debug`, I want the Software menu
    and previews to render without a live install, so that I can inspect the new
    layout on a daily driver.
24. As an operator, I want the package browser to require a synced pacman DB, and
    to behave sanely when the DB is empty, so that a missing `pacman -Sy` fails
    understandably rather than silently.

## Implementation Decisions

- **New pure aggregator `menu_owned_programs`** unions every control-owned set:
  the existing `printing_owned_programs` / `bluetooth_owned_programs` /
  `power_owned_programs`, plus new owned-sets for the Bootloader-owned program
  (`grub`), the Security-owned programs (`firewalld`, `ufw`, `clamav`,
  `rkhunter`, `apparmor`), the Backup-owned programs (`borg`,
  `zfs-auto-snapshot`), and the secrets-activated `sops`. Lives beside the
  existing owned-set helpers in the config modules.
- **Both program pickers subtract the union.** `_ctl_host_program_names` and
  `_ctl_user_program_names` filter out `menu_owned_programs`. Since all six
  `kind: host` programs are owned, the host picker resolves empty.
- **Menu model (`menu.sh`).** The `Packages` [[Configuration Category]] is
  renamed **Software**; its summary becomes `repo, aur, derived`; the
  `host programs` field row is removed. The `repo` / `aur` / `derived` drill and
  the three-state provenance dots are unchanged.
- **`＋Add` split by slot.** `repo → ＋Add` invokes the fzf package browser fed by
  `pacman -Slq`, previewing `pacman -Si {}`, multi-select. `aur → ＋Add` stays the
  current free-text prompt.
- **The guard is a pure routing over picked names**, applied on confirm. Encoded
  by the validated prototype (trimmed to the decision):

  ```
  route(name, slot):
    if name is Menu-Owned      -> inform "managed by <Control>"; no state change
    else if kind(name)==user   -> add to users[0].programs; inform "→ Users"
    else                       -> append to packages.<slot>.extra
  ```

  This preserves the config-load exclusivity safety the old silent routing gave,
  while making every reclassification explicit. The old emit-path/entry-path
  promotion rule is removed.
- **No schema change.** Stored slots, the [[Layer Resolver]] classification, and
  the [[Package Resolver]]'s derived sources are untouched; `derived` continues
  to read from the resolver.
- **Defaults unchanged.** Security/Backup/Services toggle defaults are not
  touched by this work.

## Testing Decisions

Good tests here assert *external behaviour* of the pure modules — given a Config
State / name in, the rendered rows, the filtered picker set, or the resulting
state out — never internal call shapes. All three seams are existing pure bats
homes; the interactive fzf browser is not unit-tested (it needs a live pacman DB
and a tty), matching how other interactive fzf entry surfaces are treated.

- **`guided-controller.bats` — Menu-Owned union + picker filters.** Assert
  `menu_owned_programs` lists the full set; assert `_ctl_host_program_names`
  resolves empty (all host programs owned) and excludes `grub`; assert
  `_ctl_user_program_names` excludes the Security/Backup-owned user programs and
  keeps the five free-standing ones. Prior art: the existing "picker omits the
  toggle-owned cups, keeps the rest" test and `bluetooth.bats`'
  `*_owned_programs` tests.
- **`guided-menu.bats` — menu model.** Assert `menu_categories` carries a
  **Software** category with summary `repo, aur, derived`; assert `menu_rows` no
  longer emits a `host programs` field row. Prior art: the category/row tests
  already in this file.
- **`guided-packages.bats` — `＋Add` guard routing.** Assert routing a Menu-Owned
  name leaves Config State unchanged (and reports the owning control); assert a
  free-standing user program name lands in `users[0].programs`; assert an
  ordinary name lands in `packages.<slot>.extra`. Prior art: the existing
  free-text add and exclude/provenance tests, and the `derived`-section tests.
- **`post-install.bats`** already covers `post_install_programs` deriving the
  Security/Backup programs; it is the reference for which names the new
  Security/Backup owned-sets must enumerate (they must match the derivation).

## Out of Scope

- Any change to the stored schema or install mechanisms (host vs user, pacstrap
  vs paru, chroot phase).
- Revisiting Security/Backup/Services default values (deferred deliberately at
  the design stage; a separate concern).
- Browsing or searching **AUR** packages in the `＋Add` flow — AUR is not in the
  sync DB and paru is not bootstrapped at menu time; `aur` stays free-text.
- Unit-testing the interactive fzf browser itself (tty + live pacman DB).
- Reintroducing a Host Programs section — it is a natural consequence of the
  filter if a future free-standing `kind: host` program is added.

## Further Notes

- Extends, does not supersede, ADR 0079/0080 — those delisted three service
  programs; this folds them and ten more into one `menu_owned_programs` set.
- The `repo` browser needs a synced pacman DB (`pacman -Sy`) or the list is
  empty — the same operational gotcha archinstall hit (upstream issue #3307).
- Design validated against a throwaway TUI prototype at
  `.scratch/software-menu-redesign/prototype-tui.html` (kept as a primary
  source); the guard snippet above is trimmed from it.
