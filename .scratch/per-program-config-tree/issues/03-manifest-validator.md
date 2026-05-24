Status: ready-for-agent

# Manifest Validator: hardening + bats

## Parent

`.scratch/per-program-config-tree/PRD.md`

## What to build

Replace the slice-01 minimal Manifest Validator with the full spec.

Given a path to a `manifest.jsonc`, the validator enforces:

- JSONC parses cleanly via `jq`
- Top-level object has exactly one recognized key: `files` (array)
- No unknown top-level keys (unknown keys are an error so the
  schema cannot accrete silently)
- Each `files` entry is an object with:
  - `src` (string, required) — must resolve to an existing regular
    file relative to the manifest's directory
  - `dst` (string, required) — must start with `~/`, must contain
    no `..` segments, must not contain `/etc/` or `/usr/` after
    `~/` expansion
  - `mode` (string, optional) — must match `^0?[0-7]{3,4}$`
- No unknown per-entry keys (same accretion-prevention rule)

Output: ok, or a list of `(message)` errors, each naming the
manifest path and the offending entry index so the operator can
locate the problem fast.

The validator runs as part of the Generator CLI's normal flow
(every install / re-run validates first; bad manifest aborts the
whole render). Slice 06 wires it up behind `--validate-only` for
a no-side-effect lint mode.

Validation errors surface to the operator with the same
`print_status` family already used in the chroot orchestrators, so
they render consistently with the rest of install output.

## Acceptance criteria

- [ ] Valid minimal manifest (one `{ src, dst }` entry) passes
- [ ] Valid manifest with `mode` passes for accepted octal forms
      (`0600`, `600`, `0644`, `644`, `4755`)
- [ ] Malformed JSONC fails with a clear message
- [ ] Missing `files` array fails
- [ ] Unknown top-level key (e.g. `meta`) fails
- [ ] `dst` not starting with `~/` fails
- [ ] `dst` containing `..` fails
- [ ] `dst` resolving under `/etc/` or `/usr/` fails
- [ ] `mode` not matching the regex fails (e.g. `"rwxr"`, `"999"`,
      `"08"`)
- [ ] `src` file does not exist relative to manifest dir → fails
- [ ] Unknown per-entry key (e.g. `template`) fails
- [ ] Error messages name the manifest path and the offending entry
- [ ] `configs-manifest-validator.bats` covers every case above
      with fixture manifests; all bats pass
- [ ] `tests/audit.sh` still passes

## Blocked by

- `01-tracer-end-to-end-pipeline.md`
