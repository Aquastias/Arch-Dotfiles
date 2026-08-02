# Forbid impermanence on hybrid GPU

Status: done (847efdf)

## Parent

`.scratch/hyprland-readd/PRD.md` (ADR 0060)

## What to build

Enabling impermanence on a hybrid AMD+NVIDIA GPU fails validation with a clear
error, regardless of the selected desktop. The check runs after GPU Resolution,
so a `gpu: "auto"` profile is protected against the hardware actually detected at
install time. A single-vendor GPU with impermanence still passes.

## Acceptance criteria

- [ ] Impermanence enabled + resolved GPU set contains both `amd` and `nvidia`
      → hard validation error naming the conflict
- [ ] Impermanence enabled + a single-vendor GPU → passes
- [ ] The error fires independent of `environment.desktop`
- [ ] The check runs after GPU Resolution (works for `gpu: "auto"`)
- [ ] `validation-impermanence.bats` covers pass and fail cases and is green

## Blocked by

- None — can start immediately
