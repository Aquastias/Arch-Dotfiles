# ADR 0005: Desktop Environment Adapter pattern for dynamic DE dispatch

## Status
Accepted

## Context
The installer needed to support multiple desktop environments (KDE, Hyprland, or both) selectable via `environment.desktop` in `install.jsonc`. The naive approach would add an explicit `if/elif` branch in `lib/chroot/extras.sh` for each supported DE.

The project already established the same pattern for bootloaders (ADR 0003): the Bootloader Module invokes `bootloader-${BOOTLOADER}.sh` by convention, so adding a new bootloader requires only a new script — no branch in the orchestrator.

## Decision
Desktop environment installation follows the same adapter pattern. `extras/desktop/<name>/<name>.sh` is the contract. The Environment Runner (`lib/chroot/extras.sh`) normalises `environment.desktop` to an array, then iterates and invokes each adapter by path convention. No DE name appears in the runner as a literal string.

Each Desktop Environment Adapter owns: package installation, display manager selection and config, and service enablement. Display manager is auto-selected by the adapter based on the full resolved desktop array passed as an env var — not a separate config key.

## Consequences
- Adding a new DE requires only a new `extras/desktop/<name>/` directory — zero runner changes
- Removing a DE is dropping the directory — again zero runner changes
- The runner has no knowledge of which DEs exist; a typo in `environment.desktop` produces a clear "script not found" error at runtime
- Each adapter must be self-contained and must guard against double-installing a display manager when multiple adapters run (e.g., KDE adapter installs SDDM; Hyprland adapter skips its greeter when SDDM is already present)
