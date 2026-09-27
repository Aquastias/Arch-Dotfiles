# ESP size: 2G default + 1G floor

Status: done

## Parent

PRD: Boot-path resilience on a small FAT ESP
(`.scratch/boot-path-resilience-small-esp/PRD.md`). See ADR 0038.

## What to build

Make 2G the default ESP size for new installs and reject an
under-sized ESP. The Layout Module's ESP-size resolution defaults to 2G
when `esp_size` is unset, and a validator fails the install fast when
the resolved size is below 1G. The default is defined in exactly one
place; the explicit `esp_size` pins are removed from every host profile
and every test/VM profile so they inherit it. The floor error is
surfaced clearly, consistent with the repo's fail-fast config
validation.

## Acceptance criteria

- [x] Unset `esp_size` resolves to 2G.
- [x] A resolved `esp_size` below 1G aborts the install with a clear
      error naming the field and the floor.
- [x] The 2G default is defined once; no host or test/VM profile pins
      `esp_size` unless it genuinely overrides.
- [ ] A new single-disk and a new multi-disk install partition a 2G ESP.
- [x] Bats cover resolve (unset → 2G; explicit value passes through) and
      floor (≥1G ok, <1G error).

## Blocked by

None - can start immediately.

## Comments

- 2026-09-27 audit: 3b1ac41 (layout core; esp_size bats). Later: default became
  esp_size auto (kernel-aware, ADR 0078).
