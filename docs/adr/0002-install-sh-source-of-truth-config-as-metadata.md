# ADR 0002: install.sh is source of truth; config.jsonc is orchestration metadata

## Status
Accepted

## Context
Each program in `.os/programs/<cat>/<name>/` has both a `config.jsonc` and an `install.sh`. The question was which owns the installation logic.

## Decision
`install.sh` is the source of truth for all installation logic (package install, file copying, service enabling, directory creation). `config.jsonc` contains orchestration metadata only: display name, `system` flag (true = system program, false = user program), and optional description. The runner reads `config.jsonc` to make routing decisions, then delegates all work to `install.sh`.

## Consequences
- Complex per-program logic (e.g. teamspeak3 icon/theme directory structure) lives in `install.sh` without fighting a generic runner
- Adding a new program always requires both files — config.jsonc for discoverability, install.sh for logic
- The `system` flag is the authoritative source for whether a program is host-level or user-level; host/user configs cannot override it
