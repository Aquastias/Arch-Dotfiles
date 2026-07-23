# 02 — Hybrid GPU multi-select in the menu

Status: done
Type: AFK

## Parent

`.scratch/guided-installer-legion-fixes/PRD.md`

## What to build

Let the operator pick more than one GPU vendor from the menu (e.g. AMD +
NVIDIA on a hybrid laptop). The back-end already consumes a vendor list and
handles the hybrid case (driver packages per vendor, envycontrol for
amd+nvidia, the AQ_DRM_DEVICES PRIME session env) — this slice only unlocks
the selection in the Guided Installer front-end.

Change the gpu field from a single-select enum to a multi-select toggle over
`amd nvidia intel auto`, default `auto`. A pure normalizer enforces
exclusivity: toggling a vendor on clears `auto`; toggling `auto` on clears all
vendors. The stored value is a lower-case array (e.g. `["amd","nvidia"]`) —
the exact shape the back-end already resolves. Both guided front-ends (the
persistent-fzf controller and the replay editor) use the same normalizer so
they can never drift.

## Acceptance criteria

- [x] The gpu screen is a multi-select toggle showing amd / nvidia / intel /
      auto, with `auto` selected by default.
- [x] Selecting `amd`+`nvidia` stores `["amd","nvidia"]`; the back-end
      installs both driver sets, adds envycontrol, and writes the
      AQ_DRM_DEVICES PRIME env (verified via the existing resolution path).
- [x] `auto` is mutually exclusive: picking a vendor clears `auto`, and
      picking `auto` clears vendors.
- [x] The replay editor produces the same normalized selections as the
      interactive controller.
- [x] bats covers the normalizer: `auto`+vendor → `[vendor]`, toggle `auto` →
      `[auto]`, `amd`+`nvidia` → `[amd,nvidia]`.

## Blocked by

None - can start immediately.

## Notes

Already implemented by prior guided work — verified, not rebuilt. The gpu
field is already a multi-select toggle; `_ctl_toggle_multi` carries full
`auto` exclusivity (toggle vendor clears auto; toggle auto clears vendors,
normalising to scalar `"auto"` / unset / array); `edit_set_gpu` + the replay
`_guided_edit_gpu` mirror it; `cfgstate_seed_defaults` seeds `gpu:"auto"` so
the menu shows `[x] Auto` by default; and the back-end
(`_resolve_env_gpu` / `gpu_is_nvidia_hybrid`) installs both driver sets, adds
`envycontrol`, and writes the AQ_DRM_DEVICES PRIME env for amd+nvidia. Existing
coverage: `gpu-resolution.bats` (amd+nvidia+envycontrol, auto→hybrid lspci),
`guided-controller.bats` (auto exclusivity), `guided-shell.bats`/
`guided-edits.bats` (replay parity), `guided-seed.bats` (default auto). Added
one regression: toggling AMD then NVIDIA through their Display Labels yields
`["amd","nvidia"]` (also guards the ticket-1 reverse lookup for gpu).
