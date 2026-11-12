#!/usr/bin/env bash
# =============================================================================
# lib/config/fonts.sh — Font Catalog resolver (ADR 0080)
# =============================================================================
# Pure core turning `options.fonts` — a curated multi-select — into the font
# packages that install: repo fonts feed pacstrap, AUR fonts feed the paru
# pass. The single source of truth shared by the menu (option set + defaults),
# the package collector, the AUR resolver, and the Package Resolver, so none of
# them re-encode the catalog. JSON in, package names out. No TTY, no disk.
#
# Replaces `packages.repo.fonts` as the single font home (ADR 0080). Absent
# `options.fonts` ⇒ catalog defaults, like absent `options.kernel` ⇒ lts; an
# explicit `[]` means "no fonts". The catalog is the sole classifier of a font's
# repo/AUR routing, so a new font is one row here.
#
# Public API:
#   fonts_catalog_tokens          → every catalog font, one/line (menu options)
#   fonts_default_selection       → the default-checked fonts, one/line
#   fonts_default_selection_json  → the default-checked fonts as a JSON array
#   fonts_selected       <cfg>    → the selected fonts (absent ⇒ defaults)
#   fonts_repo_packages  <cfg>    → selected fonts routed to pacstrap
#   fonts_aur_packages   <cfg>    → selected fonts routed to the paru pass
#
# Used by: lib/config/{config-state,menu}.sh, lib/packages/package-list.sh,
# lib/packages/package-resolver.sh, lib/profiles/runner.sh.
# =============================================================================

# Catalog rows: package|kind|default  (kind: repo|aur; default: on|off).
# Nerd-patched monospace builds supersede plain ones (ttf-fira-code dropped for
# ttf-firacode-nerd) because the tracked shell payload is Powerlevel10k, which
# renders Nerd glyphs. The default-checked set is neutral (ADR 0157): Noto,
# Liberation and DejaVu cover every script and the metric-compatible core
# families; the Nerd builds and ttf-ms-fonts ship selectable-but-off, and the
# Fleet Layer selects them for the operator's machines. Monaspace + Sazanami are
# off too: Monaspace per the operator's default, Sazanami because Noto CJK
# covers Japanese.
# The jq programs held in single-quoted variables use jq's $names.
# shellcheck disable=SC2016

_FONTS_CATALOG=(
  "noto-fonts|repo|on"
  "noto-fonts-emoji|repo|on"
  "noto-fonts-cjk|repo|on"
  "noto-fonts-extra|repo|on"
  "ttf-liberation|repo|on"
  "ttf-dejavu|repo|on"
  "ttf-ms-fonts|aur|off"
  "ttf-jetbrains-mono-nerd|repo|off"
  "ttf-iosevka-nerd|repo|off"
  "ttf-firacode-nerd|repo|off"
  "otf-monaspace-nerd|repo|off"
  "ttf-sazanami|repo|off"
)

# fonts_catalog_tokens — every font in the catalog, one per line, in declared
# order. The enumerated option set the menu multi-select offers.
fonts_catalog_tokens() {
  local package _rest
  # Each catalog row's package (the field before the first |).
  while IFS='|' read -r package _rest; do
    printf '%s\n' "$package"
  done < <(printf '%s\n' "${_FONTS_CATALOG[@]}")
}

# fonts_default_selection — the default-checked fonts, one per line. The shared
# baseline an untouched install lands, seeded into the guided baseline and
# applied when options.fonts is absent.
fonts_default_selection() {
  local package _kind default
  # Rows: package|kind|default (on | off).
  while IFS='|' read -r package _kind default; do
    [[ "$default" == "on" ]] && printf '%s\n' "$package"
  done < <(printf '%s\n' "${_FONTS_CATALOG[@]}")
  return 0
}

# fonts_default_selection_json — the default-checked fonts as a compact JSON
# array, for seeding options.fonts into the Guided baseline.
fonts_default_selection_json() {
  local list='$fonts | split("\n") | map(select(length > 0))'
  # The default fonts as a JSON array.
  jq -n --arg fonts "$(fonts_default_selection)" "$list"
}

# _fonts_kind <pkg> → repo | aur | "" (unknown). The catalog is the sole
# classifier; an authored font not in the catalog is unknown and treated as
# repo by the routers below (matching the "free-text extra ⇒ packages.repo"
# convention).
_fonts_kind() {
  local want="$1" package kind _default
  # Rows: package|kind|default.
  while IFS='|' read -r package kind _default; do
    [[ "$package" == "$want" ]] && { printf '%s\n' "$kind"; return; }
  done < <(printf '%s\n' "${_FONTS_CATALOG[@]}")
}

# fonts_selected <config-json> — the selected fonts, one per line. Reads
# options.fonts; absent/null ⇒ the catalog defaults (the shared baseline). An
# explicit empty array (`[]`) is honoured as "no fonts", mirroring
# optional_repos' null-vs-[] distinction.
fonts_selected() {
  local config="${1:-{\}}" raw
  # The authored font list (null when absent).
  raw="$(printf '%s\n' "$config" | jq -c '.options.fonts // null')"
  if [[ "$raw" == "null" ]]; then
    fonts_default_selection
  else
    # Its entries.
    printf '%s\n' "$raw" | jq -r '.[]'
  fi
}

# fonts_repo_packages <config-json> — the selected fonts routed to pacstrap
# (repo kind, plus any unknown/authored font), one per line.
fonts_repo_packages() {
  local package
  while IFS= read -r package; do
    [[ -n "$package" ]] || continue
    [[ "$(_fonts_kind "$package")" == "aur" ]] || printf '%s\n' "$package"
  done < <(fonts_selected "${1:-{\}}")
  return 0
}

# fonts_aur_packages <config-json> — the selected fonts routed to the paru pass
# (aur kind), one per line. Today only ttf-ms-fonts.
fonts_aur_packages() {
  local package
  while IFS= read -r package; do
    [[ -n "$package" ]] || continue
    [[ "$(_fonts_kind "$package")" == "aur" ]] && printf '%s\n' "$package"
  done < <(fonts_selected "${1:-{\}}")
  return 0
}
