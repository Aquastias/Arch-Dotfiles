# Guided Installer — in-menu credentials, hybrid GPU, latency, casing

Status: done — all 5 issues implemented + committed on main; full 1909-test suite green. Live masked prompt + felt latency remain HITL/VM on the Legion.

Decision of record: builds on **ADR 0042** (Guided Installer renders through
one persistent fzf) and **supersedes** its "passwords are collected post-menu
at Proceed" choice — credentials now enter inside the menu. Also touches ADR
0039 (Guided Installer front-end), 0041 (host Extras via Primary User paru),
0036 (Effective Config). A new ADR records the in-menu credential decision.

Glossary: Guided Installer, Configuration Categories, Config State, Effective
Config, Primary User, Host Core, Security & Backup Extras. New term proposed:
**Display Label** (the human-facing name of a menu item, distinct from its
stored Config State value).

Context: reported against a Legion 5 laptop with a hybrid GPU (AMD iGPU +
NVIDIA dGPU). The GPU back-end is already hybrid-aware; the gaps are all in
the Guided Installer front-end.

## Problem Statement

When the operator finishes configuring in the Guided Installer menu and
selects Proceed, the installer drops out of the menu to a bare terminal and
asks for the root and user passwords there. It feels like the installer left
the menu to finish the job elsewhere — the operator expects to set passwords
inside the menu, the way archinstall does.

Three further annoyances on the same machine:

- The GPU option is single-select (amd / nvidia / intel / auto), so a hybrid
  AMD+NVIDIA laptop cannot pick both vendors from the menu, even though the
  back-end already supports a vendor list and writes the correct PRIME
  session env for the hybrid case.
- Switching between menus feels laggy: every navigation blocks on work before
  the next screen paints.
- Casing across menu items is inconsistent — some items are capitalized,
  others lower-case — which reads as unpolished.

## Solution

Bring credential entry, GPU selection, and casing fully inside the single
persistent-fzf menu, and cut the per-navigation work so screen switches feel
immediate.

- **In-menu credentials.** The Users screen grows a `root password` row and,
  under each enabled user, an indented `password` row. Selecting one opens a
  hidden (masked, confirmed) prompt and returns to the menu. State shows as
  `(set)` / `(not set)`, never the value. Proceed is blocked from inside the
  menu until root and every enabled user have a password; the old post-menu
  prompt is removed entirely.
- **Hybrid GPU.** The gpu field becomes a multi-select toggle. `auto` is
  mutually exclusive with explicit vendors; the default stays `auto`.
  Selecting `amd`+`nvidia` flows through the existing back-end (both driver
  sets, envycontrol, the AQ_DRM_DEVICES PRIME env). No back-end change.
- **Latency.** Navigation dispatch computes the next screen's list once,
  writes it to a file, and asks fzf to `reload(cat …)` instead of spawning a
  second bash that re-sources the controller. The per-render jq fan-out in
  the list builder is collapsed into far fewer invocations.
- **Casing.** A single display-only formatter renders every menu item —
  labels, pick-screen values, inline values, and the pre-install review —
  through a curated acronym map with a first-letter-uppercase fallback and a
  passthrough for technical / free-text tokens.

## User Stories

1. As an operator, I want to set the root password inside the Users screen,
   so that I never leave the menu to finish configuring.
2. As an operator, I want to set each enabled user's password on an indented
   row under that user, so that credentials live next to the account.
3. As an operator, I want the password prompt to be masked and confirmed, so
   that no one can read my password off the screen and typos are caught.
4. As an operator, I want each password row to show only `(set)` or
   `(not set)`, so that the value never appears on screen.
5. As an operator, I want Proceed to refuse and tell me which passwords are
   missing while keeping me in the menu, so that I fix them without a jarring
   drop-out.
6. As an operator, I want the installer to never ask for passwords after I
   press Proceed, so that the flow ends where I configured it.
7. As a security-conscious operator, I want my typed passwords to stay out of
   any saved profile or exported config, so that Save/Export never write a
   plaintext secret.
8. As an operator who saves a profile without installing, I want Save/Export
   to work without me setting passwords, so that authoring a reusable profile
   is not gated on secrets.
9. As a returning operator, I want replay (scripted answers) to keep
   supplying passwords the way it does today, so that automated runs are
   unaffected.
10. As a Legion 5 owner, I want to select both AMD and NVIDIA in the gpu
    option, so that my hybrid laptop gets both driver stacks.
11. As an operator, I want `auto` to clear when I pick a vendor (and vice
    versa), so that I never end up with a contradictory gpu selection.
12. As an operator who does nothing to the gpu option, I want `auto` to
    remain the default and detect my hardware (including hybrid), so that the
    common case needs no thought.
13. As a hybrid-laptop operator, I want the PRIME session env written
    automatically when I pick amd+nvidia, so that my compositor renders on the
    integrated GPU without manual fixes.
14. As an operator, I want switching between menus to feel immediate, so that
    configuring does not feel sluggish.
15. As a maintainer, I want the latency change to leave the rendered rows
    identical, so that behavior is unchanged and only speed improves.
16. As an operator, I want menu items cased consistently, so that the
    installer reads as one polished program.
17. As an operator, I want acronyms shown correctly (KDE, NVIDIA, ZFS, SSH,
    LTS, ESP), so that technical names look right rather than "Kde"/"Ssh".
18. As an operator, I want technical and free-text tokens (`/dev/sda`,
    `en_US.UTF-8`, `key=value`, my hostname) left exactly as they are, so
    that formatting never corrupts an identifier.
19. As an operator, I want the pre-install review screen cased the same way as
    the menu, so that what I confirm matches what I picked.
20. As a maintainer, I want unknown/new option tokens to fall back to plain
    first-letter-uppercase, so that adding an option never requires touching
    the casing table.

## Implementation Decisions

**Credential Entry (new deep module).**
- Passwords are captured inside the menu via the existing fzf `execute()`
  drop-out to a subprocess running the shared masked prompt (read-twice,
  confirmed, non-empty; no minimum length — unchanged from today).
- The subprocess cannot write the parent shell's variables, so the captured
  secret is handed back through a dedicated tmpfs file (`GUIDED_SECRETS_FILE`,
  created by the persistent-fzf launcher via mktemp, cleaned by the same
  RETURN trap as the other GUIDED_*_FILE files). Shape:
  `{ root_password?: str, users?: { <name>: { password: str } } }`.
- This file is never referenced by config emit, Save, or Export, so the
  Config State stays secret-free (the invariant ADR 0042 established). The
  parent reads it at Proceed to build the existing no-SOPS password manifest;
  `.secrets.*` remains untouched (guided stays no-SOPS).
- Display is `(set)` / `(not set)`, derived from the file, never the value.
- The Proceed gate: a completeness predicate over the effective users +
  secrets file returns the missing set (root, and every enabled user). The
  gate is evaluated inside fzf on the Proceed key via a `transform` bind: if
  incomplete, emit a header/notice update + bell and do NOT accept; if
  complete, write the terminal action and accept. Save/Export are not gated.
- The post-menu collection path is removed. Replay continues to inject
  passwords via keyed answers (interactive-only change).

**GPU normalize (new small pure module).**
- The gpu field changes from single-select enum to multi-select toggle over
  `amd nvidia intel auto`; default stays `auto`.
- A pure normalizer enforces exclusivity: toggling a vendor on clears `auto`;
  toggling `auto` on clears all vendors. Stored value is a lower-case array
  (e.g. `["amd","nvidia"]`) — the shape the back-end already consumes.
- No back-end change: resolution, driver-package mapping, envycontrol, and
  the AQ_DRM_DEVICES PRIME env already key off the vendor list. Both guided
  front-ends (persistent controller + replay editor) use the same normalizer.

**Display formatter (new deep pure module).**
- One function maps a raw token to its Display Label: a curated table for
  acronyms/proper names, else sentence-case with any acronym word upper-cased,
  else first-letter-uppercase fallback; technical/free-text tokens
  (containing `/`, `=`, `:`, `.`, whitespace-path, leading non-alpha, or a
  device/by-id path) pass through unchanged. Proposed curated set:
  `KDE GPU SSH ZFS UFW LTS URL ESP AMD NVIDIA` plus literal `systemd-boot` and
  the filesystem labels `Ext4`/`Xfs`/`Btrfs` (approved in the grilling
  preview; `ext4` also needs a curated entry to beat the digit-passthrough);
  `Intel`/`Auto`/`Hyprland`/`Zen` take normal case.
- Applied at the render boundary to row labels, pick-screen option values,
  inline current values, and the pre-install review summary — display only,
  never mutating stored values.
- The reverse label→path lookup used to dispatch a selected row becomes
  format-aware (format each candidate label and compare), so Enter still
  resolves the correct field after labels are re-cased.

**Render fast-path (modify).**
- Navigation dispatch (enter/back) computes the next screen's list once,
  writes it to a file, and returns `reload(cat <file>)` instead of
  `reload(bash entry list)`, removing the second bash+source fork per nav.
- The list builder's jq fan-out is collapsed into far fewer jq invocations.
- Rendered rows must be byte-identical before/after (behavior-preserving).

## Testing Decisions

Good tests assert externally observable behavior, not implementation detail:
the JSON/manifest shapes, the normalized arrays, the formatted strings, and
the emitted row lists — not internal function calls. Prior art:
`tests/config/guided-*.bats` (controller logic), the matrix axis/registry
bats, and the existing config emit/round-trip tests.

- **Credential Entry logic** — bats over the tmpfs manifest read/write shape,
  the Proceed completeness predicate (missing vs complete for root + each
  enabled user), and an assertion that emit/Save/Export never surface the
  secret. The masked tty prompt itself is HITL/VM (needs a tty).
- **GPU normalize** — bats over auto-exclusivity: `auto`+toggle vendor →
  `[vendor]`; toggle `auto` → `[auto]`; `amd`+`nvidia` → `[amd,nvidia]`.
- **Display formatter** — bats over curated hits (kde→KDE, esp size→ESP
  size, ssh→SSH), fallback (unknown→First-letter), technical passthrough
  (`/dev/sda`, `en_US.UTF-8`, `key=value` unchanged), and format-aware
  reverse lookup (GPU→environment.gpu).
- **Render output-equivalence** — bats asserting `guided_ctl_list` emits
  identical rows per screen after the fast-path/jq refactor.

Glue that bats cannot reach — the live masked prompt, the fzf binds, the
actual felt latency — is verified at the HITL/VM gate on the Legion, per repo
norm (serve local main via git daemon; no push from the agent env).

## Out of Scope

- Any change to the password back-end (chroot password step, secrets
  resolver): passwords remain plaintext-shaped, no hashing in the menu.
- SOPS/`.secrets.*` activation — guided stays strictly no-SOPS.
- A persistent warm-server fzf architecture: only the in-architecture
  latency fixes are in scope; escalation is a separate future decision, taken
  from on-device measurement.
- New GPU vendors or GPU tuning beyond exposing the existing vendor list as a
  multi-select.
- Password strength policy beyond the current non-empty + confirm.
- Retro-casing of committed profile/config files on disk — display only.

## Further Notes

- The back-end is already hybrid-ready: `_resolve_env_gpu` maps each vendor to
  driver packages, adds envycontrol for amd+nvidia, and `gpu_is_nvidia_hybrid`
  writes the AQ_DRM_DEVICES PRIME env. This PRD only unlocks the selection in
  the menu.
- Documentation follows the code (per the reporter): one ADR superseding the
  post-menu-password portion of ADR 0042, a CONTEXT.md glossary entry for
  Display Label, and updates to the guided-installer memory notes.
- VM/HITL runs serve local main via git daemon with a REPO_URL override; the
  agent environment cannot push (ssh is hard-denied), so the user pushes.
