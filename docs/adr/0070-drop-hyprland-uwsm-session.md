# Drop the uwsm Hyprland session; start-hyprland is the sole one

---
Status: accepted (amends ADR 0067, which offered both sessions)
---

The Hyprland adapter no longer curates the packaged `hyprland-uwsm.desktop`
session, and no longer installs the `uwsm` package. `start-hyprland`
(`hyprland.desktop`, DRM-backend-forced) is the only Hyprland session offered.

On a real AMD-iGPU laptop (SDDM + KDE + Hyprland, encrypted ZFS, impermanence
on), the uwsm session **black-screens on the first post-boot login** and only
the uwsm session — Plasma and start-hyprland work on the same boot; a second
login (after a VT switch) works. The system journal shows the cause: SDDM
launches `uwsm start … hyprland`, uwsm logs `graphical.target is queued for
start, waiting for 60s…`, `wayland-wm@hyprland.service` never activates
(`inactive (dead)`), and ~10 s later the session is torn down
(`sddm-helper … exited with 64`), leaving no compositor driving the panel.

uwsm launches the compositor indirectly, as a systemd `--user` unit ordered
under the user `graphical.target`. That target job cannot complete on the first
login because ADR 0061 (impermanence) **pre-starts `user@uid` before the
greeter** to win the XDG_RUNTIME_DIR race that black-screened kwin — leaving the
user manager in a state uwsm's `graphical.target` job can't clear until it
settles. So the very fix that makes kwin and start-hyprland reliable under
impermanence is what deadlocks uwsm's first-boot start. Plasma and start-hyprland
are immune because they launch the compositor **directly**, with no dependency
on the user `graphical.target`.

## Considered options

- **Force the DRM backend on the uwsm session (mirror start-hyprland's
  `env -u`)** — rejected: the failure is uwsm's systemd-user orchestration
  stalling before the compositor ever runs, not a backend pick, so unsetting
  `WAYLAND_DISPLAY`/`DISPLAY` would not help.
- **Unpick ADR 0061's user-manager pre-start** — rejected: it is load-bearing
  for kwin/start-hyprland under impermanence; removing it re-opens their race.
- **Keep uwsm and add a first-boot workaround** — rejected: a fragile,
  hardware-only-verifiable patch for a launcher that adds nothing here.

## Consequences

- The Hyprland picker shows exactly one Hyprland entry (`start-hyprland`) plus,
  on a co-install, Plasma. `uwsm` is no longer pacstrapped by the adapter.
- No functional loss for this fleet: start-hyprland is upstream's recommended
  launcher (crash recovery + safe mode) and the operator manages session
  services via their own `hyprland.conf` `exec-once`, not systemd user units —
  the only thing uwsm added. Someone who wants uwsm-managed session units adds
  the session and package back deliberately.
