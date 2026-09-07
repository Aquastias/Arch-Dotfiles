# 04 — Weather widget that targets Râmnicu Vâlcea

**What to build:** The panel weather widget shows Râmnicu Vâlcea's forecast on a
fresh login, using a widget from the official repos (nothing vendored or
pinned), in the same panel position the stock widget held. (ADR 0120)

**Blocked by:** 03 — the captured `appletsrc` must exist before its weather
applet is reconfigured.

**Status:** ready-for-agent

- [ ] `plasma-applets-weather-widget-3` (official `extra` — blackadderkate's
      weather-widget-2) is added to the KDE package selection.
- [ ] The captured `appletsrc` configures the widget with provider **met.no**
      (keyless) and manual latitude/longitude/altitude for Râmnicu Vâlcea
      (≈ 45.10 N, 24.37 E, alt ~240 m).
- [ ] The widget occupies the **same panel slot** the stock
      `org.kde.plasma.weather` widget held.
- [ ] `packages/resolver.bats` asserts `plasma-applets-weather-widget-3` is in
      the resolved KDE set.
- [ ] `extras/kde-adapter.bats` asserts the captured `appletsrc` carries the
      met.no weather config in the expected slot.
