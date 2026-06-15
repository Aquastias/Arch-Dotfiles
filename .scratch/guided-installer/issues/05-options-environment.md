# Host breadth I — Options + Environment

Status: ready-for-agent

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

- [ ] Kernel multi-select stored as tokens, primary first; non-lts
      tokens offered; emitted config valid.
- [ ] Bootloader, swap + `swap_size`, `esp_size`, SSH, `age_key_url` are
      editable and correctly emitted.
- [ ] Desktop multi (kde / hyprland / both); gpu `auto` or any of
      amd/nvidia/intel, with auto mutually exclusive with vendors.
- [ ] bats: menu-model rows + emit for these fields.

## Blocked by

- `01-guided-install-tracer-bullet`
