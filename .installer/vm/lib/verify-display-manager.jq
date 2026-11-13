# verify-display-manager.jq — the systemd service boot-verify checks for the
# profile's Display Manager, resolved as the installer does (ADR 0069/0091):
# `auto` is desktop-aware (sddm when kde is present, else greetd for a
# KDE-free set); noctalia-greeter runs under greetd (ADR 0158); no desktop
# gives "none" (no DM check).

(.install.environment.display_manager // "auto") as $dm
# The desktop set, a lone desktop counted as one.
| (.install.environment.desktop // []) as $d0
| (if ($d0 | type) == "string" then [$d0] else $d0 end) as $des
| if ($des | length) == 0 then "none"
  elif $dm == "auto" then
    (if ($des | index("kde")) then "sddm" else "greetd" end)
  elif $dm == "noctalia-greeter" then "greetd"
  else $dm end
