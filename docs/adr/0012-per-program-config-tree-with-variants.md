# ADR 0012: Per-program config tree with variants

## Status
Accepted

## Context
Today the repo manages user-side dotfiles via GNU stow. The Runner
(`.os/lib/profiles.sh:282` `_profiles_clone_dotfiles`) clones the
repo into each user's `$HOME` and runs `stow --no-folding */` — so
top-level dirs (`.config/`, `.zsh/`, `.claude/`) become stow packages
symlinked into `$HOME`.

This layout groups files by **destination path**, not by program.
One program's config is scattered across `.config/foo/`,
`.local/share/foo/`, `~/.foorc`, plus any `/etc/foo/` writes done
ad-hoc by its install.sh (e.g. `programs/privacy/searxng/install.sh`
seeds `~/.config/searxng/settings.yml`; `programs/virtualization/
virt-manager/install.sh` writes `/etc/libvirt/qemu.conf`). Two
mechanisms now place config files (stow + ad-hoc cp in install.sh),
both authoritative, neither aware of the other.

Two additional pressures:

- **Variants.** The operator wants several alternate configurations
  for the same program (e.g. zsh with theme A vs theme B) selectable
  per user, not just one canonical set.
- **One program, one identity.** A program's package list, install
  logic, and config files should be discoverable from one directory
  — not split across `.os/programs/<cat>/<name>/` and a parallel
  destination-mirrored tree at the repo root.

## Decision

### Source of truth
Each program owns a config tree under
`.os/programs/<category>/<name>/configs/`. Variants are sibling
directories named `configs@<variant>/` (e.g. `configs@minimal/`,
`configs@gaudy/`). The unsuffixed `configs/` is the default variant.

Variant names match `[a-z0-9-]+`. The literal `default` is reserved
— `variants.foo = "default"` selects `configs/`; `configs@default/`
is illegal.

### Manifest
Each `configs[@variant]/` contains a `manifest.jsonc` declaring file
placement only:

```jsonc
{
  "files": [
    { "src": "kitty.conf",
      "dst": "~/.config/kitty/kitty.conf" },
    { "src": "sessions/default",
      "dst": "~/.local/share/kitty/sessions/default",
      "mode": "0600" }
  ]
}
```

Manifest scope is **user paths only** (`~/...`). System paths
(`/etc/`, `/usr/lib/`) stay in `install.sh` as today — they need
root, run during chroot before users exist, and impermanence already
models that domain (Persist Mounts, Curated Persist Defaults).

The manifest has **no templating, no conditionals, no hooks**. If a
value needs to vary, model it as a variant. If a file needs a runtime
secret, embed the `/run/secrets/<name>` path provided by the SOPS
Runtime Service — never the secret itself.

### Variant selection
Variants are declared in **User Config** (`.os/users/<u>/
config.jsonc`) under a `variants` object keyed by program name. User
Core may declare house defaults; User Config overrides per key.

```jsonc
// users/core/config.jsonc
{ "variants": { "kitty": "minimal", "zsh": "minimal" } }

// users/aquastias/config.jsonc
{ "variants": { "zsh": "gaudy" } }
// resolved: kitty=minimal, zsh=gaudy
```

For programs with no `variants` entry: fall back to `configs/`. If a
program has only `configs@*/` and no `configs/` and the user does
not declare a variant, the generator errors.

### System programs with user-side configs
A system program (declared in Host Config) may ship a `configs/`
tree. When it does, the generator applies it for **every user on the
host**, each picking their own variant via their User Config (or
falling back to the program default).

### Generator
A new tool `.os/tools/generate-configs.sh` reads all program
manifests, resolves variants for a given user, and materializes a
per-user tree at `~/.dotfiles/.stow/<user>/` mirroring destination
paths. The tree is gitignored — never committed.

The Runner invokes the generator inside `arch-chroot`
per-user, between `_profiles_clone_dotfiles` and the existing stow
invocation. The operator can also re-run it standalone after editing
a variant:

```
$ ~/.dotfiles/.os/tools/generate-configs.sh --user aquastias
```

Flags: `--validate-only` (exit 0/1), `--dry-run` (plan, no writes).
All validation lives inside the generator; if a standalone linter is
ever needed it ships as a thin wrapper invoking `--validate-only`.

No pacman hook. Configs are authored, not derived from package
versions — package updates do not invalidate the generated tree.

### Stow integration
Two stow invocations per user:

```
$ stow -d ~/.dotfiles --no-folding .config .zsh .claude    # legacy
$ stow -d ~/.dotfiles/.stow/<user> --no-folding .           # generated
```

Legacy top-level trees continue to work unchanged. Migration is
per-program: move kitty's files into `programs/terminal/kitty/
configs/`, write the manifest, delete `.config/kitty/`.

### Conflict rule
The generator scans the legacy stow tree at run time. If it would
emit a destination already owned by a legacy package, it aborts with
both source paths named. Migration is therefore atomic per program —
there is no silent precedence and no flag-day.

## Considered alternatives

**Destination-mirror with per-program sidecar metadata.** Keep
`.config/kitty/` where it is; add a `.meta/programs/kitty.yaml`
listing owned paths and variants. Lowest churn but weakest "one
place" guarantee — files still physically scattered, the sidecar
only describes the scattering.

**Single canonical file per program, templated out.** One
`configs/kitty.toml` rendered to whatever native paths/formats the
program wants. Maximally uniform; requires a renderer per program
and a schema for each native format. Overkill for a personal repo.

**Manifest covers system paths too.** Unified declaration with a
`scope: user|system` field. Rejected: chroot phase runs before users
exist, install.sh already owns system files cleanly, and the
impermanence layer (Persist Mounts, Curated Persist Defaults) is
already the right home for system-path concerns.

**Flag-day migration.** Move every existing config in one PR. One
clean end state, one large risky change. Per-program migration
trades total churn for transition safety.

**Generator replaces stow.** Drop GNU stow; the generator writes
symlinks directly. Contradicts the explicit constraint that stow
keeps working.

**Pacman post-transaction hook re-runs generator.** Pointless cost;
configs are not package-derived.

**Variants in Install Config (picker re-prompts).** Contradicts the
Pre-Install Picker philosophy (see CONTEXT.md) that non-machine
properties never re-prompt.

**Manifest grows `encrypted: true`.** Adds a SOPS dependency to the
generator and lands plaintext secrets in `.stow/<user>/` on disk.
The `/run/secrets/<name>` indirection via the SOPS Runtime Service
already solves the underlying problem without templating.

## Consequences

- `.os/programs/<cat>/<name>/` becomes the single discoverable home
  for a program: orchestration config, install script, **and** user
  configs with variants.
- A new artefact lives on every installed host:
  `~/.dotfiles/.stow/<user>/`. Gitignored, regenerable, owned by the
  user — but visible in the filesystem and worth documenting.
- Adding a variant is a directory copy + manifest edit; no schema
  changes anywhere else.
- Programs without user-side config (most system programs) stay
  unchanged — `configs/` is optional.
- Migration of the existing top-level stow tree is unbounded in
  time. The legacy tree and the generated tree coexist indefinitely
  until every program has moved.
- The generator becomes the third tool in `.os/tools/` that operators
  invoke post-install (alongside `save-pkglist.sh` and
  `impermanence.sh`).
