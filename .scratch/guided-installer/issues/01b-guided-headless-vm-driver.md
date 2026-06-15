# Headless guided VM driver — automate the fzf-launch smoke

Status: ready-for-agent

## Parent

`.scratch/guided-installer/PRD.md`

## What to build

Upgrade issue 01's **manual** fzf-launch smoke into an automated,
deterministic VM run, using the selection seam 01 ships
(`guided_select` / `guided_prompt`, replayable via `--guided <answers>`).

A third VM flow, `vm/lib/flow-guided.sh`, mirrors `flow-test.sh`: its
cloud-init `runcmd` writes a **guided answers file** (the scripted menu
choices — `hostname`, the single-disk pick, the typed `INSTALL`) into the
guest, then runs `./install.sh --guided <answers>` instead of decoding a
positional `install.jsonc`. The shell replays the answers through the
seam — no fzf, no `/dev/tty`, no keystroke injection — assembles the same
Effective Config, and installs. The existing serial sentinel
(`===INSTALLER-EXIT-N===`) and `--verify-boot` power-cycle are reused
unchanged, so a scripted guided run proves **menu → artifact → boot**, the
one gap issue 01's positional VM suite leaves open.

Add the answers-file format (one `key=value` per line, consumed in menu
order) and a guided VM profile under `tests/vm/profiles/` that selects the
flow. `vm/vm.sh` gains a `--guided` flow alongside `--testing`.

## Acceptance criteria

- [ ] `vm/lib/flow-guided.sh` emits cloud-init that writes an answers file
      and invokes `./install.sh --guided <answers>`; `vm/vm.sh` dispatches
      to it.
- [ ] The answers file drives the full single-disk path — hostname, disk
      pick, typed `INSTALL` — through `guided_select` / `guided_prompt`
      only (no fzf, no tty).
- [ ] A scripted guided run installs and **boots** (serial sentinel +
      `--verify-boot`), exercising menu → Effective Config → install.
- [ ] The Effective Config the replay produces matches the one issue 01's
      positional seed would (same single-disk ZFS artifact).
- [ ] bats: `seed-generator` / flow assertions cover the new flow's
      runcmd shape.

## Blocked by

- `01-guided-install-tracer-bullet` (ships the `guided_select` /
  `guided_prompt` replay seam this driver consumes)
