#!/usr/bin/env bash
# =============================================================================
# lib/config/menu.sh — Guided Installer Menu model (ADR 0039)
# =============================================================================
# Turns a Config State into the menu rows the fzf shell renders. Each row
# carries its section (the Host / Users split), the field's dotted path, a
# label, the current value (override if set, else the default), and the `●`
# override flag. The rows ARE the contract — they drive both the shell and the
# tests, so "full parity" means "every covered field surfaces a row".
#
# Pure: JSON-in/JSON-out, no TTY.
#
# Public API:
#   menu_rows <override> [<baseline>]  → JSON array of rows [{section,field,
#                        label,value,overridden}]
#
# <override> is the operator's sparse override map; <baseline> (optional, the
# seeded defaults) supplies a row's displayed value when the operator hasn't
# overridden it. The row VALUE is baseline*override (override wins, jq `*`), but
# `overridden` reflects the OVERRIDE map only — so a seeded-but-untouched field
# shows its value with no ● until the operator edits it.
# =============================================================================

# shellcheck source=./state.sh
declare -F cfgstate_get >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/state.sh"

# shellcheck source=./locale-source.sh
declare -F locale_list_keymaps >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/locale-source.sh"

# shellcheck source=./fonts.sh
declare -F fonts_catalog_tokens >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/fonts.sh"

# Field table — "section|path|label|default". The single source of truth for
# the covered fields; add a row here to surface a field in the menu.
_MENU_FIELDS=(
  "Locales|system.keymap|keyboard|us"
  "Locales|__language__|language|en_US"
  "Locales|__encoding__|encoding|UTF-8"
  "Locales|system.console_font|console font|default8x16"
  "Mirrors & Repositories|options.mirror_countries|mirror countries|Germany, Switzerland, Sweden, France, Romania"
  "Mirrors & Repositories|options.optional_repos|optional repositories|multilib"
  "Mirrors & Repositories|options.mirror_servers|custom servers|[]"
  "Mirrors & Repositories|options.custom_repositories|custom repositories|[]"
  "Pacman|options.pacman.ilovecandy|ILoveCandy|true"
  "Pacman|options.pacman.color|Color|true"
  "Pacman|options.pacman.verbose_pkg_lists|VerbosePkgLists|true"
  "Pacman|options.pacman.disable_download_timeout|DisableDownloadTimeout|false"
  "Pacman|options.pacman.no_progress_bar|NoProgressBar|false"
  "Pacman|options.pacman.parallel_downloads|ParallelDownloads|5"
  "Disks|disk_config.kind|manual partitioning|auto"
  "Disks|filesystem|filesystem|zfs"
  "Disks|options.encryption|encryption|false"
  "Disks|options.impermanence.enabled|impermanence|false"
  "Disks|options.esp_size|esp size|auto"
  "Bootloader|options.bootloader|bootloader|systemd-boot"
  "Kernels|options.kernel|kernel|lts"
  "System|system.hostname|hostname|"
  "System|system.timezone|timezone|Europe/Bucharest"
  # Font Catalog (ADR 0080): a curated multi-select of fonts, resident in
  # System (its one non-identity leaf; General renamed by ADR 0081). Absent ⇒
  # the catalog defaults, seeded into the baseline so a fresh run shows the
  # default set with no ●.
  "System|options.fonts|fonts|"
  "Environment|environment.desktop|desktop|"
  "Environment|environment.display_manager|display manager|auto"
  "Environment|environment.gpu|gpu|auto"
  "Software|packages.repo.extra|extra packages|[]"
  "Security|post_install.security.firewall|firewall|firewalld"
  "Security|post_install.security.antivirus|antivirus|true"
  "Security|post_install.security.rootkit|rootkit|true"
  "Security|post_install.security.apparmor|apparmor|true"
  "Security|sysctl|sysctl|"
  "Backup|post_install.backup.zfs_auto_snapshot|zfs snapshots|true"
  "Backup|post_install.backup.borg|borg|true"
  # Services (ADR 0081): the three toggle-derived daemons share one Services
  # category. Printing (ADR 0079) is a bare-bool Cycle Field (flips in place);
  # default on preserves the historical print daemon.
  "Services|options.printing.enabled|printing|true"
  # Bluetooth (ADR 0080): a bare-bool Cycle Field. Default on installs the bluez
  # daemon and enables bluetooth.service.
  "Services|options.bluetooth.enabled|bluetooth|true"
  # Power Profile (ADR 0080): an enum leaf (none | power-profiles-daemon |
  # tuned), NOT a bare bool, so it drills into a values submenu. Default ppd.
  "Services|options.power.profile|power profile|power-profiles-daemon"
  "Advanced|options.ssh.enabled|ssh|false"
  "Advanced|options.age_key_url|age key url|"
  "Users|users|users|"
)

# menu_enum_options <field> — the canonical option set for an enumerable field,
# one per line. The single source of truth shared by the interactive controller
# (_ctl_enum_options / _ctl_toggle_options) and the replay editors
# (_guided_edit_*), so the two guided front-ends can never drift on what a field
# offers. Free-text / unknown fields emit nothing. Multi-word entries stay whole
# (one per line) — callers mapfile into an array before passing them on.
menu_enum_options() {
  case "$1" in
  options.kernel)                 printf '%s\n' lts default hardened zen ;;
  options.bootloader)
    printf '%s\n' systemd-boot grub efistub limine refind ;;
  environment.desktop)            printf '%s\n' kde hyprland ;;
  environment.display_manager)    printf '%s\n' auto greetd sddm ;;
  environment.gpu)                printf '%s\n' auto amd nvidia intel ;;
  post_install.security.firewall) printf '%s\n' firewalld ufw none ;;
  options.mirror_countries)
    printf '%s\n' Germany Switzerland Sweden France Romania Austria \
      Netherlands "United Kingdom" "United States" Japan Australia ;;
  options.optional_repos)
    printf '%s\n' multilib multilib-testing core-testing extra-testing ;;
  disk_config.kind)               printf '%s\n' auto manual ;;
  options.fonts)                  fonts_catalog_tokens ;;
  options.power.profile)
    printf '%s\n' power-profiles-daemon tuned none ;;
  esac
}

# Manual Partitioning (ADR 0073) — the Disks fields disabled while it is on:
# pool-dependent choices with no meaning on a hand-drawn partition table. They
# stay VISIBLE in the menu but locked (shown-but-locked), so the operator sees
# what was traded away; the controller refuses to edit them. Shared by menu_rows
# (to mark the rows) and the controller (to block edits) so the two never drift.
_MENU_MANUAL_LOCKED=(
  filesystem options.encryption options.impermanence.enabled options.esp_size
)
menu_manual_locked_paths() { printf '%s\n' "${_MENU_MANUAL_LOCKED[@]}"; }

# menu_manual_notice — the one-time notice shown when Manual Partitioning is
# turned on, enumerating exactly which installer features become unavailable.
# The controller prints it on the auto→manual transition; kept here so the
# wording lives beside the locked-paths list it mirrors.
menu_manual_notice() {
  cat <<'EOF'
Manual partitioning hands you the whole partition table (cfdisk).
While it is on, these installer features are unavailable:
  • ZFS / pool layouts
  • Disk encryption
  • Impermanence
  • Multi-disk data pools & storage groups
  • Managed swap  (cut a swap partition in cfdisk instead)
  • ESP size
Turn it back off to restore them — your other choices are kept.
EOF
}

# Configuration Categories — the top-level drill-in groups, in install-flow
# order under six bucket headers (ADR 0081, re-cutting ADR 0071's archinstall
# reading order). Each row is "name|summary|bucket": the category NAME matches a
# row's `section` so a category aggregates its rows; the summary is display-only;
# the BUCKET drives the top-screen header lines (menu_top_lines). Categories
# sharing a bucket MUST be contiguous — the header is emitted on bucket change.
_MENU_CATEGORIES=(
  "System|hostname, timezone, fonts|SYSTEM"
  "Locales|keyboard, language, encoding, console font|SYSTEM"
  "Users|primary user, extra accounts|SYSTEM"
  "Disks|layout, data pools, filesystem, encryption, swap|STORAGE & BOOT"
  "Bootloader|bootloader|STORAGE & BOOT"
  "Kernels|kernel|STORAGE & BOOT"
  "Environment|desktop, display manager, gpu|SOFTWARE"
  "Mirrors & Repositories|countries, optional repos, custom servers/repos|SOFTWARE"
  "Pacman|ilovecandy, color, parallel downloads, verbose lists|SOFTWARE"
  "Software|repo, aur, derived|SOFTWARE"
  "Services|printing, bluetooth, power|SERVICES"
  "Security|firewall, antivirus, rootkit, apparmor, sysctl|SECURITY & DATA"
  "Backup|snapshots, encrypted backup|SECURITY & DATA"
  "Advanced|ssh, age key url|ADVANCED"
)

# menu_categories <override> [<baseline>] — the top-level category rows (JSON
# array of {name, summary, overridden}), in canonical order. `overridden` is the
# fold of the category's field rows: true iff any descendant field is an
# override. No new state — it reads menu_rows's per-field ● flag.
# _MENU_CATEGORIES_JSON — the category table as a JSON array, built once and
# cached (ticket 04), so menu_categories folds the override flags in one jq.
_MENU_CATEGORIES_JSON=""
_menu_categories_json() {
  [[ -n "$_MENU_CATEGORIES_JSON" ]] \
    && { printf '%s' "$_MENU_CATEGORIES_JSON"; return; }
  _MENU_CATEGORIES_JSON="$(printf '%s\n' "${_MENU_CATEGORIES[@]}" | jq -Rn \
    '[inputs | split("|") | {name:.[0], summary:.[1], bucket:.[2]}]')"
  printf '%s' "$_MENU_CATEGORIES_JSON"
}

menu_categories() {
  local rows; rows="$(menu_rows "$1" "${2:-{\}}")"
  # One jq: fold "any field in this category is overridden" per category row.
  jq -n --argjson rows "$rows" --argjson cats "$(_menu_categories_json)" '
    [ $cats[]
      | .name as $n
      | { name: $n, summary: .summary, bucket: .bucket,
          overridden: ($rows | any(.[]; .section == $n and .overridden)) } ]'
}

# menu_top_lines <override> [<baseline>] — the top screen's category block: the
# categories in order (ADR 0081), each as "<name> — <summary>" plus a trailing
# "  ●" when the category aggregates an override, with a "── <BUCKET> ──" header
# line emitted once before each bucket's first category and a blank spacer line
# separating one bucket from the next (ADR 0082 — the top list is the primary
# surface now the parent-column preview is gone, so it breathes). Pure (lines on
# stdout); the controller prints it between the Profiles / terminal-row dividers.
# Kept in the model so the ordering + header logic is unit-testable in isolation.
menu_top_lines() {
  menu_categories "$1" "${2:-{\}}" | jq -r '
    reduce .[] as $c ({prev: null, out: []};
      .out += (if $c.bucket != .prev
               then (if .prev == null then [] else [""] end)
                    + ["── \($c.bucket) ──"]
               else [] end)
            + [ "\($c.name) — \($c.summary)"
                + (if $c.overridden then "  ●" else "" end) ]
      | .prev = $c.bucket)
    | .out[]'
}

# menu_render_value <config> <path> — the one-line rendering of <path>'s value in
# <config> (empty when unset). The single source of truth for how a field's value
# displays: multi-select arrays (kernel / desktop / gpu) render comma-joined,
# primary/first token first; a map (sysctl) renders comma-joined key=value pairs;
# scalars stringify. Shared by menu_rows (display) and the guided controller's
# apply-time normalise (so "matches the default" is judged the way it displays).
menu_render_value() {
  # shellcheck disable=SC2016 # $p/$v are jq vars, must not expand in the shell
  jq -r --arg p "$2" '
    getpath($p | split(".")) as $v
    | if   $v == null         then empty
      elif ($v | type) == "array"  then
        ($v | map(if type == "string" then . else (.name // tostring) end)
            | join(", "))
      elif ($v | type) == "object" then
        ([$v | to_entries[] | "\(.key)=\(.value)"] | join(", "))
      else ($v | tostring) end' <<<"$1"
}

# _MENU_FIELDS_JSON — the field table (_MENU_FIELDS) as a JSON array, built once
# and cached. Lets menu_rows compute every row in a single jq call instead of a
# ~3-jq-per-field fan-out (ticket 04 latency).
_MENU_FIELDS_JSON=""
_menu_fields_json() {
  [[ -n "$_MENU_FIELDS_JSON" ]] && { printf '%s' "$_MENU_FIELDS_JSON"; return; }
  _MENU_FIELDS_JSON="$(printf '%s\n' "${_MENU_FIELDS[@]}" | jq -Rn \
    '[inputs | split("|")
      | {section:.[0], path:.[1], label:.[2], default:(.[3] // "")}]')"
  printf '%s' "$_MENU_FIELDS_JSON"
}

# menu_rows <override> [<baseline>] — the menu rows on stdout (JSON array).
# One jq call: it merges baseline*override, derives the effective filesystem
# (Impermanence is hidden for ext4/xfs — ADR 0040), and for each field renders
# the value (array→", "-join, object→"k=v", scalar→string, empty→default) and
# the override-only ● flag (getpath on the override map != null). Behaviour is
# identical to the old per-field loop — the render logic mirrors
# menu_render_value / cfgstate_is_overridden.
menu_rows() {
  local state="$1" baseline="${2:-{\}}"
  local lockpaths; lockpaths="$(menu_manual_locked_paths | jq -Rn '[inputs]')"
  jq -n \
    --argjson fields "$(_menu_fields_json)" \
    --argjson override "$state" \
    --argjson baseline "$baseline" \
    --argjson lockpaths "$lockpaths" '
    def render($v; $d):
      (if   $v == null            then null
       elif ($v | type) == "array"  then
         ($v | map(if type == "string" then . else (.name // tostring) end)
             | join(", "))
       elif ($v | type) == "object" then
         ([$v | to_entries[] | "\(.key)=\(.value)"] | join(", "))
       else ($v | tostring) end) as $r
      | if ($r == null or $r == "") then $d else $r end;
    # Locale projection (ADR 0076): the canonical system.locale (element 0 when an
    # array) split into its language identity (.CODESET dropped, @modifier kept)
    # and its encoding (the CODESET). loc0 defaults to en_US.UTF-8 so the two
    # leaves render their defaults on a fresh state.
    def loc0($src): ($src.system.locale) as $l
      | (if ($l | type) == "array" then ($l[0] // "") else ($l // "") end)
      | if . == "" then "en_US.UTF-8" else . end;
    def loc_lang($l): ($l | sub("\\.[^.@]+"; ""));
    def loc_enc($l):
      (if ($l | test("\\.[^.@]+")) then ($l | capture("\\.(?<e>[^.@]+)").e)
       else "" end);
    ($baseline * $override) as $m
    | (if (($m.filesystem // "zfs")) == "" then "zfs"
       else ($m.filesystem // "zfs") end) as $fs
    | ($m.disk_config.kind // "auto") as $kind
    | loc0($m) as $mloc
    | loc0($baseline) as $bloc
    | (($override | getpath(["system","locale"])) != null) as $loc_ov
    | [ $fields[]
        | .path as $fp
        | .default as $def
        | select($fp != "options.impermanence.enabled"
                 or ($fs != "ext4" and $fs != "xfs"))
        | ($fp | split(".")) as $pp
        | { section: .section,
            field:   $fp,
            label:   .label,
            value:
              (if   $fp == "__language__"
               then (loc_lang($mloc) | if . == "" then $def else . end)
               elif $fp == "__encoding__"
               then (loc_enc($mloc) | if . == "" then $def else . end)
               else render($m | getpath($pp); $def) end),
            overridden:
              (if   $fp == "__language__"
               then ($loc_ov and (loc_lang($mloc) != loc_lang($bloc)))
               elif $fp == "__encoding__"
               then ($loc_ov and (loc_enc($mloc) != loc_enc($bloc)))
               else (($override | getpath($pp)) != null) end),
            locked:  ($kind == "manual"
                      and ($lockpaths | index($fp)) != null) } ]'
}

# menu_category_rows <category> <override> [<baseline>] — the field rows for one
# Configuration Category (the drill-in sub-menu), filtered from menu_rows by
# `section`. Same per-row shape as menu_rows.
menu_category_rows() {
  local category="$1"
  menu_rows "$2" "${3:-{\}}" | jq --arg c "$category" '[.[] | select(.section == $c)]'
}
