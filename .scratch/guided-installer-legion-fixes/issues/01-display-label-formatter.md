# 01 — Display Label formatter across all menu surfaces

Status: done
Type: AFK

## Parent

`.scratch/guided-installer-legion-fixes/PRD.md`

## What to build

A single display-only formatter that turns a raw menu token into its
**Display Label**, and wire it into every user-facing surface of the Guided
Installer so casing is consistent everywhere. Display only — stored Config
State values are never mutated.

The formatter:
- Looks the token up in a curated table for acronyms / proper names.
- Otherwise sentence-cases the string (first letter upper) and upper-cases any
  word that is a known acronym — e.g. `esp size` → `ESP size`, `age key url`
  → `Age key URL`.
- Falls back to plain first-letter-uppercase for unknown tokens, so the table
  never has to be exhaustive (new options degrade gracefully).
- Passes technical / free-text tokens through unchanged: anything containing
  `/`, `=`, `:`, `.`, embedded whitespace-path, a leading non-alpha, or a
  device / by-id path (e.g. `/dev/sda`, `en_US.UTF-8`, `key=value`, a typed
  hostname).

Curated set: `KDE GPU SSH ZFS UFW LTS URL ESP AMD NVIDIA` plus literal
`systemd-boot`; `Intel` / `Auto` / `Hyprland` / `Zen` take normal case.

Apply it at the render boundary to: category/field row labels, pick-screen
option values, inline current-values on category rows, and the pre-install
review summary. Because selecting a row reverse-maps the visible label back to
a dotted config path for dispatch, make that reverse lookup format-aware
(format each candidate label and compare) so Enter still resolves the correct
field after re-casing.

## Acceptance criteria

- [x] A pure formatter maps tokens to Display Labels: curated hits
      (`kde`→`KDE`, `nvidia`→`NVIDIA`, `esp size`→`ESP size`, `ssh`→`SSH`),
      first-letter fallback for unknown tokens, and passthrough for
      `/dev/sda`, `en_US.UTF-8`, `key=value`, and typed hostnames.
- [x] Row labels, pick-screen values, inline values, and the pre-install
      review summary all render through the formatter.
- [x] Selecting a re-cased row still dispatches to the correct field (reverse
      lookup is format-aware).
- [x] Stored Config State / emitted config values are unchanged (formatting is
      display-only).
- [x] bats covers curated hits, fallback, technical passthrough, and reverse
      lookup (e.g. `GPU` → `environment.gpu`).

## Blocked by

None - can start immediately.

## Notes

Value-formatting is gated to human-word fields (`_ctl_display_values`):
desktop, gpu, kernel, filesystem, bootloader, firewall. Labels are always
formatted. Left raw (technical / free-text / boolean / structural): keymap
codes, locale, timezone, mirror countries, program & package names, hostnames,
sysctl pairs, usernames, booleans, layout preset keys, action rows, and the
sub-editor structural rows (swap/datapools/pooledit/rootdisk internals). The
review-summary scope is `print_environment_summary` (Desktop + GPU); backend
install-plan details (pools, disks, sizes) stay raw. Reverse lookup is
format-aware in three seams: `_ctl_field_for_label`, the Disks special-row
prefixes, and `_ctl_enter_values`. Fixed an empty-value column-shift bug
(whitespace-IFS collapse) by switching the row encoding to a unit-separator.
