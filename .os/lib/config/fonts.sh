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
# Replaces `packages.repo.fonts` as the single font home (ADR 0080, mirroring
# cups' removal from Host Core under ADR 0079). Absent `options.fonts` ⇒ the
# catalog defaults (the shared baseline), the way absent `options.kernel` ⇒
# lts; an explicit empty array (`[]`) means "no fonts" and is honoured.
#
# The catalog is the sole classifier of a font's repo/AUR routing, so a new
# font is one row here — its menu presence, default state, and install path all
# derive from that one line.
#
# Public API:
#   fonts_catalog_tokens          → every catalog font, one/line (menu options)
#   fonts_default_selection       → the default-checked fonts, one/line
#   fonts_default_selection_json  → the default-checked fonts as a JSON array
#   fonts_selected       <cfg>    → the selected fonts (absent ⇒ defaults)
#   fonts_repo_packages  <cfg>    → selected fonts routed to pacstrap
#   fonts_aur_packages   <cfg>    → selected fonts routed to the paru pass
# =============================================================================

# Catalog rows: package|kind|default   (kind ∈ {repo, aur}; default ∈ {on, off}).
# Nerd-patched monospace builds supersede plain ones (ttf-fira-code dropped for
# ttf-firacode-nerd) because the tracked shell payload is Powerlevel10k, which
# renders Nerd glyphs. Monaspace + Sazanami ship selectable-but-off: Monaspace
# per the operator's default, Sazanami because Noto CJK covers Japanese.
_FONTS_CATALOG=(
  "noto-fonts|repo|on"
  "noto-fonts-emoji|repo|on"
  "noto-fonts-cjk|repo|on"
  "noto-fonts-extra|repo|on"
  "ttf-liberation|repo|on"
  "ttf-dejavu|repo|on"
  "ttf-ms-fonts|aur|on"
  "ttf-jetbrains-mono-nerd|repo|on"
  "ttf-iosevka-nerd|repo|on"
  "ttf-firacode-nerd|repo|on"
  "otf-monaspace-nerd|repo|off"
  "ttf-sazanami|repo|off"
)

# fonts_catalog_tokens — every font in the catalog, one per line, in declared
# order. The enumerated option set the menu multi-select offers.
fonts_catalog_tokens() {
  local spec
  for spec in "${_FONTS_CATALOG[@]}"; do printf '%s\n' "${spec%%|*}"; done
}

# fonts_default_selection — the default-checked fonts, one per line. The shared
# baseline an untouched install lands, seeded into the guided baseline and
# applied when options.fonts is absent.
fonts_default_selection() {
  local spec pkg def
  for spec in "${_FONTS_CATALOG[@]}"; do
    IFS='|' read -r pkg _ def <<<"$spec"
    [[ "$def" == "on" ]] && printf '%s\n' "$pkg"
  done
  return 0
}

# fonts_default_selection_json — the default-checked fonts as a compact JSON
# array, for seeding options.fonts into the Guided baseline.
fonts_default_selection_json() {
  fonts_default_selection | jq -Rn '[inputs]'
}

# _fonts_kind <pkg> → repo | aur | "" (unknown). The catalog is the sole
# classifier; an authored font not in the catalog is unknown and treated as
# repo by the routers below (matching the "free-text extra ⇒ packages.repo"
# convention).
_fonts_kind() {
  local want="$1" spec pkg kind
  for spec in "${_FONTS_CATALOG[@]}"; do
    IFS='|' read -r pkg kind _ <<<"$spec"
    [[ "$pkg" == "$want" ]] && { printf '%s\n' "$kind"; return; }
  done
}

# fonts_selected <config-json> — the selected fonts, one per line. Reads
# options.fonts; absent/null ⇒ the catalog defaults (the shared baseline). An
# explicit empty array (`[]`) is honoured as "no fonts", mirroring
# optional_repos' null-vs-[] distinction.
fonts_selected() {
  local cfg="${1:-{\}}" raw
  raw="$(jq -c '.options.fonts // null' <<<"$cfg")"
  if [[ "$raw" == "null" ]]; then
    fonts_default_selection
  else
    jq -r '.[]' <<<"$raw"
  fi
}

# fonts_repo_packages <config-json> — the selected fonts routed to pacstrap
# (repo kind, plus any unknown/authored font), one per line.
fonts_repo_packages() {
  local pkg
  while IFS= read -r pkg; do
    [[ -n "$pkg" ]] || continue
    [[ "$(_fonts_kind "$pkg")" == "aur" ]] || printf '%s\n' "$pkg"
  done < <(fonts_selected "${1:-{\}}")
  return 0
}

# fonts_aur_packages <config-json> — the selected fonts routed to the paru pass
# (aur kind), one per line. Today only ttf-ms-fonts.
fonts_aur_packages() {
  local pkg
  while IFS= read -r pkg; do
    [[ -n "$pkg" ]] || continue
    [[ "$(_fonts_kind "$pkg")" == "aur" ]] && printf '%s\n' "$pkg"
  done < <(fonts_selected "${1:-{\}}")
  return 0
}
