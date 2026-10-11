#!/usr/bin/env bash
# =============================================================================
# lib/guided/controller-screen-data.sh — packages, disks, user panel, profile tree data
# =============================================================================
# Part of the guided controller (lib/guided/controller.sh, ADR 0042).
#
# Used by: lib/guided/controller.sh (sources it).
# =============================================================================

# ── Packages screen helpers (ADR 0058) ───────────────────────────────────────
# Provenance is three-state, reusing the existing override dot rather than
# inventing glyphs:
#   checked, no dot   — inherited from Host Core
#   checked, with dot — added by this profile or session
#   unchecked, with dot — excluded by this profile
#
# The toggle list can only offer the DECLARED UNION across Host Core and the
# profile: the universe of Arch packages is not enumerable, so adding a
# brand-new package stays a free-text entry (the `+ Add package` row).

# _ctl_pkg_union <effective> <slot> <cat> — the package names offerable in one
# category: everything the effective view carries plus everything Host Core
# declares there plus anything currently excluded (so it can be re-checked).
_ctl_pkg_union() {
  local eff="$1" slot="$2" cat="$3" core
  core="$(config_state_host_core)"
  jq -rn --argjson e "$eff" --argjson c "$core" \
     --arg s "$slot" --arg k "$cat" '
    (($e.packages[$s][$k] // []) + ($c.packages[$s][$k] // [])
     + [($e.packages.exclude // [])[]
        | select(. as $x | ($c.packages[$s][$k] // []) | index($x))])
    | unique | .[]'
}

# _ctl_pkg_categories <effective> <slot> — the categories to list, unioned
# across the effective view and Host Core so a core-only category still shows.
_ctl_pkg_categories() {
  local eff="$1" slot="$2" core
  core="$(config_state_host_core)"
  jq -rn --argjson e "$eff" --argjson c "$core" --arg s "$slot" '
    (($e.packages[$s] // {}) + ($c.packages[$s] // {}))
    | keys_unsorted | sort | .[]'
}

# _ctl_pkg_slot_count <effective> <slot> — how many packages the slot resolves
# to right now (post-exclusion), for the category row summary.
_ctl_pkg_slot_count() {
  jq -rn --argjson e "$1" --arg s "$2" \
    '[($e.packages[$s] // {}) | to_entries[]
      | select(.value | type == "array") | .value[]] | unique | length'
}

# _ctl_pkg_excluded <state> <pkg> — rc 0 when <pkg> is in packages.exclude.
_ctl_pkg_excluded() {
  jq -e --arg p "$2" '(.packages.exclude // []) | index($p)' \
    <<<"$1" >/dev/null 2>&1
}

# _ctl_pkg_in_core <slot> <cat> <pkg> — rc 0 when Host Core declares it there.
_ctl_pkg_in_core() {
  jq -e --arg s "$1" --arg k "$2" --arg p "$3" \
    '(.packages[$s][$k] // []) | index($p)' \
    <<<"$(config_state_host_core)" >/dev/null 2>&1
}

# _ctl_pkg_derived <effective> — the Package Resolver's derived rows for this
# config (TSV: source, layer, package). The SAME resolver the CLI inspector
# calls, so the menu's derived section and `explain-packages` cannot drift.
_ctl_pkg_derived() {
  package_resolver_resolve "$1" 2>/dev/null | awk -F'\t' '$2 == "derived"'
}

# _ctl_pkg_derived_total <effective> — unique derived package count.
_ctl_pkg_derived_total() {
  local n; n="$(_ctl_pkg_derived "$1" | cut -f3 | sort -u | grep -c .)"
  printf '%s' "${n:-0}"
}

# _ctl_pkg_derived_names <effective> — the sorted-unique derived package names,
# cached across a browser session (ADR 0086). Resolving is expensive and the set
# does not change while extras are toggled, so the cache is keyed by the config
# with the browse-add buckets stripped: an add hits it, a derivation change
# (GPU/DE/kernel/…) misses and recomputes. Falls back to a live resolve when no
# cache file is wired (tests, non-menu callers).
_ctl_pkg_derived_names() {
  local eff="$1" key f names
  f="${GUIDED_PKGDERIV_FILE:-}"
  key="$(jq -cS 'del(.packages.repo.extra, .packages.aur.extra)' <<<"$eff" \
    | cksum | cut -d' ' -f1)"
  if [[ -n "$f" && -s "$f" && "$(head -n1 "$f" 2>/dev/null)" == "$key" ]]; then
    tail -n +2 "$f"; return 0
  fi
  names="$(_ctl_pkg_derived "$eff" | cut -f3 | sort -u)"
  [[ -n "$f" ]] && { printf '%s\n' "$key"; printf '%s' "$names"; } >"$f"
  printf '%s\n' "$names"
}

# _ctl_aur_list — every AUR package name for the browser (ADR 0086). AUR has no
# local DB and no helper at menu time, so the names come from the published
# packages.gz. Lazy + session-cached: filled on first open, reused after; a
# failed/offline fetch yields nothing (the render then shows the type-to-add
# notice). Bounded curl so offline does not hang the menu. Network path is
# UNVERIFIED by bats; tests seed GUIDED_AURLIST_FILE to exercise the cache read.
_ctl_aur_list() {
  local f="${GUIDED_AURLIST_FILE:-}" list
  if [[ -n "$f" && -s "$f" ]]; then cat "$f"; return 0; fi
  list="$(curl -fsSL --connect-timeout 2 --max-time 8 \
    https://aur.archlinux.org/packages.gz 2>/dev/null \
    | gunzip 2>/dev/null | grep -v '^#')"
  if [[ -n "$list" ]]; then
    [[ -n "$f" ]] && printf '%s\n' "$list" >"$f"
    printf '%s\n' "$list"
  fi
}

# _ctl_aur_preview <pkg> — the browser's preview for an AUR row: the RPC info
# (ADR 0086), formatted, cached one file per package under GUIDED_AURINFO_DIR so
# re-hovering never re-hits the network. Only a good fetch is cached, so a
# transient timeout retries next hover. curl -g keeps the literal arg[] query.
_ctl_aur_preview() {
  local pkg="$1" d="${GUIDED_AURINFO_DIR:-}" cf json out
  if [[ -n "$d" ]]; then
    cf="$d/${pkg//\//_}"
    [[ -s "$cf" ]] && { cat "$cf"; return 0; }
  fi
  json="$(curl -fsSL -g --connect-timeout 2 --max-time 2 \
    "https://aur.archlinux.org/rpc/v5/info?arg[]=${pkg}" 2>/dev/null)"
  [[ -n "$json" ]] && out="$(jq -r '
    .results[0] // empty
    | "Name:        \(.Name)",
      "Version:     \(.Version)",
      "Description: \(.Description // "-")",
      "Maintainer:  \(.Maintainer // "(orphaned)")",
      "Votes:       \(.NumVotes)   Popularity: \(.Popularity)",
      (if .OutOfDate then "⚠ OUT OF DATE" else empty end),
      "URL:         \(.URL // "-")",
      "AUR:         https://aur.archlinux.org/packages/\(.Name)"
    ' <<<"$json" 2>/dev/null)"
  if [[ -n "$out" ]]; then
    [[ -n "$d" ]] && printf '%s\n' "$out" >"$cf"
    printf '%s\n' "$out"
  else
    printf '%s\n' "(no AUR info — offline, timed out, or not found)"
  fi
}

# The source → driving-category mapping lives with the source table in
# package-resolver.sh (package_resolver_source_origin), so a new derived source
# cannot render here with a missing origin.

# _ctl_bound_disks <state> — every by-id path already bound to ANY group (os +
# storage + data pools, plus the single-disk root), one per line, so a disk
# lives in exactly one place ("disappears everywhere" — ADR 0047).
_ctl_bound_disks() {
  jq -r '[ (.os_pool.devices // [])[],
           ((.storage_groups // [])[].devices // [])[],
           ((.data_pools // [])[].devices // [])[],
           (.root_disk // empty) ] | .[]' <<<"$1"
}

# _ctl_free_disks <state> — the Free Set: enumerated candidates (live medium
# excluded) minus every already-bound disk, one per line.
_ctl_free_disks() {
  local bound; bound="$(_ctl_bound_disks "$1")"
  picker_enum_disks "$(_ctl_live_set)" | awk -v b="$bound" '
    BEGIN { n = split(b, a, "\n"); for (i = 1; i <= n; i++)
              if (a[i] != "") seen[a[i]] = 1 }
    !seen[$0]'
}

# _ctl_disk_label <by-id-path> — the disk row label; delegates to the shared
# picker_disk_label ("/dev/sda <size> <model> · <tail>", tail parseable back
# out).
_ctl_disk_label() { picker_disk_label "$1"; }

# _ctl_pool_toggle_disk <group> <by-id-path> — flip the disk's membership in the
# group's devices[], then re-derive disk_count as the number bound.
_ctl_pool_toggle_disk() {
  jq -c --arg d "$2" '
    (.devices // []) as $cur
    | (if any($cur[]; . == $d) then ($cur - [$d])
       else ($cur + [$d]) end) as $new
    | .devices = $new | .disk_count = ($new | length)' <<<"$1"
}

# _ctl_disks_row <group-json> <count-editable 0|1> — the pooledit "disks:" row.
# Device-mode shows the bound count and opens the sub-screen; count-mode shows
# the 1-8 cycle when editable (OS pool, data pool, storage group) or a plain
# count when not.
_ctl_disks_row() {
  local p="$1" editable="$2"
  if _ctl_device_mode; then
    printf 'disks: %s bound   (Enter to edit)\n' \
      "$(jq -r '(.devices // []) | length' <<<"$p")"
  elif [[ "$editable" == "1" ]]; then
    printf 'disks: %s   (Enter cycles 1-8)\n' \
      "$(jq -r '.disk_count // "?"' <<<"$p")"
  else
    printf 'disks: %s\n' "$(jq -r '.disk_count // "?"' <<<"$p")"
  fi
}

# _ctl_user_panel <name> — the hovered user's detail panel (ADR 0063): the
# effective (committed-core-merged, session-override-applied) User Profile a
# session-created user shows its in-progress editor-form state, since
# _ctl_user_effective folds the userforms file. Pure over the effective view.
_ctl_user_panel() {
  local u="$1" eff gn ge
  eff="$(_ctl_user_effective "$u")"
  printf '%s\n' "$u"
  printf '  shell:    %s\n' "$(jq -r '.shell // "/bin/zsh"' <<<"$eff")"
  printf '  sudo:     %s\n' \
    "$(jq -r 'if .sudo then "on" else "off" end' <<<"$eff")"
  printf '  groups:   %s\n' "$(jq -r \
    '(.groups // []) | join(", ") | if . == "" then "(none)" else . end' \
    <<<"$eff")"
  printf '  programs: %s\n' "$(jq -r \
    '(.programs // []) | if length == 0 then "(none)"
       else "\(length) · \(join(", "))" end' <<<"$eff")"
  gn="$(jq -r '.git.name // ""' <<<"$eff")"
  ge="$(jq -r '.git.email // ""' <<<"$eff")"
  [[ -n "$gn" || -n "$ge" ]] && printf '  git:      %s <%s>\n' "$gn" "$ge"
  printf '  ssh keys: %s\n' \
    "$(jq -r '(.ssh_authorized_keys // []) | length' <<<"$eff")"
}

# _ctl_profile_tree <resolved-profile-json> — a deep ASCII tree of a machine for
# the Profiles preview (ADR 0063): hostname; users expanded to shell·groups;
# options (kernel, bootloader, encryption, impermanence, swap, ssh); environment
# (desktop/gpu); security; backup; and the disk skeleton (reusing the layout
# graph). Input is the RESOLVED profile (merged over Host Core) so it shows what
# selecting it installs, not the raw on-disk delta. Uses the same ▸ / └─ tree
# style as _ctl_layout_graph so previews feel consistent.
_ctl_profile_tree() {
  local prof="$1" u up sh grp
  jq -r '.system.hostname // "(unnamed host)"' <<<"$prof"
  printf '  ▸ users\n'
  while IFS= read -r u; do
    [[ -n "$u" ]] || continue
    up="$(profile_loader_load_user "$u" 2>/dev/null || printf '{}')"
    [[ -n "$up" ]] || up='{}'
    sh="$(jq -r '.shell // "/bin/zsh"' <<<"$up")"
    grp="$(jq -r '(.groups // []) | join(", ")' <<<"$up")"
    [[ -n "$grp" ]] || grp="-"
    printf '      └─ %s  (%s · %s)\n' "$u" "$sh" "$grp"
  done < <(jq -r '(.users // [])[]' <<<"$prof")
  jq -r "${_MENU_ANY_ZFS_JQ}"'
    def onoff(v): if v == true then "on" else "off" end;
    "  ▸ options",
    "      └─ kernel: \((.options.kernel // ["lts"])
       | if type == "array" then join(", ") else . end)",
    "      └─ bootloader: \(.options.bootloader // "systemd-boot")",
    "      └─ encryption: \(onoff(.options.encryption))",
    "      └─ impermanence: \(onoff(.options.impermanence.enabled))",
    "      └─ swap: \(if .options.swap == false then "off"
       else (.options.swap_size // "auto") end)",
    "      └─ ssh: \(onoff(.options.ssh.enabled))",
    "  ▸ environment",
    "      └─ desktop: \((.environment.desktop // [])
       | if type == "array"
         then (if length == 0 then "(none)" else join(", ") end)
         else . end)",
    "      └─ gpu: \(.environment.gpu // "auto"
       | if type == "array" then join(", ") else . end)",
    "  ▸ security",
    "      └─ firewall: \(.post_install.security.firewall // "none")",
    "      └─ antivirus: \(onoff(.post_install.security.antivirus))",
    "      └─ rootkit: \(onoff(.post_install.security.rootkit))",
    "      └─ apparmor: \(onoff(.post_install.security.apparmor))",
    "  ▸ backup",
    "      └─ snapshots: \(if any_zfs
       then onoff(.post_install.backup.zfs_auto_snapshot)
       else "off (no ZFS)" end)",
    "      └─ borg: \(onoff(.post_install.backup.borg))"
  ' <<<"$prof"
  printf '  ▸ disks\n'
  _ctl_layout_graph "$prof" \
    | while IFS= read -r _l; do printf '      %s\n' "$_l"; done
}
