# Forbid impermanence on hybrid GPU

Status: done (6719e92)

## Parent

`.scratch/hyprland-readd/PRD.md` (ADR 0060)

## What to build

Enabling impermanence on a hybrid AMD+NVIDIA GPU fails validation with a clear
error, regardless of the selected desktop. The check runs after GPU Resolution,
so a `gpu: "auto"` profile is protected against the hardware actually detected at
install time. A single-vendor GPU with impermanence still passes.

## Acceptance criteria

- [x] Impermanence enabled + resolved GPU set contains both `amd` and `nvidia`
      → hard validation error naming the conflict
- [x] Impermanence enabled + a single-vendor GPU → passes
- [x] The error fires independent of `environment.desktop`
- [x] The check runs after GPU Resolution (works for `gpu: "auto"`)
- [x] `validation-impermanence.bats` covers pass and fail cases and is green

## Blocked by

- None — can start immediately

## Comments

- 2026-09-27 audit: 6719e92.
