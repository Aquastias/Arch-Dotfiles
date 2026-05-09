# PRD: Environment Selection (Desktop, GPU, Audio)

Status: ready-for-agent
Category: enhancement

## Problem Statement

Today the installer has no structured way to configure the runtime environment of the installed system. Desktop environment support is limited to KDE via a boolean flag buried under `post_install.desktop.kde` in the Install Config, with no support for Hyprland. GPU drivers must be installed manually after first boot. Audio is never installed — the user must set up PipeWire themselves. There is no way to declare a desktop environment, GPU driver, or audio stack in the Install Config and have the installer handle everything automatically.

The result is that a user logs in to a system with no display manager, no audio, and no GPU acceleration — requiring manual post-install work that defeats the purpose of a declarative installer.

## Solution

Introduce an `"environment"` key in the Install Config that lets the user declare their desktop environment (KDE, Hyprland, or both) and GPU vendor (AMD, NVIDIA, Intel, hybrid, or auto-detect). Audio is auto-derived: PipeWire is installed whenever any desktop is selected, omitted for server installs. GPU packages are resolved at config-load time and injected into pacstrap. Desktop environments are installed inside the chroot via the Desktop Environment Adapter pattern — each DE is a self-contained directory; the Environment Runner dispatches dynamically with no hardcoded DE names. The user logs in to a fully configured graphical system on first boot.

## User Stories

1. As a sysadmin, I want to declare `"environment": { "desktop": "kde" }` in the Install Config, so that KDE Plasma is installed and SDDM is enabled without any manual post-install steps.
2. As a sysadmin, I want to declare `"environment": { "desktop": "hyprland" }`, so that Hyprland and its companion tools are installed with greetd and tuigreet as the display manager.
3. As a sysadmin, I want to declare `"environment": { "desktop": ["kde", "hyprland"] }`, so that both desktop environments are installed and selectable from SDDM on login.
4. As a sysadmin, I want to omit `"environment"` or set `"desktop": null`, so that a server install proceeds with no desktop, no display manager, and no audio stack.
5. As a sysadmin, I want to declare `"gpu": "amd"`, so that the correct AMD Vulkan and VA-API drivers are included in pacstrap without me knowing the package names.
6. As a sysadmin, I want to declare `"gpu": "nvidia"`, so that the open-source NVIDIA kernel module and userspace utilities are included in pacstrap.
7. As a sysadmin, I want to declare `"gpu": ["amd", "nvidia"]`, so that a hybrid laptop gets both driver sets plus `envycontrol` for GPU switching.
8. As a sysadmin, I want to declare `"gpu": "auto"`, so that the installer detects my GPU vendor from `lspci` and resolves the correct packages without me specifying anything.
9. As a sysadmin, I want auto GPU detection to handle hybrid setups transparently, so that a laptop with an AMD iGPU and NVIDIA dGPU gets both driver sets and `envycontrol` without any manual declaration.
10. As a sysadmin, I want auto GPU detection to recognise VM GPUs (VMware, VirtualBox, virtio-gpu) and install only `mesa`, so that VM-based installs used for testing do not fail on unrecognised hardware.
11. As a sysadmin, I want PipeWire to be installed automatically when any desktop is selected, so that I never have to think about the audio stack for a desktop install.
12. As a sysadmin, I want PipeWire to be omitted when no desktop is selected, so that server installs are not polluted with audio packages.
13. As a sysadmin, I want the installer to abort with a clear error if I set `"desktop"` to an unsupported value, so that typos are caught before any disk writes happen.
14. As a sysadmin, I want the installer to abort with a clear error if I set `"gpu"` to an unsupported value, so that misconfiguration is caught before any disk writes happen.
15. As a sysadmin, I want the Intel GPU driver to be auto-selected by CPU generation (Broadwell+ → `intel-media-driver`, older → `libva-intel-driver`), so that I always get the right driver without knowing the distinction.
16. As a sysadmin, I want KDE apps to remain individually toggleable via `install-kde.jsonc`, so that I can install only the KDE applications I actually use.
17. As a sysadmin, I want Hyprland companion tools (bar, notifications, launcher, lock, idle, wallpaper, terminal) to be individually toggleable via `install-hyprland.jsonc`, so that I can compose my own minimal Hyprland setup.
18. As a sysadmin, I want SDDM to be the display manager when both KDE and Hyprland are selected, so that I can choose between them at the login screen.
19. As a sysadmin, I want greetd and tuigreet to be the display manager when only Hyprland is selected, so that I get a lightweight Wayland-native greeter without a KDE dependency.
20. As a sysadmin, I want the NVIDIA open kernel module to be built via DKMS, so that it works against both `linux` and `linux-lts` kernels without me choosing the right package variant.
21. As a future maintainer, I want to add a new desktop environment by dropping a new `extras/desktop/<name>/` directory, so that no existing code needs to change to support a new DE.
22. As a future maintainer, I want the Environment Runner to have no hardcoded DE names, so that the set of supported DEs is defined entirely by the directory structure.
23. As a sysadmin, I want GPU and audio packages to be resolved at config-load time and fed into pacstrap, so that driver packages are installed as part of the base system — not as a separate post-pacstrap step.
24. As a sysadmin, I want the install summary shown before disk writes to include the resolved desktop, GPU, and audio selections, so that I can confirm the environment configuration before committing.

## Implementation Decisions

### Environment Config schema
A new top-level `"environment"` key is added to the Install Config. It contains two fields: `"desktop"` (string or array of strings, nullable) and `"gpu"` (string or array of strings). Audio has no config key — it is derived. The existing `post_install.desktop` key is removed. `post_install.backup` and `post_install.security` are preserved unchanged.

Valid `"desktop"` values: `"kde"`, `"hyprland"`, or `["kde", "hyprland"]`.
Valid `"gpu"` values: `"amd"`, `"nvidia"`, `"intel"`, `["amd", "nvidia"]`, or `"auto"`.

### GPU Resolution Module
A pure function in `lib/config.sh`. Accepts the raw `"gpu"` value from the Install Config. If `"auto"`, runs `lspci` on the live ISO to detect GPU vendors and resolves to a string or array. Normalises the resolved value to an array. Maps each vendor to its package list. Injects `envycontrol` for hybrid configs. Falls back to `mesa` for VM GPUs with a logged notice.

Vendor → package mapping:
- `amd` → `vulkan-radeon`, `xf86-video-amdgpu`, `mesa`, `libva-mesa-driver`
- `nvidia` → `nvidia-open-dkms`, `nvidia-utils`, `lib32-nvidia-utils`, `libva-nvidia-driver`, `egl-wayland`
- `intel` → `intel-media-driver` (Broadwell+) or `libva-intel-driver` (pre-Broadwell), selected by `lspci` device ID
- VM (VMware/VirtualBox/virtio-gpu) → `mesa`

Resolved packages are written into `packages.groups.gpu` before pacstrap.

### Audio Resolution Module
A thin function in `lib/config.sh`. If the resolved desktop array is non-empty, appends `pipewire`, `pipewire-pulse`, `pipewire-alsa`, `wireplumber` to `packages.groups.audio`. If the desktop array is empty (server install), leaves `packages.groups.audio` empty.

### Environment Config Validation Module
A function in `lib/config.sh` called during `load_config()`, before layout planning. Checks `"desktop"` values against the allowed set and `"gpu"` values against the allowed set. Aborts with a descriptive error listing valid options on any unknown value. Validation runs before any disk writes.

### Environment Runner
`lib/chroot/extras.sh` is updated to iterate the `ENVIRONMENT_DESKTOP` env var (space-separated, passed from the host into the chroot) and invoke `extras/desktop/<de>/<de>.sh` by path convention. No DE name appears as a literal string in the runner. The runner also continues to invoke `post_install.backup` and `post_install.security` extras.

### Desktop Environment Adapter contract
Each adapter at `extras/desktop/<name>/<name>.sh`:
- Reads its companion `install-<name>.jsonc` for per-component toggles
- Installs packages via pacman
- Writes display manager config and enables services
- Receives `ENVIRONMENT_DESKTOP` as an env var to guard DM conflicts (e.g., Hyprland adapter skips greetd when KDE is also in the array, since KDE installs SDDM)

### KDE Desktop Environment Adapter
Existing `extras/desktop/kde/kde.sh` is updated to:
- Read `ENVIRONMENT_DESKTOP` and skip SDDM installation only if a conflicting DM is already present (in practice: SDDM always wins when KDE is in the array, no change needed for the SDDM path)
- No other changes to package selection or `install-kde.jsonc` structure

### Hyprland Desktop Environment Adapter
New `extras/desktop/hyprland/hyprland.sh`:
- Reads `install-hyprland.jsonc` for per-component toggles (bar, notifications, launcher, rofi, terminal, lock, idle, wallpaper)
- Installs `hyprland` unconditionally
- Installs toggled companions: `waybar`, `dunst`, `fuzzel`, `rofi-wayland`, `alacritty`, `hyprlock`, `hypridle`, `hyprpaper`
- If `ENVIRONMENT_DESKTOP` does not contain `"kde"`: installs `greetd` + `greetd-tuigreet`, writes `/etc/greetd/config.toml`, enables greetd
- Installs `xdg-desktop-portal-hyprland`, `polkit-kde-agent`

### Display Manager selection
Not a config key. Auto-selected by the adapters:
- KDE adapter always installs and enables SDDM
- Hyprland adapter installs and enables greetd+tuigreet only when KDE is absent from `ENVIRONMENT_DESKTOP`
- When both are selected, SDDM is the active DM and Hyprland appears as a session

### ADRs
ADR 0005 documents the Desktop Environment Adapter pattern and the rationale for dynamic dispatch over explicit `if/elif` branches.

## Testing Decisions

Good tests in this project test external behaviour through the public interface of a module, not its internals. They use `bats` and set up fixture configs in a `$TEST_DIR` temp directory (see `configs.bats` and `iso-resolver.bats` as prior art). Seams are injected by overriding internal helper functions (e.g., `_iso_resolver_resolve_url`) so tests run without network or hardware access.

### GPU Resolution (`gpu-resolution.bats`)
Override the internal `_lspci_output` seam to return controlled strings. Test:
- Single AMD, NVIDIA, Intel → correct package list
- `"auto"` with AMD lspci → resolves to AMD packages
- `"auto"` with hybrid lspci → resolves to both + `envycontrol`
- `"auto"` with VMware lspci → resolves to `mesa` only, no abort
- `"auto"` with virtio-gpu lspci → resolves to `mesa` only
- Intel Broadwell+ device ID → `intel-media-driver`
- Intel pre-Broadwell device ID → `libva-intel-driver`
- Unknown vendor string → aborts with non-zero exit

### Environment Config Validation (`environment-validation.bats`)
Source `lib/config.sh` with a minimal fixture Install Config. Test:
- Valid `"desktop": "kde"` → exits 0
- Valid `"desktop": "hyprland"` → exits 0
- Valid `"desktop": ["kde", "hyprland"]` → exits 0
- `"desktop": null` → exits 0 (server install)
- `"desktop": "gnome"` → exits non-zero with error message
- Valid `"gpu": "auto"` → exits 0
- `"gpu": "vulkan"` → exits non-zero with error message

### Audio Resolution (`audio-resolution.bats`)
Source `lib/config.sh`. Test:
- Desktop array non-empty → `packages.groups.audio` contains pipewire packages
- Desktop array empty → `packages.groups.audio` is empty

### Environment Runner (`environment-runner.bats`)
Stub the adapter scripts as executable test doubles that write to a file when called. Test:
- `ENVIRONMENT_DESKTOP="kde"` → only KDE adapter invoked
- `ENVIRONMENT_DESKTOP="hyprland"` → only Hyprland adapter invoked
- `ENVIRONMENT_DESKTOP="kde hyprland"` → both adapters invoked
- `ENVIRONMENT_DESKTOP=""` → no adapter invoked
- Unknown DE name → runner fails cleanly (script not found)

### KDE Desktop Environment Adapter (`kde-adapter.bats`)
Mock `pacman` and `systemctl` as stubs. Test:
- `ENVIRONMENT_DESKTOP="kde"` → SDDM installed and enabled
- `ENVIRONMENT_DESKTOP="kde hyprland"` → SDDM still installed (KDE wins DM)
- Shell and apps toggles in `install-kde.jsonc` respected

### Hyprland Desktop Environment Adapter (`hyprland-adapter.bats`)
Mock `pacman` and `systemctl` as stubs. Test:
- `ENVIRONMENT_DESKTOP="hyprland"` → greetd installed, greetd enabled, `/etc/greetd/config.toml` written
- `ENVIRONMENT_DESKTOP="kde hyprland"` → greetd NOT installed (SDDM handles DM)
- Companion toggles in `install-hyprland.jsonc` respected (disabled companion → not passed to pacman)
- `xdg-desktop-portal-hyprland` always installed

## Out of Scope

- Display server selection (X11 vs Wayland) — both KDE and Hyprland are Wayland-first; X11 is not a supported target
- Audio framework selection — PulseAudio is not supported; PipeWire is the only option and is auto-derived
- Network manager selection — NetworkManager is hardcoded and always installed
- GNOME, Xfce, or any other desktop environment beyond KDE and Hyprland
- Post-install dotfiles deployment for Hyprland (companion tool configs are not written by the adapter)
- Graphics driver configuration beyond package installation (no Xorg.conf, no modprobe options)
- NVIDIA proprietary driver support — open kernel module only

## Further Notes

- NVIDIA open kernel module (`nvidia-open-dkms`) requires Turing architecture or newer (RTX 20xx+). The installer does not validate GPU generation — if a user selects `"nvidia"` on older hardware, pacman will fail inside the chroot with a clear error.
- `envycontrol` is an AUR package and cannot go through pacstrap. GPU Resolution outputs two lists: `GPU_PACMAN_PACKAGES` (injected into `packages.groups.gpu` for pacstrap) and `GPU_PARU_PACKAGES` (a separate list). When hybrid GPU is detected, `envycontrol` is added to `GPU_PARU_PACKAGES`. After paru is bootstrapped for the primary user during the profiles phase, any entries in `GPU_PARU_PACKAGES` are installed via `paru -S` before user programs run. This is a targeted extension to the profiles phase — not a general mechanism — and does not require creating a program definition for `envycontrol`.
- The stepskop/.dotfiles Hyprland setup (tuigreet, waybar, dunst, fuzzel, alacritty) is the reference for default companion package selection in `install-hyprland.jsonc`.
- ADR 0005 captures the Desktop Environment Adapter pattern rationale.

## Comments

> *This was generated by AI during triage.*

## Agent Brief

**Category:** enhancement
**Summary:** Add `"environment"` config key to the Install Config supporting desktop environment, GPU driver, and auto-derived audio selection.

**Current behavior:**
The Install Config has a `post_install.desktop.kde` boolean that triggers the KDE extras script. There is no Hyprland support, no GPU driver resolution, and no audio stack installation. A user who wants a graphical system must manually install drivers and audio after first boot.

**Desired behavior:**
The Install Config gains a top-level `"environment"` key with two fields:

- `"desktop"`: `"kde"` | `"hyprland"` | `["kde", "hyprland"]` | `null` — selects desktop environments to install
- `"gpu"`: `"amd"` | `"nvidia"` | `"intel"` | `["amd", "nvidia"]` | `"auto"` — selects GPU driver packages

Audio is auto-derived: PipeWire stack is injected when any desktop is selected, omitted for server installs. GPU and audio packages are resolved at config-load time (before disk writes) and populate the existing `packages.groups.gpu` and `packages.groups.audio` fields, which feed into pacstrap. The existing `post_install.desktop` key is removed. `post_install.backup` and `post_install.security` are unchanged.

Desktop environments are installed inside the chroot via the Desktop Environment Adapter pattern: the Environment Runner iterates the resolved desktop array and invokes `extras/desktop/<de>/<de>.sh` by directory convention — no DE name is hardcoded in the runner. Each adapter is self-contained. ADR 0005 documents the pattern.

**Key interfaces:**

- `"environment"` key in `install.jsonc` — new top-level key, replaces `post_install.desktop`
- GPU Resolution — pure function: raw `"gpu"` value → two package lists. `GPU_PACMAN_PACKAGES` (fed to pacstrap via `packages.groups.gpu`). `GPU_PARU_PACKAGES` (for AUR packages — currently only `envycontrol` on hybrid). The `lspci` call is the injectable seam for testing.
- Audio Resolution — pure function: resolved desktop array → PipeWire package list or empty. Populates `packages.groups.audio`.
- Environment Config Validation — called during `load_config()`, before layout planning. Aborts with a clear error listing valid options on any unrecognised `"desktop"` or `"gpu"` value.
- Environment Runner — replaces the `post_install.desktop.kde` branch in the extras script. Loops over resolved desktop array; invokes `extras/desktop/<de>/<de>.sh`. Passes the full desktop array as an env var so adapters can guard DM conflicts.
- `GPU_PARU_PACKAGES` install step — after paru is bootstrapped for the primary user in the profiles phase, install any entries in `GPU_PARU_PACKAGES` via `paru -S` before user programs run.
- Hyprland Desktop Environment Adapter — new. Reads `install-hyprland.jsonc` for per-component toggles. Installs `hyprland` unconditionally. Installs toggled companions: `waybar`, `dunst`, `fuzzel`, `rofi-wayland`, `alacritty`, `hyprlock`, `hypridle`, `hyprpaper`, `xdg-desktop-portal-hyprland`, `polkit-kde-agent`. If `"kde"` is absent from the desktop array env var: installs `greetd` + `greetd-tuigreet`, writes `/etc/greetd/config.toml`, enables greetd. Companion reference: stepskop/.dotfiles on GitHub.
- KDE Desktop Environment Adapter — minor update only: reads the desktop array env var to guard DM conflict (no behaviour change in practice since SDDM always wins when KDE is present).

**GPU vendor → pacman package mapping:**
- `amd` → `vulkan-radeon xf86-video-amdgpu mesa libva-mesa-driver`
- `nvidia` → `nvidia-open-dkms nvidia-utils lib32-nvidia-utils libva-nvidia-driver egl-wayland`
- `intel` → `intel-media-driver` (Broadwell+ device ID) or `libva-intel-driver` (pre-Broadwell) — detect via `lspci` device ID
- VM GPU (VMware/VirtualBox/virtio-gpu strings in lspci) → `mesa` only, log a notice, do not abort
- Hybrid (amd + nvidia) → both sets via pacman + `envycontrol` via `GPU_PARU_PACKAGES`

**`install-hyprland.jsonc` companion toggles (all default true):**
`bar` (waybar), `notifications` (dunst), `launcher` (fuzzel), `rofi` (rofi-wayland), `terminal` (alacritty), `lock` (hyprlock), `idle` (hypridle), `wallpaper` (hyprpaper)

**Acceptance criteria:**
- [ ] `"environment": { "desktop": "kde", "gpu": "amd" }` in Install Config produces a system with KDE Plasma, SDDM enabled, AMD Vulkan/VA-API drivers, and PipeWire — no manual post-install steps
- [ ] `"environment": { "desktop": "hyprland", "gpu": "auto" }` installs Hyprland with greetd+tuigreet, auto-detects GPU, installs PipeWire
- [ ] `"environment": { "desktop": ["kde", "hyprland"], "gpu": "auto" }` installs both DEs; SDDM is the active display manager; Hyprland appears as a selectable session; greetd is NOT installed
- [ ] Omitting `"environment"` or setting `"desktop": null` produces no desktop, no DM, no audio packages
- [ ] `"gpu": "auto"` on a hybrid AMD+NVIDIA laptop resolves to both driver sets and installs `envycontrol` via paru
- [ ] `"gpu": "auto"` inside a VM (VMware/VirtualBox/virtio) installs only `mesa` and does not abort
- [ ] An unrecognised `"desktop"` value (e.g. `"gnome"`) aborts before any disk writes with a descriptive error
- [ ] An unrecognised `"gpu"` value aborts before any disk writes with a descriptive error
- [ ] `post_install.backup` and `post_install.security` continue to work unchanged
- [ ] BATS tests pass for: GPU Resolution (all vendor branches + hybrid + VM + lspci seam), Audio Resolution, Environment Config Validation, Environment Runner (dynamic dispatch), KDE adapter (SDDM guard), Hyprland adapter (greetd install/skip, companion toggles)
- [ ] Shellcheck passes on all new and modified scripts
- [ ] The install summary displayed before disk writes shows resolved desktop, GPU vendors, and audio status

**Out of scope:**
- Any desktop environment other than KDE and Hyprland
- PulseAudio or any audio framework other than PipeWire
- Network manager selection (NetworkManager remains hardcoded)
- Display server selection (X11 not targeted)
- NVIDIA proprietary driver — open kernel module only
- Post-install dotfiles deployment for Hyprland companion tools (config files not written by the adapter)
- Graphics driver configuration beyond package installation (no modprobe options, no Xorg.conf)
