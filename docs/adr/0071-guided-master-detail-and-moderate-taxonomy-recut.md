# Guided Installer master-detail layout and moderate taxonomy re-cut

---
Status: accepted (amends ADR 0039's two-level category menu; scopes ADR
0042's persistent-fzf controller)
---

The Guided Installer adopts an archinstall-style **master-detail** presentation
and re-cuts its Configuration Categories from eight to twelve. Two changes, one
design pass, **zero back-end change** — the menu model (`section` labels + the
preview pane) is the only surface touched.

## Master-detail detail pane

The right-hand fzf **preview pane becomes an always-on detail column** that
renders the highlighted item's current state at **every** level (ADR 0042's
persistent-fzf controller already owns the pane):

- a **category** row previews a `key: value` summary of its fields, `●`
  override dots preserved;
- a **sub-group** row (a data pool, a user) previews its own sub-values;
- a **leaf** field previews its current value plus the allowed option set /
  short help.

Disks (pool/topology tree) and Users (account table) **reuse their existing
preview builders** rather than inventing new renders. Navigation stays
**drill-down** (Enter deeper, Esc up), matching archinstall's own behaviour
(entering *Locales* swaps its left column to `Keyboard layout / Locale language
/ …`, not a frozen list). fzf cannot freeze a parent column while drilling, so
the **preview pane renders that parent column itself** — greyed, with the
current item marked — **above** the live detail. The operator therefore always
sees `<parent> ▸ [you are here]` as a real column plus the highlighted item's
detail; the persistent parent is *visible*, not a second live cursor.

### Prototype verdict

A 3-variant HTML mock (`.scratch/guided-master-detail-redesign/prototype.html`)
answered "what should it look like": **A — classic archinstall 2-pane** (clean
chrome, drill-down) fused with **C's persistent parent column**, realised via
the preview-pane-renders-the-parent trick above. Rejected: **B** (heavy
card/footer chrome — busier than archinstall), and **C as a true two-live-column
Miller** — a second simultaneous cursor is not expressible in one fzf and would
have discarded the headless `--guided` replay and the guided bats suite, so its
only gain (dual-cursor nav) did not justify a bespoke-TUI rewrite. Staying on
single-fzf keeps ADR 0039/0042's controller and every test intact.

## Moderate taxonomy re-cut (8 → 12)

The two grab-bags are dismantled and names align with archinstall where it
helps. Every current field keeps a home; nothing is dropped or invented.

| # | Category | Fields | Moved from |
|---|----------|--------|------------|
| 1 | Locales | locale, keymap | Host |
| 2 | Mirrors & Repositories | mirror countries, multilib | Options |
| 3 | Disks | filesystem, encryption, impermanence, esp size, swap, pools | — |
| 4 | Bootloader | bootloader | Options |
| 5 | Kernels | kernel | Options |
| 6 | System | hostname, timezone | Host |
| 7 | Users | primary user, extra accounts | — |
| 8 | Environment | desktop, display manager, gpu | — |
| 9 | Packages | repo, aur, derived, system programs, extra | — |
| 10 | Security | firewall, antivirus, rootkit, apparmor, **sysctl** | Options (sysctl) |
| 11 | Backup | snapshots, borg | — |
| 12 | Advanced | ssh, age key url | Options |

Order follows archinstall's reading order (Locales, Mirrors, Disks, Bootloader,
Kernels, System, Users, …) — free familiarity, no back-end coupling to menu
order. `sysctl` moves to **Security** (it is kernel hardening); the *Options*
junk drawer becomes **Advanced**, holding only the two remote-access/secrets
knobs.

Reflector is **unchanged**: `options.mirror_countries` keeps its path and its
`reflector --country <list> --latest 10 --sort rate` consumer
(`lib/packages/list.sh`); only its menu `section` label moves to *Mirrors &
Repositories*, and the detail pane states that the countries drive reflector's
ranking.

## Considered options

- **Minimal re-skin (keep the 8, add the detail pane only)** — rejected: leaves
  *Options* a junk drawer of kernel + bootloader + mirrors + ssh + sysctl and
  wastes the mandate to rethink categories.
- **Full flat archinstall taxonomy (~15 categories)** — rejected: flattens away
  the grouping that keeps our richer Disks/Users tractable and manufactures
  empty categories for parity features that are still backlog.
- **Bespoke TUI (archinstall is a custom curses app)** — rejected: throws away
  the headless `--guided` replay and the whole bats suite for cosmetics the fzf
  preview pane already affords.
- **Literally-frozen left column** — rejected: not expressible in fzf without
  abandoning the two-level structure; the always-on detail column achieves the
  look without it.

## Consequences

- **Out of scope, tracked as backlog** (parity gaps, each its own feature with
  back-end work): network configuration, bluetooth/audio-choice/power/fonts
  rows, plymouth + unified-kernel-images, extra bootloaders (efistub/limine/
  refind), NTP, pacman color, locale encoding + console font, mirror custom
  servers + testing repos, reflector knobs (`--latest`/`--sort`/protocol), and a
  live package-search UI.
- The category count (`_MENU_CATEGORIES`) and per-field `section` labels
  (`_MENU_FIELDS`) in `lib/config/menu.sh` are the only model edits; the
  `menu_categories`/`menu_rows` contract and every field path are preserved, so
  the emit path, Layer Resolver, and Package Resolver are untouched.
- **CONTEXT.md's Guided Installer entry** (which names "eight top-level
  Configuration Categories") is updated to the twelve when the code lands, not
  before — the glossary tracks the built model.
- archinstall's **"Profile"** (desktop/minimal/server/xorg archetype) is
  deliberately **not** adopted; it collides with our **Host Profile** (a whole
  machine) and its archetypes are backlog. Environment stays desktop-only.
