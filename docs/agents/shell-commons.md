# Shell Commons

Reuse before you write. Before adding a shell helper (output, prompt,
command-existence, config read, disk math, …) check whether a Commons already
has it, and — if you must add one — put it in the *right* Commons for its
consumers. This keeps the two stdlib worlds from re-growing the duplication a
`refactor(installer): Dedup shell commons` pass removed.

## Two host-side worlds (each has its own stdlib)

- **Installer Stdlib** — `.installer/lib/common.sh`. Host-side install scripts and
  `lib/` modules. `info/warn/error/section`, `confirm`, `pick_option`,
  `cfg/cfgo`, `part_name`, `command_exists`. **Not** sourced inside
  `arch-chroot`.
- **Shell Stdlib** — `.installer/lib/shell-stdlib.sh` → `lib/shell/*.sh`. Program
  Install Scripts, sourced once by the Program Runner via `$SHELL_COMMONS`.
  `print_status`, `command_exists`, package/permission/notification helpers.

Same concept, one per world: `info` (installer) mirrors `print_status`
(programs); `command_exists` exists in *both*. That symmetry is intentional —
a helper lives in the world of its callers, never shared across.

## Boundary-forced Commons (read-only — do not merge into the above)

Split for an execution-context reason, not accidental drift. Leave them be:

- `lib/chroot/chroot-common.sh` — `common.sh` can't be sourced in the chroot.
- `lib/grub-common.sh`, `lib/chroot/bootloader-common.sh` — staged
  self-contained into runtime trees; function-only, no side effects, plain
  `echo` (no stdlib available).
- `lib/impermanence-common.sh` — shared install-time **and** runtime.
- `lib/layout/core.sh`, `lib/layout/zfs/common.sh` — layout spine (ADR 0043).
- `lib/chroot/extras-common.sh` — DE-extras adapters; own `info/section`.

## Decision tree

1. **Does a helper already exist in the caller's world?** Use it. Inline
   `command -v foo` in a script that has `command_exists` → call the helper.
2. **No helper, but the pattern repeats 3+ times in one world?** Promote it to
   that world's stdlib (`lib/common.sh` or `lib/shell/<domain>.sh`). Fewer than
   3 sites: leave inline — coincidence, not a pattern.
3. **The dupe spans a boundary** (e.g. chroot plain-`echo` vs `common.sh`
   `info`, or a staged lib vs `shell/*`)? Leave it. Collapsing across a boundary
   is an ADR question, not a refactor — the split is load-bearing.

## Don't dedup these (they look like dupes, aren't)

- ERR-trap handlers in `01/02/03-*.sh` that raw-`echo` `[ERROR]` — they fire
  *before* `common.sh` is sourced, so they can't call `error()`.
- Program scripts writing `[INFO]` to a logfile — plain `echo` is deliberate.
- `lib/shell/output.sh` local colour codes — local-scoped on purpose so the
  Shell Stdlib world doesn't leak globals.
