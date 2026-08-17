# Toggle-derived services generalized: bluetooth, power, fonts

ADR 0079 established the **toggle-derived System Program**: a single bool
(`options.printing.enabled`) that injects `cups` into the Effective Config's
`system_programs` at assembly time and gives it its own Configuration Category.
We extend that one pattern along three axes in a single pass, and — for fonts
only — deliberately reverse 0079's "keep it out of General" stance.

- **Bluetooth** — a second **bool** toggle-derived System Program,
  `options.bluetooth.enabled` (default `true`, a [[Cycle Field]]) in its own
  **Bluetooth** Configuration Category. On → inject a `bluetooth` program that
  `pacman -S bluez bluez-utils` and `systemctl enable bluetooth.service`; off →
  genuinely absent. The toggle owns only the **daemon layer**, never a GUI: on
  KDE, `bluez`/BlueDevil already arrive via `plasma-meta`, so the package
  injection is a `--needed` no-op and the toggle's real contribution is
  *enabling the service* (nothing else does today).

- **Power** — the pattern generalized from a **bool** to an **enum**.
  `options.power.profile` = `none | power-profiles-daemon | tuned` (default
  `power-profiles-daemon`) in its own **Power** Configuration Category. The
  selected value derives the daemon package + its service enable
  (`power-profiles-daemon.service` / `tuned.service`); `tuned` additionally
  pulls `tuned-ppd` so a KDE/Hyprland applet keeps a working profile switcher.
  DE-agnostic by design — `powerprofilesctl` / `tuned-adm` drive it without any
  desktop.

- **Fonts** — a curated **multi-select catalog** modelled on `options.kernel`:
  `options.fonts`, an enumerated set (`menu_enum_options`) resolved to packages,
  some pre-checked. It **replaces** `packages.repo.fonts`, which is **deleted
  from Host Core** so a font has exactly one home (mirroring cups' removal from
  core). The resolver is repo+AUR aware so the lone AUR entry (`ttf-ms-fonts`)
  routes to the Primary-User paru pass. Default-checked: `noto-fonts`,
  `noto-fonts-emoji`, `noto-fonts-cjk`, `noto-fonts-extra`, `ttf-liberation`,
  `ttf-dejavu`, `ttf-ms-fonts`, `ttf-jetbrains-mono-nerd`, `ttf-iosevka-nerd`,
  `ttf-firacode-nerd`; selectable-but-off: `otf-monaspace-nerd`, `ttf-sazanami`.
  Plain `ttf-fira-code` is dropped in favour of the Nerd build.

## Considered options

- **Fonts under General vs its own category vs a Packages leaf** — the operator
  chose **General**. This **amends ADR 0076** (which recut General to *identity*
  — hostname + timezone) and reverses ADR 0079's "General is identity, keep
  service switches out" aside: General now holds *identity + the font catalog*.
  Justification: a curated font list is not service-enablement (so it is unlike
  bluetooth/power, which keep their own categories), and the operator preferred
  one fewer top-level category over the semantic purity of a Packages leaf. The
  Packages-leaf option (fonts are packages; the category already renders font
  toggles) was the rejected alternative — recorded here so it is not
  re-proposed as an obvious "fix".
- **Power as a bool** (`options.power.enabled`, ppd only) — rejected: it would
  hard-code power-profiles-daemon and give a non-KDE / server operator no way to
  choose `tuned` or opt out. The enum is the first toggle-derived key whose
  value picks *which* package, not merely whether one lands.
- **Fonts left as `packages.repo.fonts`** (plain Categorized List, free-text
  additions) — rejected: it cannot present a default-*off* font (e.g. Monaspace)
  as a discoverable unchecked row, which the curated catalog does. Coexisting
  both a catalog and `core.fonts` would give a font two install paths (drift).
- **`blueman` bundled into the Bluetooth toggle** — rejected: it would drop a
  GTK tray on every host including KDE-only ones. Instead `blueman` is owned by
  the **Hyprland adapter** (installed iff Hyprland is selected) and its autostart
  entry carries `NotShowIn=KDE`, so a KDE session shows BlueDevil and a Hyprland
  session shows blueman — one tray per session on a KDE+Hyprland box.

## Consequences

- Three new schema keys (`options.bluetooth.enabled`, `options.power.profile`,
  `options.fonts`) join the closed allowlist; each gets an accessor, a seed
  default, a menu row, and a pure resolver module modelled on `printing.sh`.
- `bluetooth` is filtered from the Packages → system-programs picker exactly as
  `cups` is — its toggle is its sole menu home. The Package Resolver reports the
  derived programs with `source=bluetooth` / `source=power`.
- All three fields are `inert|light` in the matrix Axis Registry: they add
  packages/services with no disk/boot/pool *combination* content, so pure
  bats specs (`bluetooth.bats`, `power.bats`, `fonts.bats`) cover the
  value→package mapping rather than a VM sweep — the precedent ADR 0079 set for
  the printing toggle.
- Host Core's `packages.repo.fonts` block is removed; the desktop/laptop
  profiles inherit fonts through the catalog's defaults instead.
