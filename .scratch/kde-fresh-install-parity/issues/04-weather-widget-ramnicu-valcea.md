# 04 — Weather widget that targets Râmnicu Vâlcea

**What to build:** The panel weather widget shows Râmnicu Vâlcea's forecast on a
fresh login, using a widget from the official repos (nothing vendored or
pinned), in the same panel position the stock widget held. (ADR 0120)

**Blocked by:** 03 — the captured `appletsrc` must exist before its weather
applet is reconfigured.

**Status:** done

- [x] `plasma-applets-weather-widget-3` (official `extra` — blackadderkate's
      weather-widget-2) is added to the KDE package selection.
- [x] The captured `appletsrc` configures the widget with provider **met.no**
      (keyless) and manual latitude/longitude/altitude for Râmnicu Vâlcea
      (≈ 45.10 N, 24.37 E, alt ~240 m).
- [x] The widget occupies the **same panel slot** the stock
      `org.kde.plasma.weather` widget held.
- [x] `packages/resolver.bats` asserts `plasma-applets-weather-widget-3` is in
      the resolved KDE set.
- [x] `extras/kde-adapter.bats` asserts the captured `appletsrc` carries the
      met.no weather config in the expected slot.

## Comments

- 2026-09-27 doc sync: shipped in 8a32898, 54ecfba, 41a2188, 378db0b, a96edbc,
  e79ca17, 4352be4, dfc347d, 8f3795b, badf9e0, cd8f5a0, 840dfea, f598ff0 (ADR
  0118-0121).
