# Host breadth I — Options + Environment

Status: done

## Parent

`.scratch/guided-installer/PRD.md`

## What to build

Add the FS-agnostic **Options** section and the **Environment** section
to the menu model + fzf shell + emitter.

Options: kernel (fzf-multi over `lts` / `default` / `hardened` / `zen`
tokens, first = Primary Kernel; all offered even on ZFS, with the ZFS
Module Guard as the install-time backstop), bootloader (`grub` |
`systemd-boot`), swap toggle + typed `swap_size`, `esp_size`, SSH toggle,
`age_key_url`. Environment: desktop (fzf-multi `kde` / `hyprland` → one
or both) and gpu (`auto`, or fzf-multi `amd` / `nvidia` / `intel`;
choosing auto clears explicit vendors).

## Acceptance criteria

- [x] Kernel multi-select stored as tokens, primary first; non-lts
      tokens offered; emitted config valid.
- [x] Bootloader, swap + `swap_size`, `esp_size`, SSH, `age_key_url` are
      editable and correctly emitted.
- [x] Desktop multi (kde / hyprland / both); gpu `auto` or any of
      amd/nvidia/intel, with auto mutually exclusive with vendors.
- [x] bats: menu-model rows + emit for these fields.

## Blocked by

- `01-guided-install-tracer-bullet`

## Comments

**DONE via /tdd (2026-06-20).** Options + Environment sections wired through
the three pure cores + the fzf shell.

menu.sh: nine new `_MENU_FIELDS` rows — `Options` (kernel/bootloader/swap/
swap_size/esp_size/ssh.enabled/age_key_url) and `Environment` (desktop/gpu).
menu_rows now renders an array-valued field comma-joined (primary/first token
first) so kernel/desktop/gpu stay one scalar line. `swap_size` has no static
default (the back-end derives it RAM×2, disk-capped, treating empty ≡ "auto"),
so its row shows `auto` for legibility — display only, never written to state,
so an untouched swap_size still emits no key.

guided.sh: new `guided_multi` seam (fzf --multi interactive / whitespace-list
replay, mirrors `guided_pick_disks`); `_guided_collect_multi` +
`_guided_multi_array` (empty-dropping list→JSON-array); `_guided_edit_scalar`
free-text helper. Edits: kernel (token array, all flavours offered even on ZFS
— ZFS Module Guard is the backstop), bootloader, swap/ssh (bool), swap_size/
esp_size/age_key_url (scalar), desktop (array), gpu (auto→scalar clears
vendors, else vendor array). Loop label-dispatch routes each row ("swap size:"
before "swap:"); `guided_build`'s replay branch drives them all.

emit.sh unchanged — the override map already merges over Host Core and every
path is in the closed schema, so the Effective Config stays schema-clean.

Tests: guided-menu (+6), guided-shell (+13), guided-emit (+1) = +20. Full
suite **1178 bats**, shellcheck clean. fzf rendering stays smoke-only per the
PRD; the replay path exercises the assembly deterministically. No VM-smoke
line in this issue's acceptance.
