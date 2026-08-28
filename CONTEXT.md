# Dotfiles Context

## Glossary

### Host Profile (`profile.jsonc`)
The single, self-contained file describing one machine —
`.installer/hosts/<name>/profile.jsonc`, merged under
`.installer/hosts/core/profile.jsonc`
(Host Core). Its directory basename is the profile name, the identity passed as
`install.sh --profile <name>`; there is no `host_profile` field. Collapses the
previous schema's three files (`install.jsonc` + `install.template.jsonc` + host
`config.jsonc`) into one (ADR 0036), so "the profile" is finally the whole
machine. Declares everything about the machine **except its disks**: `system`
(hostname, locale, timezone, keymap — `locale`/`keymap` accept a string or an
array whose element 0 is the default), `options` (kernel, bootloader,
encryption, swap, `ssh.enabled`, `impermanence.*`, optional `age_key_url`),
`environment` (desktop, gpu), `users` (names; `users[0]` is the Primary User),
`host_programs`, `packages` (`repo` + `aur`, both Categorized Lists), and the
full pool skeleton — `mode` plus `os_pool` / `storage_groups[]` / `data_pools[]`
carrying names, topology, mount, ashift, and `disk_count`, but **no device
paths**. Disks are machine-physical and operator-picked at install time; the
Pre-Install Picker maps them onto the declared groups to build the Effective
Config. Validated against a closed schema at load — any unknown key at any depth
aborts with its path (ADR 0036, amending ADR 0015). Independent of the machine's
hostname (ADR 0020): a profile may pin one via `system.hostname`, or let the
profile name serve as the default. Optionally ships Host Secrets alongside.

### Minimal Profile
The committed `minimal` Host Profile (`.installer/hosts/minimal/`) — the
desktop-less,
bare base install, archinstall's "minimal" role. Selects no desktop
(`environment.desktop: []`, so the display manager resolves to `none` and no DE
adapter runs — ADR 0005) and opts out of Host Core's workstation Host Package
List (`packages.inherit: false` — ADR 0056), leaving the installer's own base on
a TTY. Not a new capability: no-desktop was always representable; this is the
canonical example of it. Guided reaches the same state from scratch (Host Core
declares no desktop) or by seeding this profile.

### Effective Config
The ephemeral, fully-resolved install config the installer back-end consumes —
never a committed file. `assemble_profile_config` builds it from a Host Profile
(merged with Host Core) plus the operator's disk assignment, adding the device
paths the profile deliberately omits. Written to tmpfs by `install.sh
--profile`, or injected by the VM seed on the unattended `install.sh
<config-file>` path. Carries exactly the shape `03-install.sh` read from the
retired `install.jsonc`, so the back-end never changed. The committed audit
artifact is the Host Profile (disks excluded); this assembled artifact is
transient by design (ADR 0036).

### Pre-Install Picker
The interactive disk-resolution front-end of `install.sh --profile <name>`
(`lib/picker.sh`) — no longer a separate `tools/pick.sh`. Because the Host
Profile already carries every machine property, the picker prompts only for what
it cannot: which disk(s) to install onto. It validates the named profile against
the closed schema, enumerates `/dev/disk/by-id/*` candidates with a
`lsblk`/`smartctl` fzf preview pane, and filters out the live medium via the
shared multi-signal Live-Medium Detector (`lib/live-medium.sh`, same one the
Disk Wipe uses — boot-mount parent disk, `iso9660`/`ARCH_*` label, not
string-matching). Single mode resolves one device; multi slices the picked set
across the profile's declared `os_pool` / `storage_groups[]` / `data_pools[]`
groups by each group's `disk_count`, in declared order, rendering the per-group
mapping to stderr so a multi assignment is never implicit (ADR 0037). The
assignment is validated against the min-disk table (mirror/stripe ≥2, raidz1 ≥3,
raidz2 ≥4, none ≥2) and assembled into the Effective Config in tmpfs — `mode`
and topology come from the profile, never re-prompted. `install.sh
<config-file>` is the parallel unattended seam (the VM seed's path): it consumes
a pre-assembled Effective Config directly and skips the picker.

### Guided Installer
The interactive, menu-driven front-end of the Single Entry Point that builds an
Effective Config through a TUI instead of *requiring* a committed Host Profile —
the on-ramp for ad-hoc installs (archinstall's role). It may optionally **seed**
from a Host Profile via the in-menu **Profiles** picker (a top-screen row above
the category divider, shown **unconditionally** — even on a repo with no
committed profiles — that drills to a list of installable profiles; picking one
merges its delta over Host Core into the Config State, then the operator tweaks
or Proceeds — disks stay operator-picked), so guided is "from scratch **or** from
a profile" per run (ADR 0055, superseding ADR 0039's require-a-profile
rejection). Each profile row previews a **deep tree** of that machine (hostname,
users → shell·groups, options incl. encryption/impermanence, environment,
security, backup, disks). A `＋ New host (start blank)` row leads the picker: it
is a confirm-gated, undoable **full session reset** — clearing Config State,
session-created users and their editor forms, password/secret overrides, and any
in-menu disk bindings back to the bare Host Core baseline — broader than the
edit-history `Reset all`, which resets Config State only. Merges operator
choices over Host Core (so the shared base — swappiness, base
users, packages — still applies) and covers the full host schema. Secrets
**default** and are never gated — root + per-user passwords to `12345`, the disk
encryption passphrase to `12345678` (8 chars, because ZFS `keyformat=passphrase`
rejects a shorter one at pool creation; accounts have no such floor — ADR 0059).
The Users screen lists the account secrets for optional override; the disk
passphrase is overridden on the Disks [[Encryption Editor]]. A resolvable age
key decrypts committed secrets in their place (ADR 0055, superseding the ADR
0051/0054 Proceed gate); both defaults are runtime-only and never enter Config
State, Save, or Export. Unlike the Pre-Install Picker, which only
resolves disks against an already-authored profile, the Guided Installer also
authors the pool skeleton and every other machine property interactively.
Navigation is non-destructive: a single in-session **Config State** holds only
the operator's overrides over the computed defaults, so every screen is
re-entrant, edits commit on confirm (never on `Esc`), changes survive moving
between sections, and validation is deferred to the terminal actions. fzf is the uniform selection/navigation surface, now a **two-level** menu: a top
list of fourteen **Configuration Categories** in **install-flow order** under
six non-selectable **bucket headers** — `GENERAL` (System, Locales, Users),
`STORAGE & BOOT` (Disks, Bootloader, Kernels), `SOFTWARE` (Environment,
Mirrors & Repositories, Pacman, Packages), `SERVICES` (Daemons),
`SECURITY & DATA` (Security, Backup), `ADVANCED` (Expert) — each category
opening a submenu of its fields, so a section name never repeats per row.
(ADR 0071 established the two-level model; ADR 0081 re-cut it into buckets,
renamed General → **System**, and merged the Printing/Bluetooth/Power service
toggles into one category. ADR 0086 then renamed every category that echoed its
bucket header — **Services** → **Daemons**, **Advanced** → **Expert** — and the
`SYSTEM` bucket → **`GENERAL`** so `System` no longer repeats it.) The bucket
headers, the divider, and
the blank spacers between buckets are **inert** — the cursor auto-skips them
(a fzf `focus` bind, ADR 0083), so only Profiles, a category, and the terminal
actions are ever selected. Presentation is
**master-detail**: the fzf preview pane shows the highlighted item's live state,
and the current selection is marked by the **triangle pointer (`▶`)** in the main
list. On the **top screen** the pane shows only the highlighted category's own
`key: value` fields with the `●` override dots — the category **parent column was
dropped** (ADR 0082) as a duplicate of the bucketed main list. **Drill (category)
screens** still show a **sibling-field column** (the category's fields, current
marked, the rest dimmed) above the leaf detail — there it lists fields, not a
copy of the main list. A leaf field previews its current value and allowed
options; the Disks layout leaf previews the ZFS pool tree and the Users category
its account table (both reusing the existing previews). Navigation stays
drill-down (Enter deeper, Esc up) with a breadcrumb — archinstall's own
behaviour. Every value list is an fzf list, and
multi-select re-entry pre-marks prior picks; only free-text fields with nothing
to enumerate (hostname, package names, sizes, URLs, `sysctl` pairs, persist
paths) drop to a typed prompt. Terminal actions (Proceed / Save / Export) are
selectable rows under a divider; the edit-history toolbar (Undo / Redo / Reset
field|section|all) is bound to footer keybindings, not rows. Every **action
row** (`＋ Create/Add …`, `✗ remove …`, `← Back`) renders as a visible list row
in rich chrome, not just on the `^A`/`^X`/`Esc` accelerators — amending ADR
0047's actions-on-keybindings split, whose hidden `＋ Create user` was
undiscoverable on modern fzf (ADR 0063). The Users-screen `name — shell · pw`
rows preview a **full user panel** on hover (shell, sudo, groups, programs, git,
SSH keys). Computed defaults
seed an untouched run: hostname `eterniox`, `users[0]` = `aquastias` (Primary
User), single-disk ZFS layout, locale `en_US.UTF-8` / timezone
`Europe/Bucharest` / keymap `us`. The **baseline is loaded from Host Core**
rather than hand-copying a few of its values (ADR 0058), so everything core
installs surfaces as a seeded-but-unmarked row — core's package list, once
hand-copied and invisible. (`cups` was the original example; it has since become
a toggle-derived Host Program with its own menu home — ADR 0079.) Core
therefore enters the pipeline exactly once; the
emitter does not merge it again. The **Packages** category drills `repo` →
category → package toggles (and `aur` likewise), with three-state provenance
reusing the override dot: checked-without-dot means inherited from core,
checked-with-dot means added here, unchecked-with-dot means excluded. Unchecking
an inherited package writes a `packages.exclude` entry — the only way the
exclusion mechanism is reachable from the menu. The toggle list can offer only
the declared union across core and the profile, so a brand-new package stays a
free-text entry. A read-only **`derived`** section lists what the current
Environment, Security and Backup choices pull in, grouped by source and naming
the category that drives each, via the same [[Package Resolver]] the CLI
inspector calls. A typed extra-packages entry is **routed by kind at entry
time** — a Host Program name to `host_programs`, a User Program name to the
Primary User's `programs`, anything else to `packages.repo` — so what reaches
Config State is already canonical; the old emit-path promotion rule, which made
the same file install differently per front-end, is deleted. Save Profile writes
a **delta over Host Core**, so a saved profile stays layered rather than
freezing a snapshot. Mistakes
are recoverable three ways — re-edit, **Reset** (field / section / all, the last
itself undoable), and **Undo/Redo** over a snapshot stack. Ends in one of four
terminal actions: **Proceed** (assemble the Effective Config in
tmpfs from the choices plus the picked disks, then install now), **Save Profile**
(write `hosts/<name>/profile.jsonc` — the committed, device-less audit artifact,
replayed via `--profile`), **Export Effective Config** (write the
device-baked artifact to an operator-chosen path *outside* the repo's `hosts/`
tree, replayed via `install.sh <config-file>`), or **Abort** (an explicit
action row, Esc-equivalent: quit the menu cleanly so `install.sh` skips the
back-end — pre-destructive only, nothing on disk to undo; ADR 0077). The
committed save strips disks;
only the export carries them — preserving 0036's invariant that device paths are
never committed as repo source of truth. The third front-end over the one
back-end.

### In-Menu Disk Binding
The Guided Installer's device-aware mode for authoring a multi-disk layout
*inside* the menu (as opposed to the device-less post-menu resolution the
Pre-Install Picker path uses). Selected automatically by hardware presence
(evaluated once at launch), never a manual switch: when real disks are enumerable
the pool editor binds actual `/dev/disk/by-id/*` devices per group (device-mode);
when authoring off-target with no disks it falls back to the abstract `disk_count`
cycle (count-mode). On-target it is *bind-all* — OS pool, preset storage groups
(disks only; topology/existence stay preset-fixed), data pools, and the
single-disk root (a `root disk:` row) all bind in the menu, so a fully-bound
layout runs no post-menu pick. A bound pool carries an additive `devices[]` list
and its `disk_count` is *derived* as the number bound; a counted pool carries only
`disk_count`. `devices[]` is transient — it never reaches a validated artifact:
Save Profile flattens it back to counts (`disk_count` = number bound, `devices`
dropped), preserving the device-less profile invariant (ADR 0036); Proceed/Export
lift it into the per-group assignment instead. Presets contribute a group's
topology and name but never auto-bind
disks — binding which physical disk goes to which pool is always the operator's,
one at a time.

### Display Label
The human-facing name of a menu item in the Guided Installer, as distinct from
its stored Config State value. Acronyms and proper names read correctly (KDE,
NVIDIA, ZFS, SSH, LTS, ESP), field labels and value choices are cased
consistently, and technical or free-text tokens (a device path, a locale, a
`key=value` pair, a typed hostname) are shown verbatim. A Display Label is a
rendering concern only: it never changes what is stored, and selecting a
re-cased row still resolves to the same underlying value.

### Cycle Field
A Guided-Installer leaf whose whole value set is `true`/`false` and which
therefore **flips in place** on the category screen — Enter advances to the
other value and stays put (`echo refresh`), never drilling into the values
submenu (ADR 0075). A field is a Cycle Field structurally, by its option set
being exactly `{true, false}` (`_ctl_is_cycle_field`), so a newly-added bare
bool becomes one with no list to maintain. Scope is **bare bools only**: the
five Pacman flags, the three Security and two Backup bools, and Advanced→SSH —
eleven in all. A bool that owns a richer editor (encryption, impermanence — both
`▸` editor rows) is **not** a Cycle Field; it keeps drilling. Mirrors the older
Manual-Partitioning in-place flip, now generalized. Reuses the strict-delta
apply (`_ctl_apply_enum` + `_ctl_normalise_default`), so flipping back to the
default clears the override and the `●` dot; a Manual-Partitioning-locked field
is a silent no-op. The detail pane lists both values with the current one marked
so the choice stays discoverable without the submenu. _Avoid_: "toggle" — that
term already means the multi-select (TAB-many) leaf kind in this installer.

### Free Set
The pool of physical disks still available to bind during In-Menu Disk Binding:
every enumerated `/dev/disk/by-id/*` candidate, minus the live medium, minus
every device already bound to *any* group (OS pool, storage groups, data pools
share one set — a disk lives in exactly one pool). A pool's `＋ add disk` action
offers only the Free Set and disappears when it is empty (the "noop when
exhausted" rule). Exhausting the set can leave a pool below its topology minimum;
that is not prevented at selection time but caught by the existing skeleton
validation before Proceed, naming the under-populated group.

### Manual Partitioning
A Guided-Installer-only disk-config mode, toggled on/off from the **Disks**
screen, that hands the whole partition table to the operator instead of the
installer's predefined (auto) pool layouts. Turning it on fires a one-time
confirm notice: manual is the deliberately feature-light escape hatch, so it
disables everything that lives on the pool machinery — ZFS/pool layouts, disk
encryption (Encryption Editor), impermanence (Impermanence Editor), multi-disk
data pools / storage groups and pool owners, managed swap (the zswap default),
and the ESP-size field — which stay **shown-but-locked** on the Disks screen so
the operator sees what was given up. The operator partitions by hand (cfdisk,
where swap is a partition they cut for themselves), then assigns each resulting
partition a mountpoint (or `[swap]`) and a format-or-keep choice; a viable
install requires exactly one ESP and one root. Reversible and non-destructive to Config
State like every other guided choice — auto↔manual toggles without losing either
side's overrides — and its partition assignment is **transient**, never reaching
a committed or exported artifact, mirroring the device-less invariant (ADR 0036).
Because a hand-drawn table cannot be replayed from a committed file, manual is
**Proceed-only**: no Save Profile, no Export, and it never appears on the
`--profile` Pre-Install Picker or the unattended `install.sh <config-file>` path.
Distinct from the predefined (auto) layouts, whose pool skeleton is the
installer's default.

### Host Core
Declarative JSONC file at `.installer/hosts/core/profile.jsonc`. Declares the
base set
of users, Sysctl Defaults, **and the Host Package List** shared across all hosts
(ADR 0056, amending ADR 0007 — whose "the lists are
machine-specific" premise failed: `laptop` is a strict subset of `desktop`, 57
repo packages in both and zero unique to laptop). Holds the 63 packages both
machines share (57 repo + 6 AUR), so each Host Profile is a **delta** and
`hosts/laptop` carries
no packages block at all. Every Host Profile is resolved over core by the
[[Layer Resolver]] — core applies first, then the host profile per the ADR 0057
per-key classification. A host drops something core declares via
`packages.exclude[]` or `host_programs_exclude[]`; the three VM fixtures opt
out of the inherited package set wholesale with `packages.inherit: false`
(scoped to packages — they still inherit core's users and sysctl). Also the
Guided Installer's menu baseline (ADR 0058), so everything core installs is
visible and deselectable in the menu. Core declares **five** free-standing base
Host Programs (`ccache`, `fwupd`, `gamemode`, `lact`, `smartmontools` — ADR
0089); `cups`, once its sole entry, has since moved out to a toggle-derived Host
Program with its own menu home (ADR 0079).

### Layer Resolver
`.installer/lib/config/layer-resolver.sh`. The pure module answering "given Host
Core
and a host profile, what is the effective set?" — and the same for User Core and
a user profile. Resolution is **per-key**, classified by unordered set versus
ordered selection (ADR 0057): *additive* keys concat + dedupe and `exclude`
subtracts (`packages.repo.*`, `packages.aur.*`, `host_programs`, `users`,
`persist.*`, `sysctl`, and user-side `groups`/`programs`/`ssh_authorized_keys`);
*replace* keys are overwritten wholesale by the later layer (`options.kernel`,
`system.locale`/`keymap`, `environment.desktop`/`gpu`,
`options.mirror_countries`, `storage_groups[]`, `data_pools[]`, every scalar).
Anything not listed additive is replaced, so a new key cannot start
concatenating by accident. Layers fold in order and the **last layer wins**, so
a host may re-add something a lower layer excluded; exclusions apply from the
upper layer only. `packages.inherit: false` is applied before the fold. The
control keys are stripped from the output — they instruct the resolver and must
never reach a consumer. Pure: JSON in, JSON out, no filesystem, no TTY, so the
layering contract is testable without a VM. Replaces the two divergent merge
rules that were in use (concatenation in config load, replacement in the guided
view), **both** of which were load-bearing where they were. The subtract-then-
strip exclusion logic has **one** implementation — the jq `apply_exclusions` def
in `layer_jq_exclusions`, included by both the fold (`_layer_fold_one`) and the
guided effective-config path (`layer_apply_exclusions`), mirroring how
`layer_jq_prelude` already shares `is_additive` with the Save-path inverse, so
the two exclusion paths cannot drift.

### Config Store
`.installer/lib/config/store.sh`. The **effectful** edge over the pure Config
State —
owns the Guided Installer's triad session files (`GUIDED_STATE_FILE` /
`GUIDED_NAV_FILE` / `GUIDED_BASELINE_FILE`) behind a small named interface
(`cfgstore_state` / `cfgstore_write_state`, `cfgstore_nav` /
`cfgstore_write_nav`, `cfgstore_baseline` / `cfgstore_write_baseline`) so no
caller pokes the tmpfs paths directly. `config/state.sh` (`cfgstate_*`) stays
**pure** (JSON in/out); the Config Store is where the file IPC lives, once. fzf
runs each keystroke bind in a **fresh shell**, so the session state must be
process-external — the backing is a tmpfs file read via the `GUIDED_*_FILE` path
the launcher (`guided_run_persistent`) exports; there is **one adapter** (the
file), and the controller tests set the same globals to a temp path, asserting
behaviour through it unchanged. The controller's private `_ctl_state` /
`_ctl_write_state` / `_ctl_nav` / `_ctl_write_nav` / `_ctl_baseline` now delegate
here, and the former direct pokes in `guided-fzf-entry.sh` (the `cfdisk` /
`pkgbrowse` execute() verbs) and `guided.sh` (the session seed/read in
`guided_run_persistent`) route through it. Scope is the Config State
triad; the other session handoff files (secrets, userforms, history, pw buffers,
session-undo, skip, list, result) are separate concerns not yet folded in.

### Package Resolver
`.installer/lib/packages/resolver.sh`. The pure module answering "what actually
lands
on this machine?" — an Effective Config in, every package out, each tagged with
its **source** and **layer**. The layer is provenance: `derived` for a computed
set, or `core` vs `host` for an authored one, so the report answers "do I edit
Host Core or this host profile?". Covers the authored
slots, the [[Base Package List]], and every derived set: kernel and headers,
bootloader, GPU drivers, audio, filesystem tools, ZFS/LUKS userland, login
shells, the Plasma shell, KDE applications, KDE AUR, the display manager
(`sddm` / `greetd` / `greetd-tuigreet`, keyed on the resolved `display_manager`;
`sddm-kcm` stays with the KDE set — ADR 0069), Security & Backup Extras,
and secrets-activated `sops`. Every input is declarative, so it makes **no
pacman query and no network call** and stays deterministic and testable
headless. Eighteen distinct paths put a package on the system and only five are
authored — the answer is not fewer paths but a way to *query* the result.
Consumed by `tools/explain-packages.sh`, the Guided Installer's read-only
`derived` section, and the real-profile regression tests, so those three cannot
drift. Excluded packages are reported separately by `pkgres_excluded` (read from
the *authored* profile — the Layer Resolver strips the key once applied), and
the sets that genuinely need the target hardware (GPU `auto`, CPU microcode) by
`pkgres_unresolved`, so they are never faked as package names.

### User Profile
Declarative JSONC file at `.installer/users/<username>/profile.jsonc` (renamed
from
`config.jsonc` in step with the host side — profile = a host/user, config = a
program spec; ADR 0036). Declares a user's shell, sudo access, groups, which
user-level programs are installed, and an optional `user_services` list enabled
via `systemctl --user enable` after the user's programs and dotfiles are placed
(a unit missing at enable time aborts with an actionable message). Optional
fields: git identity, SSH authorized keys. `git` must be declared explicitly as
a user program — it is not installed by default. Passwords are not stored in the
profile — hardcoded as `12345` by default unless User Secrets override. User ↔
Host-Program references (refining the old always-abort rule, ADR 0036): a
user-level program may shadow a Host Program; referencing a Host Program the
host already installs is a no-op; referencing one no host installs aborts with
an actionable message — the `system` flag stays host-owned (ADR 0002). Applied
on top of User Core.

### User Editor
The Guided Installer sub-screen opened by Enter on a user in the flattened Users
screen (a single `root — shell · pw` row opening the [[Root Editor]], users
shown `name — shell · pw` with a `⚠` when unset, `＋ Create user`). Exposes the
full User Profile — enabled/remove, shell,
password, sudo, groups, git identity, SSH keys, programs. Edits are
install-scoped: they bake into Proceed and Export but never rewrite a committed
`users/<name>/profile.jsonc` (ADR 0051). A committed user's editor shows its
effective (core-merged) values while storing only a delta. A committed user can
be *disabled* (excluded from the install) but not removed; only a session-created
user is removable. A `⧉ Clone this user` row copies the source's effective
account-shape (shell, sudo, groups, programs — never git identity, SSH keys, or
password) into a new ad-hoc user and opens its editor (ADR 0064). Distinct from
the User Profile, which is the committed file; the User Editor is the transient,
per-install override surface over it. Root's account is a single Users-screen
row opening the [[Root Editor]] (see [[Root Shell]]).

### Root Editor
The Guided Installer sub-screen opened by Enter on the single `root — shell · pw`
row of the flattened Users screen — the root counterpart of the [[User Editor]],
symmetric with it so every account row opens its own editor. Collapses the two
former Users-screen rows (`root password` + `root shell`) into one row and one
editor exposing exactly `password` and `shell` (root has no groups/sudo/programs).
The password is captured the inline-masked, type-twice-confirm way (ADR 0051) and
stored in the no-SOPS manifest under the root role; `shell` cycles `/bin/bash` →
`/bin/zsh` → `/bin/fish` (see [[Root Shell]]). Install-scoped like the User
Editor: it bakes into Proceed/Export, never a committed file.

### Encryption Editor
The Guided Installer sub-editor reached from the single `Encryption ▸` row on
the **Disks** screen (kept beneath the filesystem row, whose choice derives the
cipher), which collapses the disk-encryption decision into one place: an
enablement toggle plus the ZFS/LUKS passphrase (ADR 0059, superseding the
separate `encryption` toggle + passphrase row of ADR 0054 and the Users-screen
`Disk encryption` override of ADR 0055 — the Users screen is now accounts-only).
The collapsed row summarises both facts — `on · <source>` (spelling the default,
`on · custom`, `on · from age`) or `off`, plus the standard override dot.
Modelled on the swap sub-editor, the Editor shows only `enabled` when off (a
passphrase configures nothing then) and adds a `password` row when on; `enabled`
cycles in place and setting a passphrase never flips it. The passphrase is
captured the same inline-masked, type-twice-confirm way as the root/user
passwords (ADR 0051) and stored in the no-SOPS Secrets Manifest under
`enc_passphrase` (never in Config State, Save, or Export); its one divergence
from the password rows is that first entry must be **≥ 8 chars** — the ZFS
`keyformat=passphrase` minimum. It is never gated (an unset passphrase defaults
to `12345678`); toggling encryption off hides the `password` row but retains any
stored value. The back end (`collect_enc_passphrase`) consumes it by precedence
`INSTALL_ENC_PASSPHRASE` → guided manifest → unattended default → interactive
prompt, so an interactive profile/manual install keeps the tty prompt while
`--unattended` takes the default (ADR 0059, extending ADR 0054).

### Impermanence Editor
The Guided Installer sub-editor reached from the single `Impermanence ▸ on/off`
row on the **Disks** screen (with the standard override dot), which merges the
enablement toggle and persist-directory management into one section — replacing
the former inline `impermanence:` toggle plus a separate `Add persist directory`
action row (ADR 0066). Modelled on the [[Encryption Editor]] / swap sub-editor,
it collapses when off (only `enabled: off`); when on it shows `enabled: on`
(strict-delta), one removable row per user-added persist directory, a read-only
`curated defaults: N paths always persisted` line, and an `Add persist
directory` action appending to `persist.directories`. Scope is directories only
(`persist.files` and the ZFS-only `dataset`/`mount` stay file-editable);
directories already stored are retained, not purged, when impermanence is
toggled off. Menu surface only — the stored shape, install-time validation, the
hybrid-GPU ban (ADR 0060), and rollback mechanics (ADR 0008 / 0044) are
unchanged.

### Root Shell
The root login shell, chosen in the Guided Installer via the `shell` row of the
[[Root Editor]] (Enter cycles `/bin/bash` → `/bin/zsh` → `/bin/fish`, the same
cycle the User Editor uses). Stored at Config State `options.root_shell` (default
`/bin/bash`, normalised out when equal to the default), so it bakes into Export
and a saved profile like any host option; not gated (it always has a valid
default). Applied in the chroot by `lib/chroot/password.sh` (`chsh` root plus a
missing-shell package install, mirroring `create-user.sh`), so root can never be
left with an unusable login shell (ADR 0054).

### User Core
Declarative JSONC file at `.installer/users/core/profile.jsonc`. Declares the
base set
of programs, shell defaults, groups, and House Defaults shared across all users.
Every User Profile is resolved over core by the [[Layer Resolver]] — core
applies first, then the user profile per the ADR 0057 per-key classification
(`groups`/`programs`/`ssh_authorized_keys` additive; `shell`/`sudo`/
`user_services` replace). A user drops something core declares via
`programs_exclude[]`; the two throwaway VM test users use it for `docker` and
`virt-manager`.

The default `shell` is **`/bin/zsh`**: the entire tracked shell payload is zsh
(18 files under `.zsh/` plus `.zshrc`, `.zshenv`, `.zprofile`, `.zsh_aliases`,
`.p10k.zsh`) while `.bashrc`/`.bash_profile`/`.profile` are untracked, so a bash
default landed a fresh install in a shell whose stowed config never loaded. Root
stays `/bin/bash` (see [[Root Shell]]). Neither `zsh` nor `zinit` is declared as
a package: `ensure_login_shell_installed` pacman-installs a user's login shell
when the binary is missing, and the zinit config git-clones itself on first
interactive shell — which means the first login after install needs network.

### Primary User
The first entry in a host's `users` array (`users[0]` in
`.installer/hosts/<profile>/profile.jsonc`, merged with Host Core) — the same
user the
Runner uses for the shared AUR/paru pass (`profiles.sh` gates host + GPU AUR
installs on `users[0]`). Purely positional: there is no `primary: true` flag, so
ordering the `users` array chooses it. A host that declares no users has no
Primary User. The conventional default owner for host-wide, user-facing
resources: it is the AUR/paru user, and the default owner of a data pool whose
`owners` field is omitted (see Pool Owners). Exactly one per host; distinct from
root.

### Program Config
Declarative JSONC file at `.installer/programs/<category>/<name>/config.jsonc`.
Contains orchestration metadata only: display name, `system` flag, optional
description, and optional [[Program Dependency]] (`requires`). The adjacent
`install.sh` is the source of truth for installation logic.

### Program Dependency (`requires`)
A `requires: [name, …]` array in a [[Program Config]] naming other Programs
whose install-time setup — package **and** side effects (e.g. podman's
subuid/subgid + linger) — must be in place before this one runs (ADR 0065).
Enforced at
`validate_install_context` before any side effect: a required program must be a
[[Host Program]] (installed before all user programs) or appear earlier in the
same user's `programs` list, since the [[Runner]] installs a user's programs in
declared order. A missing or later-ordered dependency aborts up front with an
actionable message rather than hard-failing mid-install. Today only `searxng`
declares one (`["podman"]`).

### Host Program
A program that requires root and is installed via pacman during the chroot
phase — host-owned, not any user's (contrast [[User Program]]). Declared in the
host's `host_programs` field (renamed from `system_programs` by ADR 0085,
completing ADR 0084's deferral). Usually declared in a Host Profile or Host
Core. Marked `"kind": "host"` in its program config (the `"system": true` bool
became a `kind` enum, ADR 0085). Only official repo packages (no AUR) should be
Host Programs. The registry now marks **twelve** programs `kind: host`, reaching
the install four ways. **Authored**: Host Core declares five free-standing base
host programs (`ccache`, `fwupd`, `gamemode`, `lact`, `smartmontools` — ADR
0089), and a Host Profile declares `grub`. **Control-derived**, injected into
`host_programs` at assembly and never in a committed list: `cups`/`bluetooth` by
a Daemons toggle, `power-profiles-daemon`|`tuned` by the Power enum, `reflector`
by the Mirrors & Repositories section (see [[Printing Service]] / [[Bluetooth
Service]] / [[Power Profile]] / [[Mirror Service]] — ADR 0079/0080/0089).
**Secrets-activated**: the sops Program, selected by the Runner when
install-state records secrets (see SOPS Runtime Service, ADR 0025).

The `system` flag is carried by the [[Program Registry]] and is
**authoritative** (ADR 0058): a program's name resolves to exactly one kind,
and that kind decides which slot may declare it. The Guided Installer's host
`host_programs` picker offers only `kind: host` programs and the User
Editor's `programs` picker only
`kind: user` ones — one unfiltered list used to feed both, so the host side
could build a config that failed validation at Proceed.

### Menu-Owned Program
A registry Program whose install is governed by a **dedicated menu control** —
its control is the program's **sole home**, so it is never default-installed as
a program and never listed in either Programs picker (host or User Editor).
Generalizes the `*_owned_programs` filter that already delisted `cups` /
`bluetooth` / `power-profiles-daemon` / `tuned` (ADR 0079/0080) into one
`menu_owned_programs` union covering every control-owned program (ADR 0086):
`grub` (Bootloader enum), `firewalld` / `ufw` / `clamav` / `rkhunter` /
`apparmor` (Security toggles), `borg` / `zfs-auto-snapshot` (Backup toggles),
`sops` (secrets activation), and `reflector` (the Mirrors & Repositories
section, ADR 0089 — its sole home, like cups' is Printing). The unconditional
base host programs promoted under ADR 0089's rule (`ccache`, `fwupd`,
`gamemode`, `lact`, `smartmontools`) are the exception — free-standing
`kind: host` programs owned
by no control; they install via Host Core's `host_programs` and are dropped from
a bare install by `inherit: false`. Consequence: no `kind: host` program is
operator-pickable — the Guided Installer's
**Packages** category lists no Programs at all (its `host programs` row dropped;
the name stays `Packages` — no longer a misnomer, and avoids echoing the
`SOFTWARE` bucket) — the only pickable Programs are the five
free-standing User Programs (`docker`, `podman`, `virt-manager`, `searxng`,
`teamspeak3`) in the [[User Editor]]. Delisting only; a deliberate free-text add
is still allowed — the `＋ Add` guard informs (Menu-Owned → "managed by
\<Control\>") or offers (free-standing user program → "add under Users") rather
than silently reclassifying. Removes the duplicate representation (e.g. `clamav`
appearing as a Program when Security already installs it) without changing any
control's default — whether the program installs is still the control's call.

### Printing Service (`options.printing.enabled`)
The Guided-Installer toggle governing whether `cups` — the CUPS print daemon —
is installed and its `cups.service` enabled. A single bool [[Cycle Field]]
(default `true`, normalised-out when true) in the shared **Daemons**
Configuration Category (ADR 0081; its own **Printing service** category
pre-merge), a service-enablement field rather than an identity field like
System's hostname/timezone. `cups` is
**not**
declared in Host Core; when the toggle is on it is **injected into the Effective
Config's `host_programs` at assembly time**, so the [[Runner]] installs it in
the chroot exactly as an authored Host Program would (its Program dir /
`install.sh` are unchanged). The first **toggle-derived Host Program** —
`options.ssh.enabled` only enables a service on the always-present `openssh`,
whereas this toggle gates the package install itself, so cups is genuinely
absent when off. The Printing toggle is cups's **sole** menu home: it is
filtered out of the Packages → system-programs picker, and surfaces in the
read-only `derived` section / `explain-packages` as `source=printing` (layer
`derived`) — the one place the resolver reports a Host Program at all (ADR
0079).

### Mirror Service (Mirrors & Repositories)
The Mirrors & Repositories section's owned Host Program: `reflector`. Unlike the
toggle-derived [[Printing Service]] it is **state-independent** — the section
has no on/off bool; it always injects `reflector` into the Effective Config's
`host_programs` at assembly time (`lib/config/mirrors.sh:mirrors_inject`), so
the [[Runner]] installs the package and enables the weekly `reflector.timer` on
every install (ADR 0089). `reflector` is **not** declared in Host Core; the
section is its sole menu home, filtered from the Packages picker
(`mirrors_owned_programs`) and reported by the resolver as `source=mirrors`
(layer `derived`). Distinct from the install-time use of `reflector` (the ISO's
copy ranks mirrors once during `install_base` from the operator's Mirror
Countries) — this is the *installed system's* recurring refresh.

### Bluetooth Service (`options.bluetooth.enabled`)
The second **toggle-derived Host Program**, twinning [[Printing Service]]: a
single bool [[Cycle Field]] (default `true`, normalised-out when true) in the
shared **Daemons** Configuration Category (ADR 0081). On → a `bluetooth` program
is injected into the Effective Config's `host_programs` at assembly time,
installing `bluez` + `bluez-utils` and enabling `bluetooth.service`; off →
genuinely absent. Owns only the **daemon layer**, never a GUI frontend: on KDE
`bluez`/BlueDevil already arrive via `plasma-meta`, so the injection is a
`--needed` no-op and the toggle's real contribution is *enabling the service*
(nothing else does today). A Hyprland-session tray is a separate concern — the
[[Desktop Environment Adapter]] for Hyprland ships `blueman` with a
`NotShowIn=KDE` autostart, so a KDE session shows BlueDevil and a Hyprland
session shows blueman (ADR 0080). Filtered from the Packages → system-programs
picker like `cups`; surfaces as `source=bluetooth` in the resolver.

### Power Profile (`options.power.profile`)
The **enum** generalization of the toggle-derived pattern (ADR 0080, extending
0079's bool): a choice field `none | power-profiles-daemon | tuned` (default
`power-profiles-daemon`) in the shared **Daemons** Configuration Category
(ADR 0081; its own **Power** category pre-merge).
Unlike a bool toggle — which only decides *whether* a package lands — the value
picks *which* daemon is injected and whose service is enabled
(`power-profiles-daemon.service` / `tuned.service`); `tuned` additionally pulls
`tuned-ppd` so a KDE/Hyprland applet keeps a working switcher. DE-agnostic:
`powerprofilesctl` / `tuned-adm` drive it with no desktop, so "I don't use KDE"
is a non-issue — pick `tuned` or `none`. `power-profiles-daemon` is only an
*optional* dep of Powerdevil, so this key genuinely adds it even on KDE.
Surfaces as `source=power` in the resolver.

### Font Catalog (`options.fonts`)
The curated multi-select font list, modelled on `options.kernel`: an enumerated
option set (in `menu_enum_options`) that the operator TAB-checks, some
pre-checked, resolved to packages before pacstrap. **Replaces**
`packages.repo.fonts`, which is **deleted from Host Core** so a font has exactly
one home (mirroring cups' removal from core, ADR 0079). The resolver is
repo+AUR aware — the lone AUR entry (`ttf-ms-fonts`, kept because
`ttf-liberation` covers only Arial/Times/Courier metrics, not
Verdana/Georgia/Tahoma) routes to the Primary-User paru pass. Lives as a leaf
in the **System** Category (ADR 0080; renamed from General by ADR 0081), the
one non-identity resident there.
Default-checked spans the Noto family (incl. `noto-fonts-cjk` for CJK glyphs),
`ttf-liberation`, `ttf-dejavu`, `ttf-ms-fonts`, and the Nerd-patched monospace
trio (`ttf-jetbrains-mono-nerd`, `ttf-iosevka-nerd`, `ttf-firacode-nerd`);
`otf-monaspace-nerd` and `ttf-sazanami` are selectable-but-off. The Nerd builds
supersede plain ones (`ttf-fira-code` dropped) because the tracked shell payload
is Powerlevel10k, which renders Nerd glyphs.

### Program Registry
The in-memory index built once per run by `configs_build_registry`
(`lib/config/layers.sh`), mapping each program name to its `category/name` path
**and** its `kind`. Exposes `program_kind <name>` → `host` | `user` |
`none`, and `program_names_of_kind <kind>`. Backs the exclusivity validator,
both Guided Installer program pickers, and the [[Package Resolver]], so a menu
render never re-parses twenty-four `config.jsonc` files.

### User Program
A program installed for a specific user via the AUR Helper inside the chroot.
Declared in a User Profile or User Core. Marked `"kind": "user"` in its program
config. The AUR Helper is bootstrapped per user before any user programs are
installed. `base-devel` is hardcoded into pacstrap and always available in the
chroot.

### AUR Helper
The AUR helper the Runner bootstraps per user and installs AUR packages with —
`paru` by default, `yay` the fallback. Bootstrap is a **resilience ladder** (ADR
0052): `paru` from source, then `paru-bin`, then `yay-bin`, each retried shallow
(2 retries, 3s/10s backoff) before dropping to the next rung; the `-bin` rungs
pull a checksum-pinned prebuilt binary from GitHub Releases, a different
endpoint than the source-tarball codeload, so a transient codeload outage no
longer aborts the install. The landed helper's name is the **`$AUR_HELPER`**
value: the Runner exports it (per user) into each User Program's `install.sh`
alongside `INSTALLER_DIR` / `PROGRAMS` / `SHELL_COMMONS`, resolving it once at
bootstrap. The "paru preferred, yay fallback" rule lives in one place —
`_profiles_detect_helper` (`lib/aur-helper.sh`), shared with the standalone
`tools/install-pkglist.sh`. Only exhausting all three rungs aborts, cleanly.
Resolution is per user — a transient blip leaving one user on `paru` and
another on `yay` is harmless.

### Runner
`.installer/lib/profiles/runner.sh`. Reads host core + host profile (merged),
validates
program references (a user referencing a Host Program no host installs aborts;
one the host already installs is a no-op — ADR 0036), installs Host Programs
via `arch-chroot`, then for each user merges user core + user profile and
installs programs via `arch-chroot /mnt su - <username>`. Called by
`03-install.sh` after `configure_system()`.

### Single Entry Point
`.installer/install.sh`. The one script a user runs from the Arch live CD after
cloning
the repo. Three front-ends over one back-end (ADR 0036): `install.sh --profile
<name>` (interactive — the Pre-Install Picker resolves disks and assembles the
Effective Config in tmpfs; the user-facing path), `install.sh <config-file>`
(the unattended seam consuming a pre-assembled Effective Config; the VM seed's
path), and the **Guided Installer** (a from-scratch menu that builds an
Effective Config interactively when no profile exists yet). Orchestrates: ZFS bootstrap → disk wipe → partition → pacstrap → system
config → Host Programs → user programs → cleanup and pool export.

A global **`--debug`** modifier turns any front-end into inspect/author-only: it
skips the full-toolchain preflight (only the front-end tools `jq`+`fzf` are
ensured, so the menu still launches) and **blocks the install** — the numbered
phases (01/02/03) never start, so no disk is touched. The interactive front-ends
still run for inspection (the guided menu and previews, the `--profile` disk
picker) and Save/Export still write their artifacts; only the install is
withheld. It exists so the menu can be exercised on a non-target box (a daily
driver) that has neither the install toolchain nor an intent to install; plain
`install.sh` on the live CD stays fully guarded. Named `--debug` despite the
"skip install" (not "verbose logging") meaning, documented at the flag site.

### Disk Wipe
`.installer/02-wipe.sh`, the install flow's **make-blank** step — not a
secure-erase.
It clears partition tables, filesystem signatures, and ZFS/LVM/MD labels so a
target disk looks pristine to the partitioner. Method is device-aware:
`blkdiscard` on SSD/NVMe (instant), a single zero-pass on HDDs (the slow case,
shown as a per-disk progress bar; disks wiped in parallel). Multi-pass/forensic
erase (`shred`, ATA secure-erase) is deliberately out of scope. Two safety
invariants hold: the **live medium is never listed, selectable, or wipeable**
(detected by multiple signals — boot-mount parent disk, `iso9660`/`ARCH_*` label
— not string-matching), and an **install-driven wipe touches only the install's
target disks** (`os_pool` + `storage_groups` + `data_pools` disks resolved from
the Effective Config and passed in explicitly), never an unrelated disk that
holds data. Run standalone it wipes only an explicitly selected target set,
defaulting to nothing.

### Installer Stdlib
`.installer/lib/common.sh`. Shared utility library for host-side install scripts
and
`lib/` modules — colour codes, `info/warn/error/section`, `confirm`,
`pick_option`, `cfg/cfgo`, `part_name`, `command_exists`. **Not** sourced inside
`arch-chroot` (that world uses `chroot-common.sh`). The installer-world twin of
Shell Stdlib: same concepts, one stdlib per world, never shared across.

### Shell Stdlib
`.installer/lib/shell-stdlib.sh` — a **facade** that sources the domain modules
under
`lib/shell/` (`output.sh`, `commands.sh`, `permissions.sh`, `packages.sh`,
`notifications.sh`). Shared utility library sourced once per program by the
Program Runner (not by the install.sh itself), so program scripts get its
helpers (`print_status`, `command_exists`, package/permission/notification
helpers) without their own source line.

### Program Install Script
`install.sh` inside each `.installer/programs/<category>/<name>/`. Source of
truth for
all installation logic: package install, file copying, service enabling. Invoked
by the Program Runner via `lib/profiles/program-runner.sh`, which validates staging, sources
Shell Stdlib, then sources the install.sh in the same shell. Receives env vars
`$INSTALLER_DIR`, `$PROGRAMS`, `$SHELL_COMMONS` pre-exported. Programs are
referenced
by name only across all categories (names are unique).

### Layout Module
`.installer/lib/layout/zfs/<mode>.sh` (`zfs/single.sh`, `zfs/multi.sh`; ADR
0043). Each
implements the layout interface (`layout_validate`, `layout_plan`,
`layout_partition`, `layout_create_pools`, `layout_mount_esp`) and publishes a
normalized state record consumed by chroot/finalize: `LAYOUT_ESP_PARTS[]`
(resolved ESP device paths, primary at index 0), `LAYOUT_OS_POOL_NAME`,
`LAYOUT_DATA_POOL_NAME` (empty when no data pool). `layout_validate` is a pure
check (no state writes) — called by `validate_install_context` to gate disk
paths and mode-specific topology before any work begins; exits via `error` on
first failure. The active module is selected by `INSTALL_MODE` and sourced from
`03-install.sh` **before** `validate_install_context` runs, so the dispatcher
can call `layout_validate` on the active adapter. The seam wrappers enforce
phase ordering via `_layout_enter_phase` / `_layout_exit_phase` in
`lib/layout/core.sh` (phases: validate→plan→partition→pools→esp); a verb called
out of order aborts via `error` before any destructive operation. Mode-private
globals (`SINGLE_*`, `MULTI_*`, `OS_ESP_PARTS`, `STORAGE_PARTS`,
`RESOLVED_TOPOLOGIES`) stay inside the module — consumers only read `LAYOUT_*`.
Reframed as the ZFS **Filesystem Adapter** once the filesystem axis lands: the
mode-keyed split *is* ZFS today (ADR 0040).

### Filesystem Adapter
The seam that selects the on-disk filesystem. The top-level `filesystem`
discriminator (default `zfs`; `btrfs`, `ext4`, `xfs`) names the **OS/root**
filesystem; data groups may each carry an *optional* per-group `filesystem` that
defaults to the root value, so one machine can mix filesystems by group (e.g.
ZFS root + an ext4 data disk). Each adapter owns its volume model (ZFS pools +
datasets; btrfs subvolumes; ext4/xfs bare partitions) and its multi-disk story:
ZFS and btrfs have **native** topology (mirror/raidz; raid0/1/10), while ext4 and
xfs are **single-disk only** (no mdadm/LVM — a group set to ext4/xfs rejects
`disk_count > 1`; use ZFS or btrfs for redundancy). Encryption is
filesystem-conditional: ZFS native AES-256-GCM (`native`) vs dm-crypt/LUKS
*under* the filesystem (`luks`) — one shared passphrase seam, only the consumer
differs. Impermanence and the Bootloader Adapter's `root=` are also
filesystem-conditional: Impermanence is offered on the snapshotting filesystems
ZFS and btrfs only (never ext4/xfs). The additive `options.encryption_method`
(`native` | `luks`, default derived from `filesystem`) and the fs-keyed dispatch
mean a new filesystem is an additive adapter, never a schema migration (ADR 0040,
extended by ADR 0043). See [[Root Layout Adapter]] and [[Data Group Formatter]]
for the dispatch split.

### Root Layout Adapter
The filesystem-and-mode-keyed half of the layout dispatch that owns the **OS
disk**: partitions it (`ESP + [swap] + root`), formats/creates the root volume,
and hands the Bootloader Adapter the right `root=` (ZFS → `root=ZFS=<pool>/ROOT`;
ext4/xfs → `root=/dev/mapper/cryptroot` or `root=UUID=…`; btrfs adds
`rootflags=subvol=…`). Selected by `root_adapter_source <fs> <mode>`. The ZFS
single/multi Layout Modules become the ZFS Root Layout Adapter, relocated under
`lib/layout/zfs/` (ADR 0043).

### Data Group Formatter
The filesystem-keyed (mode-independent) half of the layout dispatch that formats
**one** data group with *its* chosen filesystem — a group is just disks +
topology + fs, with no single/multi notion. The multi-disk data-pool loop
dispatches each group via `data_formatter_source <fs>`; ZFS's existing data-pool
creation becomes the ZFS Data Group Formatter (ADR 0043).

### Storage Group
A vdev (or set of per-disk vdevs) folded into the single Combined Data Pool in
multi-disk mode. Declared in `storage_groups[]` in the Host Profile (`name`,
`disk_count`, `mount`, optional `topology`/`ashift`/`owners`) — devices are
operator-picked and assigned to the group by the Pre-Install Picker, never
committed. Each group surfaces as datasets under `dpool/DATA/<name>`; all groups
share one pool and therefore one failure domain. Use a Storage Group when you
want several disks pooled together (with redundancy) under one name. Contrast
Standalone Data Pool.

### Combined Data Pool
The single `dpool` assembled from every Storage Group (and any leftover OS disks
folded in when OS topology is `none`) in multi-disk mode. One pool, one failure
domain. Optional — absent when there are no Storage Groups and no folded
leftovers. Contrast Standalone Data Pool.

### Standalone Data Pool
A ZFS pool that owns its disk(s) outright rather than folding into the Combined
Data Pool — its own name, mountpoint, topology, and **failure domain**, so one
pool losing a disk never affects another. Declared per-entry in `data_pools[]`
in the Host Profile (`name` = the zpool name and `disk_count` required; optional
`topology`/`mount`/`ashift`/`owners`); operator-picked devices are assigned by
the Pre-Install Picker. Topology is limited to
`stripe`/`mirror`/`raidz1`/`raidz2`; `none` and `independent` are rejected —
"each disk separate" is expressed as multiple entries, and "all disks, no
redundancy" is `stripe`. Encryption inherits the global `options.encryption`.
Multi-disk only. Also producible interactively: when OS topology is `none`, each
leftover disk may be chosen per-disk as its own Standalone Data Pool (named at
the prompt) instead of folding into the Combined Data Pool. Contrast Storage
Group.

### Pool Owners
The optional `owners` field on a `data_pools[]` or `storage_groups[]` entry —
the principals granted read/write to that pool's mountpoint, so a human (not
just `root`) can use it. Each element is a username or a `@group` (the `@`
distinguishes the two namespaces; groups come from a User Profile's `groups`).
Omitted → the Primary User. A single bare user → a plain `chown` (mode `0755`).
More than one principal, or any `@group` → POSIX ACLs (`acltype=posixacl`): the
first listed user is the nominal owner, and every user / `@group` gets an `rwx`
entry plus a default-ACL so new files inherit it; group grants stay dynamic
(membership lives in a User Profile, not a snapshot). Every user with access —
listed users plus members of listed groups — gets a `~/Disks/<pool>` symlink so
any file manager (GUI or TUI) reaches it without per-app bookmarks. Validated at
install: a bare name must be a declared user, a `@group` must have ≥1 declared
member. Applied install-time after the Runner creates users + groups, on the
host against the altroot-mounted paths, resolving each owner to a numeric
UID/GID from the installed `/etc/passwd` + `/etc/group` (the live ISO has no
knowledge of the chroot's users); ACL group grants use `g:<gid>:rwx` so
membership stays dynamic. (ADR 0031.)

### Program Runner
`.installer/lib/profiles/program-runner.sh`. Wrapper invoked by the Runner inside arch-chroot for
every Program Install Script. Verifies the chroot-side staged tree (Shell Stdlib
readable, install.sh readable) and exits 99 with a clear message on mismatch.
Sources Shell Stdlib once and sources the install.sh in the same shell, so
install.sh files inherit `set -Eeuo pipefail` and the stdlib helpers without a
per-script source line.

### Chroot Configuration Module
`.installer/lib/chroot/`. Set of shell scripts copied into
`/mnt/root/lib-chroot/`
before `arch-chroot` and orchestrated by `configure.sh` inside the chroot. Each
sub-script owns one concern: identity (locale/timezone/keymap/hostname), pacman
config, initcpio (ZFS hook + mkinitcpio), root password, an extras runner
(KDE desktop adapters), plus a Bootloader Adapter. `lib/chroot.sh` shrinks to
live-ISO concerns: write_fstab, write_esp_mirror_hook, collect_passwords, and
the single `arch-chroot` invocation that stages and runs `configure.sh`.

### Chroot Staging Manifest
The declared set of `lib/` files the chroot phase copies into the new root,
held as data in `lib/chroot.sh` (`_CHROOT_STAGE_LIBCHROOT` flat siblings of
`lib/chroot/*` under `/root/lib-chroot`; `_CHROOT_STAGE_EXTRAS_LIB` helpers
under `/root/lib`) and materialized by one `_chroot_stage` copy verb — instead
of a run of imperative `cp` lines. Because the dependency set is explicit, a
bats check (`tests/chroot/chroot-staging.bats`) asserts every manifest source
still exists and that every `$_LIB_DIR/<name>.sh` sibling a chroot script
sources is staged. Makes the lib-foldering lockstep fail at bats time, not in
the VM: a renamed/moved `lib/` file breaks the manifest's source path and the
check catches it.

### Install State
`lib/install-state.sh`. Sole owner of the `install-state.json` wire format that
carries config from the host phase into `arch-chroot` (`install_state_write`
host-side, `install_state_load` chroot-side; a schema list keeps the two in
sync). Also owns the credential keys `.secrets.*` (SOPS-backed) and
`.guided_passwords.*` (the Guided no-SOPS injector): `install_state_credential_path`
resolves a host/user role to its decrypted-file path with the precedence
`.secrets` then `.guided_passwords`, and `install_state_activates_sops` is the
`.secrets`-only gate that triggers the SOPS Runtime Service (ADR 0025) — the
Guided key deliberately never does. Consumers (the Chroot Configuration
Module's host-secrets resolver, the Runner's user-secrets resolver) call these
rather than re-encoding the jq, so the precedence and the SOPS-gate invariant
live in one place.

### Bootloader Module
The seam selecting between Bootloader Adapters. The active adapter is chosen by
`options.bootloader` in the Host Profile — one of `systemd-boot`, `grub`,
`efistub`, `limine`, `refind` (default `systemd-boot`), a **closed set**
validated at profile load against `menu_enum_options options.bootloader`, so an
unknown loader aborts with its path (ADR 0077). The chroot orchestrator invokes
`bash /root/lib-chroot/bootloader-${BOOTLOADER}.sh`. Adding a new bootloader
means dropping in a new Bootloader Adapter plus one Bootloader Manifest row — no
`if/elif` branches grow.

### Bootloader Adapter
`.installer/lib/chroot/bootloader-<name>.sh`. Concrete bootloader
implementation:
package install, config file generation, kernel-image entry registration. Five
adapters: `bootloader-systemd-boot.sh`, `bootloader-grub.sh`,
`bootloader-efistub.sh`, `bootloader-limine.sh`, `bootloader-refind.sh`. Each
reads the same env vars from the orchestrator (`KERNEL`, `ROOT_DATASET`, ESP
info, etc.) and is interchangeable from the orchestrator's view. Four of the
five are ESP-mirroring loaders; `grub` is the native-ZFS special case (ADR
0077).

### ESP-mirroring loader
The class of Bootloader Adapters — `systemd-boot`, `efistub`, `limine`,
`refind` — that boot by reading the kernel, microcode, and initramfs the ESP
Kernel Sync mirrors onto the FAT32 ESP, so they boot a ZFS root without reading
ZFS. They differ only in **entry format** (systemd loader entry / `efibootmgr`
load-options / `limine.conf` / `refind_linux.conf`) and loader-binary path,
both carried by the Bootloader Manifest. `grub` is excluded — it reads ZFS
natively and needs no ESP mirror to find its kernel. **efistub** is a
direct-UEFI boot *method* (one `efibootmgr` entry per kernel + fallback), not a
loader binary; its manifest loader path is the kernel image itself (ADR 0077).

### Bootloader Manifest
`.installer/lib/boot/bootloaders.sh`. The pure token table — sourced host-side
by the
package resolver / list and staged into the chroot for the orchestrator —
keying each `options.bootloader` value to its EFI loader path, package set, and
ESP-entry style. The single source of truth that replaced the per-loader
`if grub/else systemd` chains in `configure.sh`, `resolver.sh`, and `list.sh`
(ADR 0077).

### ESP Kernel Sync
The pacman hook (`94-esp-kernel-sync.hook` →
`/usr/local/lib/archzfs/esp-kernel-sync.sh`, installed from the shared
`lib/boot/esp-kernel-sync.sh`) that copies the kernel image, microcode, and
initramfs from the ZFS `/boot` onto the FAT32 ESP after every kernel
transaction — required because every ESP-mirroring loader (systemd-boot,
efistub, limine, refind) reads its kernel from the ESP, not ZFS. Not installed
under `grub`, which reads ZFS natively. The files mirrored
are driven by the loader entries: only files an entry references (its
`linux`/`initrd` lines) that exist in `/boot` are copied, so a Stray Kernel —
having no entry — is never mirrored, and a missing file is never referenced.
Numbered `94` so it runs before the ESP Mirror Hook. Distinct from it (ADR
0038).

### ESP Mirror Hook
The pacman hook (`95-esp-mirror.hook` → `/usr/local/sbin/esp-mirror`) installed
only on multi-disk OS layouts (≥2 ESPs); it rsyncs the primary ESP
(`/boot/efi`) onto every secondary ESP (`/boot/efi1`, …) so each OS disk stays
independently bootable. Bootloader-agnostic. Runs after the ESP Kernel Sync
(`94` < `95`) so secondaries receive freshly-synced images. Distinct from the
ESP Kernel Sync.

### Environment Config
The `"environment"` key in the Host Profile. Declares desktop environment
selection, display manager selection, and GPU driver selection. Audio is not declared — it is auto-derived
(PipeWire when any desktop is selected, omitted for server installs). Processed
at config-load time; resolves into the derived `GPU_PACMAN_PACKAGES` and
`AUDIO_PACKAGES` sets before pacstrap. These are internal, never authorable —
they used to share the `packages.groups` namespace, which made a derived set
look like something the operator declares; that key is gone and authoring it
aborts at load (ADR 0056). Valid desktop values: `"kde"`, `"hyprland"`, `"niri"`
(array-shaped, multi-select co-installs allowed; adding a DE stays
zero-runner-change, ADR 0005/0062/0090). Valid GPU values: `"amd"`, `"nvidia"`,
`"intel"`, `["amd", "nvidia"]`, or `"auto"`. Valid `display_manager` values:
`"auto"` (default — desktop-aware: `sddm` when `kde` is present, else `greetd`
for a KDE-free set; `none` if no desktop, ADR 0091), `"greetd"`, `"sddm"` (ADR
0069). Valid `niri_shell` values: `"noctalia"` (default) | `"none"` (ADR 0090).
Replaces `post_install.desktop` from the previous schema.

### Desktop Environment Adapter
Script at `extras/desktop/<name>/<name>.sh`, optionally with a companion
`install-<name>.jsonc` for per-component toggles (KDE has one for its app list;
the Hyprland adapter is core-only and ships none — ADR 0062). Invoked
dynamically by the Environment Runner based on `environment.desktop`. KDE,
Hyprland, and niri are the three adapters (ADR 0090). Each adapter owns every
DE-tied package (apps, Qt plugins, AUR theming bridges) **and every DE-tied
config default**: it installs its repo packages via pacman, writes its session
files (and, for Hyprland, enables seatd), enables its services, and — for KDE —
seeds the DE's default look (Breeze Dark, Papirus-Dark icons, Breeze cursors)
plus per-app first-run state into `/etc/skel` and `/etc/xdg` so a fresh login is
ready, not first-run (ADR 0088). The KDE package set is **all data** in
`install-kde.jsonc`, parsed in bool mode: the Plasma shell itself is
`shell_packages` (gated by the `shell` bool), and the app set is split by
provenance across `apps_list` (packages in the `kde-applications` group) and
`apps_extra` (KDE-ecosystem repo packages outside that group — ADR 0087). The
[[Package Resolver]] reads the same `install-kde.jsonc`, so what the adapter
installs and what the resolver reports (source `kde-shell`) cannot drift — the
shell list is no longer a fixed pacman line mirrored in the resolver. The display manager is **not** its concern
(ADR 0069) — a separate [[Display Manager Adapter]] owns package, config, and
enable. AUR dependencies are not installed by the adapter — they are declared
in an optional top-level `aur` field of `install-<name>.jsonc` (same 2-level
Categorized List `{ category: { pkg: bool } }` shape as `apps_list`, validated
in bool mode; absent field contributes nothing) and installed by the Profiles
Runner's paru pass. Adding a new DE requires only a new `extras/desktop/<name>/`
directory — no runner code changes.

The **niri adapter** is core-only like Hyprland but leaner: the `niri` package
ships its own session file + `niri-session` and pulls `seatd`, so it authors no
launcher shim and no aquamarine DRM pin (ADR 0090). Its one companion is the
[[Wayland Shell Companion]], selected via `environment.niri_shell`.

### Wayland Shell Companion
The Noctalia desktop shell as an optional, menu-visible layer on a niri install,
selected via `environment.niri_shell` (`noctalia` | `none`, default `noctalia`;
meaningful only when niri is in the desktop set — ADR 0090). `none` = bare niri,
seeding nothing (Hyprland core-only precedent). `noctalia` = the **prepared work
preset**: the `noctalia` package (v5, `extra` repo — one package for bar,
launcher, notifications, clipboard history, control center, lock, wallpaper, OSD)
plus the session-completing gaps `kitty` + `brightnessctl`, a minimal
`/etc/skel/.config/niri/config.kdl` glue that autostarts `noctalia --daemon`
(ADR 0088 skel precedent). Since ADR 0093 the preset is **enriched by default**:
it also seeds the **Rosé Pine** built-in palette (`[theme]`, the one theming
exception to 0090's glue-only rule) and a curated, overlap-free plugin set —
`keymap`, `screen-toolkit`, `wl-screen-mirror`, `arch-updater`, `procmon`,
`audio-switcher`, `file-search`, `shell-command`, `ssh-launcher`, `mini-docker`,
`custom-shortcut`, `udiskie`, `todo`, `drive-health`, `eyecare`, `gamer-mode`,
`cat`, `wallpaper-switcher`, the three `niri-*` plugins, and the official
**Bitwarden** plugin, plus laptop-gated `battery-power-management` +
`battery-widget`. Plugins install pinned from two registered sources (official +
community). Preset component bools — one per plugin, plus `laptop`, `cava`,
`cliphist` — live in `install-niri.jsonc`, mirroring KDE's `install-kde.jsonc`
(ADR 0087); toggling them off recovers the lean shell. Noctalia runs on Hyprland
too; the field is niri-bound for now but written to generalise.

### Environment Runner
The extras dispatcher in `lib/chroot/extras.sh`. Iterates the resolved
`environment.desktop` array and invokes each Desktop Environment Adapter by
directory convention (`extras/desktop/<de>/<de>.sh`), then invokes the resolved
[[Display Manager Adapter]] (`extras/dm/<dm>/<dm>.sh`) — after the desktop loop,
so every session file and seatd already exist (ADR 0069). No DE or DM names are
hardcoded in the runner — dispatch is purely by convention. Security & Backup Extras are
no longer dispatched here — they install via the Profile Runner's Primary-User
paru pass (see Security & Backup Extras). AUR discovery for the
selected DEs lives alongside this: for each desktop in the resolved array the
installer reads that adapter's `aur` list and unions it (deduped) with the
host's `packages.aur` into the Profiles Runner's single paru invocation, so
DE-tied AUR packages land only when their DE is selected.

### GPU Resolution
Translation of `environment.gpu` into driver packages at config-load time.
`"auto"` uses `lspci` on the live ISO to detect all GPU vendors and resolves to
a string or array. Hybrid configs (e.g., `["amd", "nvidia"]`) install per-vendor
drivers; they no longer add `envycontrol` — the deterministic hybrid config is
owned by the chroot GPU Configuration Module (see GPU Hardening, ADR 0053). The
resolved vendor list is also threaded into install-state (`.gpu`) so the chroot
can decide whether to harden. Resolved packages populate the derived
`GPU_PACMAN_PACKAGES` set before pacstrap.

Vendor → package mapping:
- `"amd"` → `vulkan-radeon xf86-video-amdgpu mesa libva-mesa-driver`
- `"nvidia"` → `nvidia-open-dkms nvidia-utils lib32-nvidia-utils
  libva-nvidia-driver egl-wayland` (open kernel module only; requires
  Turing+/RTX 20xx+; DKMS used so it builds against both `linux` and
  `linux-lts`)
- `"intel"` → `intel-media-driver` (Broadwell/5th-gen+) or `libva-intel-driver`
  (pre-Broadwell), auto-selected by parsing `lspci` device ID
- VM GPU (VMware/VirtualBox/virtio-gpu) → `mesa` only (software rendering);
  detection logs a notice and continues without aborting

### GPU Hardening
The deterministic AMD+NVIDIA hybrid configuration applied by the chroot **GPU
Configuration Module** (`lib/chroot/gpu.sh`) when GPU Resolution detects **both**
`amd` and `nvidia` (ADR 0053). Auto-gated on the resolved `.gpu` vendor list —
no config field. Runs before initcpio so the single `mkinitcpio -P` bakes it in.
The set: a `modprobe.d` NVIDIA config (`nvidia_drm modeset=1 fbdev=1`,
`NVreg_PreserveVideoMemoryAllocations`, `NVreg_DynamicPowerManagement`, `blacklist
nouveau`), **Early KMS** (the nvidia modules in `MODULES=`), an **RTD3** udev
rule, the suspend/resume/hibernate services, and an initramfs-regen pacman hook.
Replaces the never-invoked `envycontrol` switcher.

- **Hybrid Graphics / PRIME Offload** — the runtime topology: the AMD iGPU drives
  the internal panel and the KDE compositor; the NVIDIA dGPU stays idle until an
  app is offloaded to it (`prime-run`). Matches the firmware's switchable-
  graphics mode.
- **Early KMS** — loading the nvidia kernel modules from the initramfs (via
  `MODULES=`) so kernel modesetting is up before the display, closing the
  half-initialised-dGPU race.
- **RTD3** — fine-grained runtime power management that lets the idle dGPU reach
  D3cold (powered off), the main battery win on the hybrid laptop.

### Display Manager
Operator-selected via `environment.display_manager` — `auto` | `greetd` |
`sddm`, default `auto` (ADR 0069, superseding ADR 0067's "greetd owns the DM
whenever Hyprland is installed"). **Full symmetry**: any DM launches any DE —
SDDM for Hyprland or KDE+Hyprland, greetd for KDE. This became a choice once
**seatd** (ADR 0068) gave aquamarine DRM master independent of the DM; before
that an SDDM-launched Hyprland session could not obtain master (atomic KMS
commit `Permission denied`, retry-loop, black screen — kwin survived it, ADR
0067), so greetd was *forced* whenever Hyprland was present. `auto` is **desktop-aware** (ADR 0091,
superseding the fleet-wide-SDDM code and ADR 0069's stale body): `greetd` for a
KDE-free non-empty desktop set (hyprland and/or niri), `sddm` when the set
contains `kde`, and `none` when no desktop is selected. It is a smart default,
not a lock — a concrete DM still overrides freely (seatd makes any DM launch any
DE, so the pairing is preference, not constraint). A **concrete** DM with an empty desktop set aborts at
config-load (a greeter with no session). Dispatched as a [[Display Manager
Adapter]] by the Environment Runner after the desktop loop, so the choice is
independent of DE adapter execution order. The DM adapter owns its package +
config + enable; the DE adapters own the session files and seatd and no longer
touch any DM. The greeter still sees a curated
`/usr/local/share/wayland-sessions` (written by the Hyprland adapter) holding
exactly the good sessions — its own `hyprland.desktop` (`env -u WAYLAND_DISPLAY
-u DISPLAY start-hyprland`, the 0.53+ launcher; unset vars force aquamarine's
DRM backend over its nested one), the **sole** Hyprland session, and — on a KDE
co-install — Plasma. The packaged `hyprland-uwsm.desktop` is deliberately not
curated and `uwsm` is not installed (ADR 0070): its systemd-user
`graphical.target` orchestration deadlocks on the first post-boot login under
impermanence (ADR 0061 pre-starts `user@uid`), black-screening only the uwsm
session while start-hyprland and Plasma work. Under impermanence the same
display-manager login is used — no tty1 autologin — with the enablement
mirrored onto the never-rolled-back `/usr/lib` tree via the DM-agnostic
`display-manager.service` alias so it survives the rolled-back root (ADR 0061).

### Display Manager Adapter
Script at `extras/dm/<name>/<name>.sh`, invoked by the Environment Runner after
the desktop loop based on the resolved `environment.display_manager` (ADR 0069).
Mirrors the [[Desktop Environment Adapter]] and Bootloader Adapter
convention-dispatch (no DM name is a literal in the runner). `dm-greetd` and
`dm-sddm` are the two adapters. Each owns exactly its DM: **package install**,
config, and `systemctl enable` — `dm-greetd` writes `config.toml` pointing
`tuigreet --sessions` at the curated `/usr/local/share/wayland-sessions`;
`dm-sddm` installs and enables sddm (so SDDM on a Hyprland-only host now has an
owner — the KDE adapter no longer installs it) and writes a `Wayland.SessionDir`
(+ X `SessionDir`) sddm.conf.d drop-in pinning that same curated dir ahead of
`/usr/share`, so both DMs show one deduped session list. Adding a future DM is a new
`extras/dm/<name>/` directory — no runner change. Runs after every DE adapter,
so the session files and seatd it relies on already exist.

### User Secrets
SOPS-encrypted JSON file at `.installer/users/<username>/secrets.json`. Contains
sensitive per-user data: `password`, `ssh_identity_private_key`, and
`ssh_identity_key_type` (`ed25519` | `rsa` | `ecdsa`; defaults to `ed25519`).
Values are encrypted (keys remain plaintext). Optional — if absent, user
password defaults to `12345` and no SSH identity is deployed. Parallel to the
User Profile; read by the Secrets Module at install time and consumed by user
creation and SSH provisioning. Not merged with User Core — secrets are always
user-specific.

### Host Secrets
SOPS-encrypted JSON file at `.installer/hosts/<profile>/secrets.json`. Contains
`root_password` for the host. Parallel to the Host Profile; read by the Secrets
Module at install time and consumed by root password provisioning. Optional — if
absent, root password falls back to interactive prompt.

### Secrets Module
`lib/secrets.sh`. Runs immediately after config load in `03-install.sh`. Locates
the passphrase-encrypted Operator Age Key via two sources in priority order: (1)
a removable USB device scanned for `/age/key.age`; (2) an HTTPS download from
`options.age_key_url` in the Host Profile (live-CD fallback when no USB is
present). Prompts for the passphrase, decrypts all User Secrets and Host Secrets
to a tmpfs, and writes the tmpfs paths into `install-state.json` for consumption
by chroot scripts. Clears the tmpfs after the chroot phase completes.

### Machine Age Key
Age private key stored at `/etc/secrets/age/keys.txt` on the installed system.
Derived at install time from the machine's `ssh_host_ed25519_key` via
`ssh-to-age`. Used exclusively by the SOPS Runtime Service for boot-time
decryption. Must be added as a recipient in `.sops.yaml` and secrets
re-encrypted via `sops updatekeys` after first install.

### SOPS Runtime Service
Systemd service installed by `.installer/programs/security/sops/install.sh`.
Runs early
in boot (before user services), mounts a tmpfs at `/run/secrets/`, decrypts all
SOPS-encrypted secret files using the Machine Age Key, and sets declared
ownership and permissions. Programs that need runtime secrets reference
`/run/secrets/<name>` paths. The sops Program is secrets-activated: the Runner
installs it (deriving the Machine Age Key and building `ssh-to-age` via `go`)
only when the host or one of its declared users ships a `secrets.json` —
consistent with secrets being optional. It is therefore not a member of any
host's declared Host Programs, including Host Core; a host with no secrets
gets neither the service nor `go`.

### Base Package List
The **unconditional** set pacstrapped onto every host regardless of config — the
18 always-on names (`base`, `base-devel`, `linux-firmware`, `networkmanager`,
`openssh`, `cronie`, `efibootmgr`, `dosfstools`, `vim`, `git`, `sudo`, `rsync`,
`jq`, `pacman-contrib`, `stow`, `man-db`, `man-pages`, `texinfo`). Now a shared
pure module, `lib/packages/base.sh:base_packages`, and one of the [[Package
Derivation Maps]] — consumed by **both** `lib/packages/list.sh:collect_packages`
(install) and the [[Package Resolver]] (query), so the two can never disagree on
what "base" is. Config-*conditional* additions (selected kernel + headers, CPU
microcode, `zfs-dkms`/`zfs-utils`, `cryptsetup`, `xfsprogs`/`btrfs-progs`, GPU +
audio) are **not** part of this set — they come from their own Package
Derivation Maps. What the **installer itself** needs, as distinct from the [[Host
Package List]] in Host Core, which is what this *fleet* wants — the two are
different layers, not competing ones. A Host Package List is deduplicated
against it at install time. `stow` belongs here because the Runner invokes it
unconditionally for every user during the dotfiles step, yet no layer guaranteed
it — only the two host profiles happened to declare it, so every VM fixture hit
`stow: command not found`. Universal infrastructure daemons whose package lives
here (NetworkManager, cron) are enabled by the Chroot Configuration Module, not
by a Program (ADR 0026).

### Package Derivation Maps
The shared **pure** modules under `lib/packages/` that hold a package-name set
once so the install path and the [[Package Resolver]] cannot drift:
`base.sh` (`base_packages` — the [[Base Package List]]), `gpu.sh`
(`gpu_vendor_packages <vendor>`), `audio.sh` (`audio_packages` — the PipeWire
stack), and `filesystem.sh` (`fs_userland_packages <fs>` + `luks_userland_packages`),
alongside the older-established `kernel.sh`, `boot/bootloaders.sh`, and
`config/fonts.sh`. Each maps an already-resolved input to package **names** only;
the **decision** of which inputs apply, and any impure **detection**, stay with
the caller — GPU vendor detection (`lspci`) and the intel pre-Broadwell
refinement live in `config/environment.sh`, so the resolver stays headless and
`environment.sh` owns the hardware edge. The pattern: extract the pure name list
to a map both callers source, keep detection out of it. This is what lets the
Package Resolver *query* the same names the installer *installs* rather than
mirror a second hand-typed copy.

`collect_packages` reads `packages.repo` from the **Effective Config**, not by
re-loading a committed profile keyed on hostname: the guided and inline-config
front-ends have no `hosts/<hostname>/` directory to re-read, so anything they
authored was silently dropped.

### Host Package List
`packages` object in Host Core or a Host Profile with two authored fields:
`repo` (official-repo packages installed via pacstrap) and `aur` (AUR packages
installed via paru for the Primary User). Both are 2-level categorized objects —
kebab-case category keys mapped to string arrays — flattened to a sorted-unique
list by the Categorized List Parser at install time. Categories are cosmetic;
renaming `media` to `multimedia` does not change what installs. Shape,
leaf-type, or category-name violations abort at config-load with the offending
path. Declared in **Host Core** for what every machine shares and in a Host
Profile for that machine's delta (ADR 0056). Deduplicated against base packages
by the installer. AUR packages are installed once for the system via the first
declared user's paru instance before any user programs run.

`repo` and `aur` are the **only** authored repo/AUR slots. `packages.extra[]`
(which was `repo` without a category) and `packages.groups.*[]` (used by no
profile, and sharing a namespace with the internal GPU/audio buckets) were
removed and now abort at load as unknown keys. The routing rule is mechanical:
*does the name resolve to a Program directory?* — yes and `kind: host` → host
`host_programs`; yes and `kind: user` → user `programs`; no →
`packages.repo` or `packages.aur`. A name is **either a Program or a package,
never both**: an overlap aborts at config load naming the path and the correct
slot (ADR 0058),
which replaced a promotion rule that ran only in the Guided Installer's emit
path and so made the same file install differently per front-end.

Three control keys accompany the authored slots, consumed by the [[Layer
Resolver]] and stripped from the resolved output: `packages.exclude[]` and
`host_programs_exclude[]` on a host profile, `programs_exclude[]` on a user
profile, and `packages.inherit` (bool, default true) scoped to packages only.

### Sysctl Defaults
`sysctl` object in Host Core (or a host-specific Host Profile), containing
key-value pairs written verbatim to `/etc/sysctl.d/99-os.conf` during the
profiles phase. Applied to every host via Host Core. A host-specific config can
add keys (they deep-merge per the core merge rules) but cannot remove keys
declared in core.

### Security & Backup Extras
The `post_install.security` and `post_install.backup` objects in a Host
Profile — the host's hardening and backup tool selection, authored by hand or by
the Guided Installer's Security / Backup categories. `security` picks one
firewall (`firewalld` | `ufw` | none; the two are mutually exclusive) plus
`clamav` (antivirus), `rkhunter` (rootkit scanner), and `apparmor` (MAC);
`backup` picks `zfs-auto-snapshot` and/or `borg`. The selected tools are
paru-based User Programs (`kind: user`; paru refuses root), so they are
**not** installed as Host Programs — the Runner unions the resolved program
names into the **Primary User's** paru pass (the seam host AUR packages already
use), and each tool's existing Program Install Script runs unchanged. Supersedes
the former boolean `post_install.*` extras, which dispatched to never-shipped
`extras/security.sh` / `extras/backup.sh` (ADR 0041). A host with no users
cannot carry these — the Guided Installer aborts at the terminal action.

### Tools
`.installer/tools/`. Utility scripts for managing a running system or preparing
an
install — not part of the install flow itself. Currently: `save-pkglist.sh`
(writes a Drift Snapshot of the running system to
`hosts/<profile>/pkglist-repo.txt` and `pkglist-aur.txt`),
`install-pkglist.sh` (installs packages from those files, skipping their
header), `explain-packages.sh` (see Package Resolver), `impermanence.sh` (see
Impermanence Tool), and `fetch-iso.sh` (downloads + sha256-verifies the
archzfs-Compatible ISO for USB prep). The pkglist tools take a **profile**
name (a `hosts/<name>/` directory), not a hostname — ADR 0020 decoupled the
two, and deriving the directory from `$(hostname)` is what left
`save-pkglist.sh` failing on every real machine. They fall back to
`$SAVE_PKGLIST_PROFILE`, then `$(hostname)`, and name the available profiles
when resolution fails.

### Drift Snapshot
The output of `save-pkglist.sh`: a flat `pacman -Qqen` / `-Qqem` dump of what
is explicitly installed on a running machine, stamped with a `#` header naming
the profile and warning against replay. It is a **diff** artifact, not a
profile source — replaying it into a profile would collapse Host Core, the
host delta and every derived set into one host's list, undoing the layering on
first use. Compare it against `explain-packages.sh <profile>` to find drift. A
profile-aware version emitting only the genuine host delta is separate work.

### archzfs-Compatible ISO
Newest archived Arch ISO (from `archive.archlinux.org`) whose kernel major.minor
matches a kernel `archzfs` ships a prebuilt `zfs-linux` for. The prebuilt-kernel
list is used as a proxy for "the current ZFS source is known to compile against
this kernel" — even though the installer always builds ZFS via DKMS, not the
prebuilt. Resolved by `iso_resolver_get_zfs_compatible` in
`lib/packages/iso-resolver.sh`. The installer cannot use the latest Arch ISO when its
kernel is newer than `archzfs` tracks: DKMS then fails to build the ZFS module
against that kernel.

### Kernel Selection
`options.kernel` in the Host Profile: one or more kernel flavour tokens naming
which kernels the installed system gets. Accepts a single token (string) or a
list. Tokens map to a kernel package plus its matching headers:
`lts`→`linux-lts`, `default`→`linux`, `zen`→`linux-zen`,
`hardened`→`linux-hardened`. Every selected kernel is installed, and `zfs-dkms`
builds the ZFS module against each. `lts` is the only token `archzfs` is
guaranteed to track; any other (notably `default`, the rolling kernel) may
temporarily outrun `archzfs` and is caught by the ZFS Module Guard. Defaults to
`lts`.

### Primary Kernel
The first token in the Kernel Selection. Drives the bootloader default boot
entry and the initramfs preset/fallback logic — exposed to chroot modules as the
scalar `KERNEL` (the full list is `KERNELS`). When more than one kernel is
selected, the others are still installed and `mkinitcpio -P` builds their
presets, but the bootloader default and the custom fallback-preset injection
track only the Primary Kernel until full multi-kernel preset wiring lands.

### ZFS Module Guard
Post-pacstrap check, host-side, run before chroot configuration begins. Verifies
a loadable `zfs` module exists for every kernel installed into the target,
aborting the install with archzfs-support guidance if any kernel lacks one.
Turns the otherwise opaque mid-`mkinitcpio` "module not found" failure into an
early, explicit error naming the unsupported kernel. Necessary because Kernel
Selection may include kernels newer than `archzfs` tracks (see
archzfs-Compatible ISO).

### Stray Kernel
A kernel installed on a host but **not** in its Kernel Selection — e.g. a
rolling `linux` pulled in out-of-band on an lts-only host. Boot-harmless under
the hardened path: the ESP Kernel Sync mirrors only entry-referenced kernels, so
a stray never reaches the ESP, systemd-boot entries name only the Primary
Kernel, and under GRUB `GRUB_TOP_LEVEL` pins the Primary Kernel as default so a
higher-sorting stray cannot auto-boot. It still wastes ZFS `/boot` space and,
lacking a buildable `zfs.ko`,
would be a trap if booted. Surfaced — warned, never removed — by a non-blocking
PostTransaction hook (`97-stray-kernel-warn.hook`) that reuses the ZFS Module
Guard's `zfs.ko`-presence check (ADR 0038).

### Impermanence
Optional install-time feature that resets selected system directories to a clean
state on every boot via ZFS dataset rollback. Enabled by `options.impermanence`
in the Host Profile. When enabled, the installer creates a Persist Dataset,
splits a set of Rollback Datasets out of the OS pool, takes a Blank Snapshot of
each, and installs a Rollback Hook in initramfs. Inspired by NixOS impermanence;
deliberately narrower in scope — Arch lacks a `/nix/store`-equivalent, so
rolling back all of `/` would erase every pacman update, hence Impermanence
targets `/etc`, `/root`, `/opt`, `/srv`, `/usr/local` only.

### Persist Dataset
ZFS dataset (default `rpool/persist`, mounted at `/persist`) that holds all
state surviving across reboots when Impermanence is enabled. Name and mountpoint
configurable via `options.impermanence.dataset` and `options.impermanence.mount`
in the Host Profile. Must live on the same pool as `rpool/ROOT/arch` so the
early-boot bind-mounts complete before `local-fs.target`. Holds the Persist
Payload (operator-editable `.mount` units + tmpfiles snippets) plus the actual
data of every persisted path.

### Rollback Datasets
The set of ZFS datasets reverted to their Blank Snapshot on every boot when
Impermanence is enabled: `rpool/ROOT/etc` (`/etc`), `rpool/ROOT/root` (`/root`),
`rpool/ROOT/opt` (`/opt`), `rpool/ROOT/srv` (`/srv`), `rpool/ROOT/usrlocal`
(`/usr/local`). Deliberately excludes `rpool/ROOT/arch` (so pacman writes to
`/usr` survive reboots without re-snapshot), `rpool/home`, `rpool/var`,
`rpool/var/log`, `rpool/var/cache`, `rpool/tmp` (already separate datasets,
naturally persistent except `/tmp` which is intended ephemeral). Created by the
installer when Impermanence is enabled; absent otherwise.

### Blank Snapshot
ZFS snapshot named `@blank` on each Rollback Dataset, taken at the end of the
chroot phase after Curated Persist Defaults have been moved off the dataset onto
the Persist Dataset. The Rollback Hook reverts each Rollback Dataset to its
Blank Snapshot at every boot. Re-created by the Pacman Resnapshot Hook after
every successful pacman transaction so that pacman's writes to `/etc/<pkg>/`
etc. survive across reboots. If `@blank` is missing on any Rollback Dataset, the
Rollback Hook drops to emergency shell — fail-closed.

### Rollback Hook
mkinitcpio hook pair installed under `/etc/initcpio/hooks/` and
`/etc/initcpio/install/` and added to `HOOKS=` in `mkinitcpio.conf` between the
`zfs` and `filesystems` hooks. Runs in initramfs after the ZFS module loads and
pool is imported (and decrypted, if `options.encryption=true`), and before
`zfs-mount-generator` mounts the Rollback Datasets. Hardcoded at install time
with the list of Rollback Datasets to revert. Fails closed if any Blank Snapshot
is missing — drops to emergency shell rather than continuing with stale state.

### Bootstrap Mount
Pair of files baked into `/usr/lib` at install time that bridge the Persist
Dataset into systemd's standard discovery paths.
`/usr/lib/tmpfiles.d/impermanence-bootstrap.conf` creates `/etc/systemd/system/`
and `/etc/tmpfiles.d/` as empty directories at early boot.
`/usr/lib/systemd/system/persist-etc-systemd-system.mount` and
`persist-etc-tmpfiles-d.mount` bind `/persist/etc/systemd/system` and
`/persist/etc/tmpfiles.d` over those placeholders. Lives on `rpool/ROOT/arch`
(non-rolled-back) so it persists across reboots without snapshot manipulation.

### Persist Mount
`.mount` unit named `persist-<slug>.mount`, one per persisted path. Each unit
bind-mounts `/persist/<path>` over `<path>` early in boot. Ordered
`After=systemd-tmpfiles-setup.service` and `Before=local-fs.target` with
`RequiredBy=local-fs.target` so a failed bind cascades to emergency. Curated
Persist Defaults ship as units under `/usr/lib/systemd/system/` (vendor-owned,
snapshot-immune); host-declared Persist Extensions ship as units under
`/persist/etc/systemd/system/` (operator-editable). Live data is staged onto the
Persist Dataset before the unit activates — moved at install time (the live path
will be reset on next boot), copied at runtime (the bind mount activates
immediately and covers the original).

### Curated Persist Defaults
Fixed list of system-identity paths the installer always persists when
Impermanence is enabled. Files: `/etc/machine-id`, `/etc/hostname`,
`/etc/locale.conf`, `/etc/vconsole.conf`, `/etc/adjtime`, `/etc/fstab`.
Directories: `/etc/ssh`, `/etc/secrets`, `/etc/cryptsetup-keys.d`
(data-group LUKS/zfs keyfiles, ADR 0043),
`/etc/NetworkManager/system-connections`, `/etc/sudoers.d`, `/etc/pacman.d`,
`/root`. Loss of any of these breaks first reboot — host keys, Machine Age Key,
hostname, network connections, fstab. Shipped as Persist Mount units under
`/usr/lib/systemd/system/` so they're stable across operator edits.

### Persist Extensions
`persist` object in a Host Profile or Host Core with two arrays: `directories`
and `files`. Each entry is an absolute path. Deep-merged across Host Core and
the specific Host Profile per the standard merge rules. Translated by the
installer into Persist Mount units under `/persist/etc/systemd/system/` and
tmpfiles entries placed under `/persist/etc/tmpfiles.d/`. Only meaningful when
`options.impermanence.enabled=true`. Validation warns on paths already covered
by an always-persistent dataset (`/home`, `/var`, `/var/log`, `/var/cache`,
`/tmp`) or by a Curated Persist Default.

### Pacman Resnapshot Hook
Pacman post-transaction hook at
`/etc/pacman.d/hooks/zz-impermanence-resnapshot.hook` (or shipped under
`/usr/share/libalpm/hooks/`) that destroys and re-takes the Blank Snapshot on
every Rollback Dataset after a successful pacman transaction. Necessary because
pacman writes config defaults under `/etc/<pkg>/` etc.; without this hook those
writes would vanish on next reboot. Known v1 limitation: user edits to
non-persisted paths under a Rollback Dataset made *before* a pacman transaction
get baked into the new Blank Snapshot and survive one additional reboot. A
future opt-in pre-transaction drift check (`zfs diff` fails loudly if dirty)
closes this leak.

### Impermanence Tool
`.installer/tools/impermanence.sh`. Runtime utility for managing Persist
Extensions on
a system where Impermanence is enabled. Verbs: `add <path>` (writes the path
into the host's `persist.directories` or `persist.files` in
`hosts/<hostname>/profile.jsonc`, copies current data onto the Persist Dataset,
generates the Persist Mount, daemon-reloads); `remove <path>` (reverses);
`status` (lists active Persist Mounts and runs `zfs diff` against `@blank` for
each Rollback Dataset); `apply-defaults` (regenerates Curated Persist Defaults'
unit files under `/usr/lib/systemd/system/` from the installer's current curated
list, used after pulling an updated dotfiles repo). Does not edit Curated
Persist Defaults directly — those are vendor-shipped.

### Stow Tree
Top-level dotfile dirs in the repo (`.config/`, `.zsh/`, `.claude/`, plus loose
home-relative files like `.zshrc`, `.p10k.zsh`) that GNU stow symlinks into each
user's `$HOME` via `stow --no-folding */` during the Runner's dotfiles step.
Layout groups files by destination path, not by program. Legacy as of ADR 0012 —
being migrated program-by-program into Program Config Trees, but remains
supported indefinitely. Path collisions with the Generated Stow Tree abort the
Config Generator.

### Program Config Tree
Per-program user-side config files under
`.installer/programs/<category>/<name>/configs/`. The unsuffixed `configs/` is
the
default; sibling `configs@<variant>/` directories hold alternates (Config
Variants). Optional — programs without user-side config omit the dir entirely.
Manifest scope is user paths only; system paths stay in the program's
`install.sh`. Authoring location only — never directly symlinked or copied; the
Config Generator materializes the Generated Stow Tree from these.

### Config Variant
An alternate version of a program's Program Config Tree, named by the suffix on
`configs@<variant>/`. Variant names match `[a-z0-9-]+`; `default` is reserved
and refers to the unsuffixed `configs/`. Selected per-user via a `variants`
object in a User Profile (with House Defaults inheritable from User Core,
overridden per-key by the User Profile). Unselected variants fall back to
`configs/`; programs with only `configs@*/` and no `configs/` require an
explicit selection or the generator aborts.

### Config Manifest
`manifest.jsonc` inside each `configs[@variant]/` directory. Declares file
placement only — `files` is an array of `{ src, dst, mode? }` entries. `src` is
relative to the manifest's directory; `dst` is a `~/`-rooted user path. No
templating, no conditionals, no hooks, no system paths, no encrypted entries.
Constraints exist so that complexity is forced into the Config Variant axis
instead of into per-file metadata.

### Generated Stow Tree
Per-user materialized tree at `~/.dotfiles/.stow/<user>/` produced by the Config
Generator on the target machine. Mirrors destination paths (`.config/<...>`,
`.local/<...>`, home-relative files at root). Gitignored — never committed,
always regenerable from the repo + User Profile + Config Variants. Consumed by
`stow -d ~/.dotfiles/.stow/<user> --no-folding .`, which runs after the legacy
Stow Tree pass.

### Config Generator
`.installer/tools/generate-configs.sh`. Reads the merged User Core + User
Profile for a
target user and the merged Host Core + Host Profile for the machine (hostname
looked up at runtime). Resolves each program's Config Variant via the Variant
Resolver, validates all relevant Config Manifests, builds a per-user plan via
the Plan Builder, and materializes the Generated Stow Tree. Invoked by the
Runner inside `arch-chroot` per user between the dotfiles clone and the stow
invocation. Also runnable standalone after install (`--user <name>`) to
re-render after variant edits. Flags `--validate-only` and `--dry-run` are
supported. Aborts if a planned destination is already owned by the legacy Stow
Tree.

### Plan Builder
Pure function inside the Config Generator. Inputs: the resolved Config Variant
map, the per-user `~/.dotfiles/.stow/<user>/` stow root, and the declared
program set (User Programs from User Core + User Profile, unioned with Host
Programs from Host Core + Host Profile). Output: a deterministically-ordered
flat list of `{ src_abs, dst_in_stow_tree, mode? }` entries. No writes. Programs
with a Program Config Tree on disk but not in the declared set are silently
omitted — mid-migration is a normal state.

### House Defaults
Variants declared in User Core's `variants` object, applied to every user unless
overridden per-key in their own User Profile. Same merge semantics as the rest
of the User Core / User Profile relationship — core first, user adds on top,
individual keys can be replaced without replacing the whole object.

### VM Profile
A JSON file describing one virtual machine to provision for install testing or
dev use, consumed by the VM Harness — never installed onto real hardware
(distinct from a Host Profile). Carries a `hardware` block (disk sizes, RAM,
vCPUs) and names the machine's install source via exactly one of two top-level
keys (`host_profile` xor `install`): a `host_profile` reference names a real
host directory, resolved through the unified Profile Loader — the picker
assembles its Effective Config against the VM's virtual disks, keeping one
source of truth; or an `install` block, either an inline Effective Config (a
full assembled config, for test-only permutations with no real Host Profile) or
the string `"repo"`, meaning the repo's designated default Host Profile named by
the single harness constant `VM_DEFAULT_HOST_PROFILE` (default `arch-kde`),
hostname patched — the smoke test that the shipped default installs (ADR 0036,
amending ADR 0035). Profiles for persistent/usable VMs live under
`.installer/vm/profiles/<category>/`; test profiles live under
`.installer/tests/vm/profiles/<category>/` and additionally carry verification
expectations (pools, mounts, owners, boot checks). Grouped into Profile
Categories (subdirectories).

### VM Harness
`.installer/vm/vm.sh`. The single profile-driven entry point that provisions a
libvirt
VM from a VM Profile and runs `install.sh --unattended` inside it. Default flow
builds a persistent, reusable VM (spice graphics, reboots into the installed
system for interactive use via virt-manager). `--testing` selects the disposable
test flow (headless, serial-console capture, sentinel watcher, installer
exit-code propagation, opt-in boot-verify). Validates the profile up front
(schema, exactly one install source, and that any referenced `host_profile`
names a real host directory) before doing any work, mirroring the repo's
fail-fast config validation. Shared host-side core (dependency checks, ISO
resolution, Effective Config assembly, libvirt domain create/boot) and the two
divergent flows live in `vm/lib/`. A test profile run **without** `--testing`
yields a persistent VM of that exact config — the supported way to interactively
debug a failing test case.

### Console Answerer
The Combination-Matrix harness component that makes encrypted cells
boot-verify headlessly instead of stopping at install. It watches the serial
log (the same one the sentinel watcher tails — the test-only `console=ttyS0`
cmdline injection already routes emergency/passphrase prompts there) for a
disk-unlock prompt, matches it against the known prompt patterns (mkinitcpio
`encrypt` hook, `systemd-cryptsetup`, zfs-native `load-key`), and writes the
known test passphrase **to the serial char device** — not via `virsh
send-key`, because with `console=ttyS0` the prompt reads from `/dev/console`,
not the emulated keyboard. Bounded retries fail into `ENCRYPTED-BOOT-FAIL`
rather than a hang. Drives the real passphrase-unlock path (ADR 0046), so an
encrypted cell verifies as close to reality as a human at the prompt.

### Profile Category
The subdirectory grouping VM Profiles within a `profiles/` tree. The axis
differs per tree: persistent profiles (`.installer/vm/profiles/`) are
categorized by
desktop/use (`desktop/`, `headless/`); test profiles
(`.installer/tests/vm/profiles/`)
are categorized by the install path they exercise (`single/`, `multi/`,
`data-pools/`, `impermanence/`, `env/`, `boot/`, `headless/`). Each profile
lives in exactly one
category; when a feature category fits (e.g. `impermanence/`, `env/`) it wins
over the bare layout-mode category.

### Combination Matrix
The generated space of menu-reachable install combinations under test, so that
"no error for any menu choice" is a checked property rather than a hope. A cell
is one axis assignment (root filesystem, encryption, impermanence, topology,
disk-mode, per-group data-pool filesystem/encryption, kernel, bootloader,
desktop, gpu, swap). Cells, their allowed values, and the exclusions between
them are **derived from the menu's own option functions** (`_ctl_topologies_
for_fs`, `menu_rows`, picker/validation), never a hand-kept duplicate, so an
unreachable combination is one the menu never emits (ADR 0046). Covered in two
tiers: **Tier 1** assembles + `validate_install_context`-checks the *exhaustive*
storage cluster with no VM (always-on in bats); **Tier 2** installs a
**pairwise** (2-wise) subset plus a pinned seed list of historically-broken
tuples through a real VM (`vm.sh --testing`), reusing Tier 1's assembler to feed
the Effective Config via the config seam. The covered set is recorded as a
committed **Matrix Manifest** (one line per cell); VM Profiles are materialized
on demand, never committed.

### Optional Repositories
`options.optional_repos[]` in a Host Profile — the pacman repos enabled beyond
`core`/`extra`: any of `multilib`, `multilib-testing`, `core-testing`,
`extra-testing` (ADR 0072). Replaces the former `options.multilib` bool: the
same choice plus the testing repos as one multi-select. Defaults to
`["multilib"]` (the historical `multilib=true`); an explicit `[]` means no
optional repos. Applied before pacstrap by `enable_optional_repos`, which
uncomments the shipped `#[repo]` + `#Include` in the host `/etc/pacman.conf` in
place (preserving Arch's testing-above-stable ordering), inherited by the target
via the pacman.conf copy. `install_config_multilib` remains a back-compat shim
("true" iff `multilib` is in the set).

### Custom Servers & Repositories
Two operator-authored Mirrors & Repositories extras (ADR 0072).
`options.mirror_servers[]` is a list of custom pacman `Server =` URLs, written
**above** the reflector-ranked mirrorlist (after `reflector --save`) so they are
tried first. `options.custom_repositories[]` is a list of archinstall-style extra
repos, each `{name, url, sign_check, sign_option}` — `sign_check` ∈
`Never`/`Optional`/`Required`, `sign_option` ∈ `TrustAll`/`TrustedOnly`,
combined into the pacman `SigLevel` — appended as `[name]` blocks to
`/etc/pacman.conf` before pacstrap. Both are surfaced in the Guided Installer as
list screens (a listing plus a `＋ Add …` action).

### Pacman Options
The `options.pacman.*` object in a Host Profile — the pacman `[options]` block
flags surfaced as a dedicated **Pacman** Configuration Category, sitting right
after Mirrors & Repositories (both edit `pacman.conf`). Five bool toggles
(`ilovecandy`, `color`, `verbose_pkg_lists` default on; `disable_download_timeout`,
`no_progress_bar` default off) plus one int (`parallel_downloads`, default `5`),
listed as toggle/text rows like every other section (ADR 0074). Applied
**authoritatively** before pacstrap — each managed flag is uncommented/written
when on and commented out when off, so the host `/etc/pacman.conf` always
reflects the toggles regardless of what the ISO shipped; the target inherits it
via the pacman.conf copy. Deliberately excludes `CheckSpace` (the ZFS path
force-disables it via `disable_checkspace`) and `multilib` (owned by Optional
Repositories). Untouched lines (`SigLevel`, includes) are left intact.

### Locales Category
The Guided Installer Configuration Category for a machine's localization: four
leaves — `keyboard`, `language`, `encoding`, `console font`. `language` and
`encoding` are **projections** of one canonical locale string (`en_US.UTF-8`):
language is the base before the charset suffix, encoding is the suffix, and
editing either recomposes the single string exactly once — so an encoding can
never be doubled onto the locale. `encoding` offers only charsets valid for the
chosen `language`. `console font` sets the virtual-console font. Its option
lists are enumerated live from the installer medium, never hardcoded. Timezone
is deliberately excluded — it is a clock setting, not localization, and lives in
the **General** Category (ADR 0076).

### General Category
The Guided Installer Configuration Category holding a machine's hostname,
timezone, and the [[Font Catalog]] (`options.fonts`); the former **System**,
renamed once its localization fields moved to the **Locales Category** (ADR
0076). Was recut to machine *identity* by ADR 0076, then **re-broadened** to
"identity + fonts" by ADR 0080 — the operator's deliberate choice to house the
font multi-select here rather than spend a top-level category or a Packages
leaf on it. Fonts are the one non-identity resident; service-enablement
switches (Bluetooth, Power, Printing) still keep their own categories, so
General never became a catch-all.
_Avoid_: System.

## Flagged ambiguities

- "base packages" vs "core packages" — **re-resolved (ADR 0056)**: there are now
  two shared bases and they are different layers, not competitors. The **Base
  Package List** (the pure `lib/packages/base.sh:base_packages` map) is what the
  *installer* needs on any host it builds. **Host Core**'s `packages` object is
  what this *fleet* wants on every real machine. ADR 0007's rule that Host Core carries no
  package list is **superseded**: its "the lists are machine-specific" premise
  failed against the actual fleet (`laptop` is a strict subset of `desktop`).
  A VM fixture takes the first and opts out of the second via
  `packages.inherit: false`. The ADR 0021 clause placing `extra-cmake-modules`
  in Host Core is withdrawn (see ADR 0021 amendment); ECM is dropped entirely
  since paru resolves makedepends at build time.
- DE packages in host configs — resolved: every package derivable from
  `environment.desktop` belongs to its **Desktop Environment Adapter**, not a
  Host Profile (ADR 0021). KDE, Hyprland, and niri are the adapters (Hyprland
  re-added ADR 0062 superseding the ADR 0050 removal; niri added ADR 0090).
- `host_profile` now lives at one layer only (ADR 0036): it is a **VM Profile**
  key naming a real host directory, which the unified Profile Loader resolves to
  that machine's **Host Profile** (the picker assembles the **Effective Config**
  against the VM's virtual disks). The former install-config `host_profile`
  *field* is gone — a machine's identity is its profile directory name, i.e. the
  `install.sh --profile <name>` argument.
