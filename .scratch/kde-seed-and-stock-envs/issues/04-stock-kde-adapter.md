# 04 — Stock KDE adapter

**What to build:** With `environment.stock` on, a KDE install is upstream-stock:
the `plasma-meta` shell only, with no curated apps and no captured settings seed
— stock Breeze, first-run. (ADR 0112, KDE half.)

**Blocked by:** 02 (KDE captured-settings seed — the seed logic this skips), 03
(`environment.stock` foundation — the env var this reads).

**Status:** ready-for-agent

- [ ] The KDE adapter reads `ENVIRONMENT_STOCK`; when set, it installs the
      `plasma-meta` shell but skips `apps_list`, `apps_extra`, `plugins`, and
      `aur` (ADR 0087) and the entire captured/first-run seed (ADR 0088/0111).
- [ ] When `ENVIRONMENT_STOCK` is unset/false, behaviour is the full opinionated
      install from ticket 02 (no regression).
- [ ] `tests/extras/kde-adapter.bats` asserts the stock path: shell packages
      installed, no captured seed files written to `KDE_SEED_ROOT`, no app sets.
- [ ] Host daemons are unaffected — the Bluetooth service toggle still applies
      under stock (ADR 0080).
