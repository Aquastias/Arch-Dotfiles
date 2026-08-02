# Spec: Re-add Hyprland as an installer desktop option

Status: done (847efdf)

Relevant ADRs: 0062 (re-add Hyprland adapter), 0061 (impermanence uses a real
display manager), 0060 (forbid impermanence on hybrid GPU), 0005 (DE adapter
pattern), 0021 (adapter owns DE packages), 0050 (superseded — original removal),
0053 (hybrid GPU hardening / `gpu` install-state seam).

## Problem Statement

The installer only offers KDE. The operator wants Hyprland back as a selectable
desktop — usable on its own or alongside KDE — including on the hybrid
AMD+NVIDIA laptop that is the main machine Hyprland is wanted on. When Hyprland
was last shipped it black-screened on that laptop; the operator has since
established that the black screen was caused by impermanence on hybrid hardware,
not by Hyprland or by the display manager, so a straight restore would repeat a
misdiagnosis rather than fix the real constraint.

## Solution

Hyprland returns as a Desktop Environment Adapter selectable via
`environment.desktop`, on any host, independent of impermanence. The display
manager follows the pre-removal rule: SDDM when KDE is co-installed, greetd +
greetd-tuigreet when Hyprland is the only desktop. On every host — including
impermanence hosts — the operator reaches a real login screen, selects their
user, and enters a password; there is no autologin. The known-bad combination
(impermanence on a hybrid AMD+NVIDIA GPU) is refused at validation with a clear
error, so the black screen can no longer be assembled. Hyprland's two
hardware-specific footguns are handled inside its adapter: the `start-hyprland`
supervisor crash (via a direct-launch session override) and aquamarine grabbing
the wrong DRM node on hybrid GPUs (via DRM device pinning gated on the hybrid
set). The adapter installs only the minimum working-session core; the operator
brings bars, launchers, terminals, and theming via their own dotfiles.

## User Stories

1. As an operator, I want `hyprland` to be a valid `environment.desktop` value,
   so that I can install Hyprland from a Host Profile.
2. As an operator using the Guided Installer, I want Hyprland offered in the
   Environment desktop selection list, so that I can pick it without editing a
   profile.
3. As an operator, I want to select both KDE and Hyprland, so that I can switch
   between a Plasma session and a Hyprland session on one machine.
4. As an operator, I want to select only Hyprland, so that I get a lean Wayland
   compositor with no Plasma.
5. As an operator installing KDE alongside Hyprland, I want SDDM as the display
   manager, so that I get a graphical greeter that offers both sessions.
6. As an operator installing only Hyprland, I want greetd + greetd-tuigreet as
   the display manager, so that I get a login screen that launches Hyprland.
7. As an operator, I want to arrive at a login screen on every boot on every
   host, so that I select my user and type a password rather than being
   auto-logged-in.
8. As an operator on an impermanence host, I want a real display-manager login
   that survives the rolled-back root, so that impermanence does not force a
   tty1 autologin.
9. As an operator on the hybrid AMD+NVIDIA laptop, I want to run Hyprland with
   the compositor pinned to the integrated GPU, so that aquamarine does not grab
   the NVIDIA node and black-screen.
10. As an operator, I want enabling impermanence on a hybrid AMD+NVIDIA GPU to
    fail with a clear error, so that I never assemble the black-screen
    combination by accident.
11. As an operator, I want the impermanence+hybrid check to apply regardless of
    which desktop I chose, so that the guardrail is about hardware, not desktop.
12. As an operator with `gpu: "auto"`, I want the impermanence+hybrid check to
    fire on the hardware actually detected at install time, so that a portable
    profile is still protected.
13. As an operator selecting KDE+Hyprland, I want the Hyprland session launched
    directly rather than through `start-hyprland`, so that the SDDM session does
    not crash back to the greeter.
14. As an operator, I want the direct-launch session override to win over the
    packaged one and survive Hyprland upgrades, so that the fix is durable.
15. As an operator, I want the Hyprland adapter to install only the
    working-session core (compositor, both portals, polkit agent, Wayland
    clipboard), so that I am not handed a bar/launcher/terminal I will not use.
16. As an operator, I want no companion applications and no `qt6ct-kde`
    installed by the Hyprland adapter, so that my dotfiles own appearance and
    tooling.
17. As an operator, I want Qt theming under Hyprland to remain my
    responsibility, so that it does not clash with Plasma's own Qt platform
    theme in a combined install.
18. As an operator, I want the display-manager choice to depend only on the
    resolved desktop set (not a config key), so that the behavior is predictable
    and there is nothing extra to configure.
19. As an operator, I want the DM rule to be independent of adapter execution
    order, so that KDE+Hyprland and Hyprland+KDE resolve to the same DM.
20. As a maintainer, I want Hyprland re-added as a directory-convention adapter
    with no changes to the Environment Runner, so that ADR 0005 still holds.
21. As a maintainer, I want the aquamarine DRM pinning to live in the Hyprland
    adapter rather than in DE-agnostic environment resolution, so that
    ADR 0050's placement smell is not reintroduced.
22. As a maintainer, I want the DRM pin to reach every session type (SDDM and
    tuigreet) via the standard login-environment path, so that it needs no
    per-DM special-casing.
23. As a maintainer, I want the Tier-2 install matrix to regain Hyprland cells
    automatically from the widened desktop enum, so that I do not hand-edit the
    matrix.
24. As a maintainer, I want `hyprland` to render as `Hyprland` in menus and
    summaries, so that the surface reads consistently with `KDE`.
25. As a maintainer, I want the glossary updated so that KDE is no longer
    described as the sole desktop and the display manager is again
    multi-valued.
26. As an operator, I want KDE-only installs to be completely unaffected, so
    that re-adding Hyprland introduces no regression to the default desktop.

## Implementation Decisions

- **Hyprland Desktop Environment Adapter restored.** A new
  `extras/desktop/hyprland/` adapter with its `install-<name>.jsonc` companion,
  invoked by the existing Environment Runner via directory convention — no
  Runner change (ADR 0005). `hyprland` is added to the valid desktop set so
  Environment validation accepts it.
- **Core-only package set.** The adapter installs exactly the working-session
  core: the compositor, `xdg-desktop-portal-hyprland`, `xdg-desktop-portal-gtk`,
  the polkit agent, and the Wayland clipboard bridge (ADR 0021's "minimum
  non-negotiable"). All former companion toggles (bar, launchers, terminal,
  lock/idle/wallpaper, screenshot, look tool) are dropped, and the `qt6ct-kde`
  AUR theming bridge is dropped — the adapter carries no `aur` field.
- **Display-manager rule (pre-removal behavior).** DM is auto-selected from the
  full resolved desktop set, not a config key: greetd + greetd-tuigreet
  (`tuigreet` launching Hyprland directly) when KDE is absent, SDDM when KDE is
  present. The KDE adapter is unchanged and always enables SDDM. The reverted
  `a5b429d` behavior (greetd owning the DM even alongside KDE) is deliberately
  not restored. The rule reads the full desktop set passed to each adapter, so
  it is independent of adapter execution order.
- **Direct-launch session override.** The adapter ships a wayland-session entry
  whose exec launches the compositor binary directly (not the `start-hyprland`
  supervisor), placed where it wins the display manager's session scan and
  survives package upgrades. This is what makes the SDDM (KDE+Hyprland) session
  reliable; the greetd path already launches the compositor directly.
- **Aquamarine DRM pinning, relocated into the adapter.** Re-derive the previous
  `AQ_DRM_DEVICES` mechanism — a udev rule minting a stable, colon-free
  integrated-GPU DRM symlink plus an `AQ_DRM_DEVICES` entry in the system login
  environment — but house it in the Hyprland adapter and gate it on the resolved
  `amd`+`nvidia` hybrid set, read from the `gpu` array already threaded into
  install-state (ADR 0053's seam). Because it lands in the system login
  environment, it reaches every session (SDDM and tuigreet) with no per-DM
  handling. On non-hybrid hardware nothing is written.
- **Impermanence forbids hybrid GPU (ADR 0060).** Impermanence validation gains
  a hard error when impermanence is enabled and the resolved GPU set contains
  both `amd` and `nvidia`, regardless of desktop. The check runs after GPU
  Resolution because `gpu: "auto"` only resolves to the vendor pair at install
  time.
- **Impermanence uses a real display manager (ADR 0061).** The impermanence
  tty1 autologin step is removed from the impermanence apply sequence, along
  with the stale reference to the removed greetd-swap. The existing enablement
  relocation (mirroring the DM enablement onto the never-rolled-back tree) and
  the graphical-session hardening (per-user linger, `XDG_RUNTIME_DIR` fallback,
  pre-greeter user-manager oneshot) are retained so the DM login survives the
  rolled-back root. No HITL verification gate.
- **Surface wiring.** The Guided Installer's Environment desktop options include
  `hyprland`; the Display Label formatter renders `hyprland` as `Hyprland`. The
  pairwise install matrix picks up Hyprland cells automatically from the widened
  desktop enum on regenerate — no hand-editing.
- **Glossary updates.** The Display Manager and Desktop Environment Adapter
  entries (and the note stating KDE is the only adapter) are corrected: KDE is
  no longer the sole desktop and DM selection is again multi-valued.
- **No host-profile default change.** Both shipped Host Profiles keep KDE as
  their desktop; Hyprland is opt-in via the Guided Installer or a profile edit.

## Testing Decisions

Good tests here assert **external behavior at the highest existing seam** — what
packages an adapter installs, which display-manager service it enables, which
files it writes, and whether validation accepts or rejects a config — never
internal function structure. Every seam already exists; the adapter-script-under-
stubs seam carries most of the feature.

- **Hyprland adapter** (`tests/extras/hyprland-adapter.bats`, restored as a
  sibling of the live `kde-adapter.bats`, which is the prior art). With stubbed
  `pacman`/`systemctl` and injectable `HYPR_JSON`, `GREETD_CONF_DIR`,
  `WAYLAND_SESSIONS_DIR`, `ROOT`, and a GPU input, assert: the 5-package core is
  installed; no companion packages and no `qt6ct-kde` are installed; greetd is
  installed and enabled when KDE is absent and skipped when KDE is present; the
  session override exec launches the compositor directly and never
  `start-hyprland`; the DRM udev rule and login-environment pin are written only
  when the GPU set is hybrid and absent otherwise.
- **Environment Runner** (`tests/extras/environment-runner.bats`, existing):
  dispatch to the Hyprland adapter by convention with no DE literal in the
  runner.
- **Environment resolution/validation** (`environment-resolution.bats`,
  `environment-validation.bats`, existing): `hyprland` resolves as a valid
  desktop; an unknown desktop still errors.
- **Impermanence validation** (`validation-impermanence.bats`, existing):
  impermanence + `amd`&`nvidia` errors; impermanence + a single vendor passes;
  the error is desktop-independent.
- **Impermanence apply** (`chroot-impermanence.bats`, existing): with `ROOT`
  redirected, SDDM remains enabled on a rolled-back root (no autologin
  disabling it) and the graphical-session hardening is still applied.
- **Surface** (`display-label.bats`, `menu-enum.bats`, existing): `hyprland`
  renders as `Hyprland`; the guided desktop enum offers `hyprland`.

## Out of Scope

- Shipping a Hyprland configuration, bar, launcher, terminal, lockscreen, or
  theming — the operator's dotfiles own these.
- Per-session `QT_QPA_PLATFORMTHEME` wiring for Qt theming under Hyprland vs
  Plasma — a dotfiles concern.
- Changing the default desktop of any shipped Host Profile.
- Any change to the KDE adapter's own packages or its unconditional SDDM enable.
- A human-in-the-loop hardware smoke-test gate (explicitly declined).
- Re-introducing any Hyprland companion-package toggles or a guided surface for
  them.
- Runtime GPU mode switching (envycontrol and similar) — out of scope per
  ADR 0053.

## Further Notes

- The original black screen was reproduced only on the hybrid laptop and was
  never observed on single-GPU impermanence; the "DM-initiated login is
  fundamentally broken under impermanence" conclusion in the removed autologin
  code was an over-generalization from that one machine (three escalating fixes
  in one afternoon, 2026-07-28). ADRs 0060 and 0061 record the corrected
  understanding.
- The `AQ_DRM_DEVICES` mechanism and the `start-hyprland` direct-launch override
  can both be recovered from git history (the pre-removal adapter at the commit
  before the removal, and the reverted `a5b429d` fix) rather than re-invented.
- greetd-tuigreet, greetd, and `AQ_DRM_DEVICES` re-enter the project's
  vocabulary, reversing part of ADR 0050's vocabulary cleanup.
