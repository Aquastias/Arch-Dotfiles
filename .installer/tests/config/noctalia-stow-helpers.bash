# noctalia-stow-helpers.bash — shared setup for the noctalia-stow-*.bats parts
# Seam B (ADR 0094/0095): the curated Noctalia/niri config is the single-source
# stow-ready payload at the repo root — the operator may stow it, and the niri
# adapter seeds a copy into /etc/skel (ADR 0095). These tests read the COMMITTED
# payload and assert its shape:
# required keys/values present, host-bound/orphan content absent, scripts
# shaped, and — the drift guard — that config.toml's enabled list mirrors the
# vendored shared core set (noctalia_core_plugins), so the two cannot drift.

setup() {
  REPO="$BATS_TEST_DIRNAME/../../.."      # .installer/tests/config → repo root
  CT="$REPO/.config/noctalia/config.toml"
  KDL="$REPO/.config/niri/config.kdl"
  HC="$REPO/.config/hypr/hyprland.lua"
  # Split config (ADR 0107): the entry file is a manifest of `include` lines;
  # settings live in these conf.d/ part-files, asserted where each construct now
  # lives.
  NENV="$REPO/.config/niri/conf.d/environment.kdl"
  NAPP="$REPO/.config/niri/conf.d/appearance.kdl"
  NAUTO="$REPO/.config/niri/conf.d/autostart.kdl"
  NBIND="$REPO/.config/niri/conf.d/keybinds.kdl"
  HENV="$REPO/.config/hypr/conf.d/environment.lua"
  HAUTO="$REPO/.config/hypr/conf.d/autostart.lua"
  HBIND="$REPO/.config/hypr/conf.d/keybinds.lua"
  CYCLE="$REPO/.local/bin/noctalia-cycle-palette"
  ENABLE="$REPO/.local/bin/noctalia-enable-plugins"
  BRIDGE="$REPO/.local/bin/noctalia-theme-bridge"
  NOCTALIA_SH="$BATS_TEST_DIRNAME/../../lib/packages/noctalia.sh"
  PRESET="$BATS_TEST_DIRNAME/../../lib/chroot/noctalia-preset.sh"
  # The preset seeds /etc/skel through its sibling noctalia-skeleton.sh.
  SKEL="$BATS_TEST_DIRNAME/../../lib/chroot/noctalia-skeleton.sh"
  CHROOT="$BATS_TEST_DIRNAME/../../lib/chroot.sh"
  QT6CT="$REPO/.config/qt6ct/qt6ct.conf"
  QT6CT_COLORS="$REPO/.config/qt6ct/colors"
  # kitty config is single-source under its program home/ (ADR 0134).
  KHOME="$REPO/.installer/programs/system/kitty/home/.config/kitty"
  KITTY="$KHOME/kitty.conf"
  KTPL="$REPO/.config/noctalia/templates/kitty.conf"
  KTHEMES="$KHOME/themes"
  XDGDIRS="$REPO/.local/bin/noctalia-xdg-user-dirs"
}

# toml_table <name> <file> — the [<name>] table's lines through the next
# table header (inclusive, like a sed range).
toml_table() {
  TABLE="[$1]" awk 'index($0, ENVIRON["TABLE"]) == 1 { inside = 1; print; next }
    inside { print; if (/^\[/) inside = 0 }' "$2"
}

