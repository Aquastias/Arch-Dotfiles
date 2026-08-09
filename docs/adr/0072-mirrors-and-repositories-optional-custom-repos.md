# Mirrors & Repositories: optional repos, custom servers, custom repositories

---
Status: accepted (extends ADR 0071's Mirrors & Repositories category; pulls
the "custom servers + testing repos" item forward from ADR 0071's backlog)
---

The Guided Installer's **Mirrors & Repositories** category gains three operator
affordances, each authored declaratively and consumed by the install back-end:

1. **Optional Repositories** — a multi-select over `multilib`,
   `multilib-testing`, `core-testing`, `extra-testing`, stored as
   `options.optional_repos[]`. **Replaces** the old `options.multilib` bool: the
   bool was a single repo expressed as a flag; the set expresses the same choice
   plus the testing repos as one field. Default is `["multilib"]`, preserving the
   historical `multilib=true` default; an explicit `[]` means "no optional repos"
   (multilib off). `install_config_multilib` survives as a back-compat shim
   ("true" iff `multilib` ∈ the set) so no read-site had to change at once.

2. **Custom mirror servers** — `options.mirror_servers[]`, a list of `Server =`
   URLs the operator adds. Written **above** the reflector-ranked mirrorlist
   (after `reflector --save`, so they are not clobbered) and therefore tried
   first.

3. **Custom repositories** — `options.custom_repositories[]`, archinstall-style:
   each entry carries `name`, `url`, `sign_check` (`Never` | `Optional` |
   `Required`) and `sign_option` (`TrustAll` | `TrustedOnly`), which combine into
   the pacman `SigLevel` (`Never`, or `<check> <option>`). Appended as `[name] /
   SigLevel / Server` blocks to `/etc/pacman.conf`.

## Application (install back-end)

All three are applied in `install_base` (`lib/packages/list.sh`) **before**
pacstrap, on the host `/etc/pacman.conf` / `mirrorlist`, so their targets resolve
during pacstrap; `chroot.sh` then copies that `pacman.conf` into the target, so
the installed system inherits the same repos and mirrors. `enable_optional_repos`
uncomments the shipped `#[repo]` + `#Include` **in place** (preserving Arch's
testing-above-stable section ordering), appending a standard section only if the
ISO's `pacman.conf` lacks it.

## Schema + menu

`options.optional_repos[]`, `options.mirror_servers[]`, and
`options.custom_repositories[].{name,url,sign_check,sign_option}` join the closed
host schema (`profile.sh`); `options.multilib` is removed and now aborts as an
unknown key. In the menu, `optional_repos` is a toggle multi-select;
`mirror_servers` and `custom_repositories` are **list screens** (a listing plus a
`＋ Add …` action that opens a text prompt), modelled on the existing sysctl list.
`custom_repositories` holds objects, so the menu value renderer now maps a
non-string array element to its `.name` instead of `join`-ing (which errored).

## Considered options

- **Keep `options.multilib` bool + a separate testing set** — rejected: two rows
  for one operator concept ("which optional repos"); the operator's mental model
  is a single multi-select, so one `optional_repos` field is the honest shape.
- **A field-by-field custom-repo sub-form (archinstall's multi-screen prompt)** —
  deferred: the fields are captured via a single `name url [check] [option]`
  prompt (defaults `Required`/`TrustedOnly`), which records exactly the same data
  with far less controller surface. Upgrading to a per-field form is additive.

## Consequences

- Enabling `core-testing`/`extra-testing` uncomments the shipped sections in
  place, so ordering is correct on the stock ISO; the append fallback (used only
  if a section is absent) lands below stable, which is imperfect for a testing
  repo but never happens on a standard `pacman.conf`.
- The pacman.conf / mirrorlist edits are **VM-verifiable only** (they touch the
  live `/etc/pacman.conf`); the pure seams — schema, accessors
  (`install_config_optional_repos` / `_mirror_servers` /
  `_custom_repositories`), the SigLevel builder, the menu model, and the
  controller add-flows — are covered headless in bats.
- The Combination Matrix registry axis `options.multilib` becomes
  `options.optional_repos`.
