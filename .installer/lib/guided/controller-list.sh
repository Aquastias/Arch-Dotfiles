#!/usr/bin/env bash
# =============================================================================
# lib/guided/controller-list.sh — list rendering (fzf reload)
# =============================================================================
# Part of the guided controller (lib/guided/controller.sh, ADR 0042).
#
# Used by: lib/guided/controller.sh (sources it).
# =============================================================================

# ── list rendering (for fzf reload) ──────────────────────────────────────────
# guided_ctl_list — the current screen's item list on stdout.
guided_ctl_list() {
  _ctl_autocommit   # snapshot any edit for undo/redo (single choke point)
  local nav state base screen
  nav="$(_ctl_nav)"; state="$(_ctl_state)"; base="$(_ctl_baseline)"
  screen="$(navigation_screen "$nav")"
  case "$screen" in
  top)
    # Profiles picker (ADR 0055/0063): a `Profiles ▸` row leads the screen, set
    # off by its own divider above the categories. Unconditional now — even a
    # fresh repo with no committed profiles shows it, because the picker leads
    # with `+ New host (start blank)`, so it is always a first-class entry.
    printf '%s\n' "Profiles ▸ start from a saved machine"
    printf '%s\n' "$_CTL_DIVIDER"
    # Secrets are never a gate (ADR 0055): root, every user, and the encryption
    # passphrase default to 12345, so Proceed always installs. The per-secret
    # source is surfaced (default 12345 / custom / from age) on the Users
    # screen,
    # not as a top-row block. Save/Export are likewise never gated.
    # A blank spacer below the Profiles divider, right above the first category —
    # an inert row for a clear gap between the rule and the categories.
    printf '\n'
    menu_top_lines "$state" "$base"
    # A blank spacer sets the terminal-action block off from the categories —
    # an inert row (skipped like the inter-bucket spacers), so a clear gap sits
    # above the Proceed / Save / Export / Abort divider.
    printf '\n'
    printf '%s\n' "$_CTL_DIVIDER"
    printf '%s\n' "Proceed ▸ review & install"
    # Manual Partitioning is Proceed-only (ADR 0073): a hand-drawn partition
    # table cannot be replayed from a committed file, so Save and Export are
    # withheld while it is active.
    if ! manual_partition_kind_active "$state"; then
      printf '%s\n' \
        "Save profile ▸ write a device-less profile" \
        "Export config ▸ write a device-baked config"
    fi
    # Abort is always available (Esc-equivalent): a pre-destructive clean exit
    # so install.sh skips the back-end. Unconditional, unlike Save/Export which
    # are withheld under Manual Partitioning (ADR 0077).
    printf '%s\n' "Abort ▸ quit without installing" ;;
  profiles)
    # The picker leads with `↺ Reset to blank` (a confirm-gated full session
    # reset, ADR 0063), then the installable Host Profiles (ADR 0055) one row
    # each, then Back. The deep profile tree previews in the pane; picking a
    # profile seeds the menu. On a fresh repo only the reset row + Back show — a
    # consistent entry point.
    printf '%s\n' "↺ Reset to blank"
    profiles_list "$(_ctl_hosts_root)"
    _ctl_action_row "← Back" ;;
  newhost)
    # The `+ New host` confirmation (ADR 0063): a full session reset discards
    # ALL session work, so it is confirm-gated. Enter on the confirm row resets;
    # Back cancels. Broader than Reset-all (which clears Config State only).
    printf '%s\n' "Yes — discard session work and start blank"
    _ctl_action_row "← Back" ;;
  category)
    local cat; cat="$(navigation_get "$nav" category)"
    # Live ESP budget warning (ADR 0078): surfaced on the Kernels + Disks
    # screens where kernels / esp_size are picked, not only at Proceed.
    if [[ "$cat" == "Disks" || "$cat" == "Kernels" ]]; then
      _ctl_esp_budget_warn "$(_ctl_effective "$state" "$base")"
    fi
    # Disks leads with the layout row (the headline storage choice), then
    # fields.
    if [[ "$cat" == "Disks" ]] && manual_partition_kind_active "$state"; then
      # Manual Partitioning (ADR 0073): the pool layout / root-disk / swap rows
      # are replaced by a single Partitions row that launches cfdisk and shows
      # how many partitions the operator has assigned so far.
      local _np
      _np="$(jq '(.disk_config.partitions // []) | length' <<<"$state")"
      printf 'Partitions ▸ %s assigned (run cfdisk)\n' "$_np"
    elif [[ "$cat" == "Disks" ]]; then
      local _ov=""
      jq -e '.os_pool or .mode or .storage_groups or .data_pools' \
        <<<"$state" >/dev/null 2>&1 && _ov="  ●"
      printf '%s: %s%s\n' "$(display_label layout)" \
        "$(_ctl_layout_label "$(_ctl_effective "$state" "$base")")" "$_ov"
      # Single-disk root binds in-menu on-target: a device-mode single-disk
      # layout gets a root disk row (ADR 0047). Multi layouts bind per pool;
      # off-target (count-mode) the single disk is resolved post-menu as before.
      local _deff; _deff="$(_ctl_effective "$state" "$base")"
      if _ctl_device_mode \
        && [[ "$(jq -r '.mode // "single"' <<<"$_deff")" != "multi" ]]; then
        local _rd; _rd="$(jq -r '.root_disk // ""' <<<"$_deff")"
        printf '%s: %s   (Enter to pick)\n' "$(display_label "root disk")" \
          "$([[ -n "$_rd" ]] && _ctl_disk_label "$_rd" || echo "(none)")"
      fi
      local _sov=""
      jq -e '.options.swap != null or .options.swap_size != null' \
        <<<"$state" >/dev/null 2>&1 && _sov="  ●"
      printf '%s: %s%s\n' "$(display_label swap)" \
        "$(_ctl_swap_label "$(_ctl_effective "$state" "$base")")" "$_sov"
    fi
    # Packages leads with the slot drill-downs (ADR 0058). packages.repo/aur had
    # no menu representation at all: seeding a profile carried its whole package
    # payload into Config State where the operator could neither see nor
    # deselect it. `derived` is read-only — it reports what the Environment,
    # Security and Backup choices pull in.
    if [[ "$cat" == "Packages" ]]; then
      local _eff_pkg; _eff_pkg="$(_ctl_effective "$state" "$base")"
      local _slot _n _sov
      for _slot in repo aur; do
        _n="$(_ctl_pkg_slot_count "$_eff_pkg" "$_slot")"
        _sov=""
        jq -e --arg s "$_slot" \
          '(.packages[$s] != null) or (.packages.exclude != null)' \
          <<<"$state" >/dev/null 2>&1 && _sov="  ●"
        printf '%s ▸ %s package%s%s\n' "$_slot" "$_n" \
          "$([[ "$_n" == 1 ]] || echo s)" "$_sov"
      done
      local _dtot; _dtot="$(_ctl_pkg_derived_total "$_eff_pkg")"
      printf 'derived ▸ %s package%s (read-only)\n' \
        "$_dtot" "$([[ "$_dtot" == 1 ]] || echo s)"
    fi
    # Unit-separator (\x1f), not @tsv: a tab IFS is whitespace, so read
    # collapses
    # the double delimiter of an EMPTY value field and shifts the columns. \x1f
    # is non-whitespace, so empty fields are preserved.
    local _ffield _flabel _fval _fov _flock
    while IFS=$'\x1f' read -r _ffield _flabel _fval _fov _flock; do
      # No ZFS anywhere: zfs snapshots is forced off (ADR 0041).
      if [[ "$_ffield" == "post_install.backup.zfs_auto_snapshot" \
            && "$_flock" == "true" ]]; then
        printf '%s: off (no ZFS)\n' "$(display_label "$_flabel")"
        continue
      fi
      # Disks encryption collapses to ONE drill-down row (ADR 0059): the toggle
      # + passphrase live in the Encryption Editor, not on a bool row plus a
      # passphrase sub-row. The row still carries options.encryption's override
      # dot (_fov) so it reads like every other field.
      if [[ "$cat" == "Disks" && "$_ffield" == "options.encryption" ]]; then
        # Manual Partitioning forces it off (ADR 0073); show that, not the
        # retained-but-locked override the operator can no longer edit.
        if manual_partition_kind_active "$state"; then
          printf 'Encryption ▸ off (manual)\n'
        else
          printf 'Encryption ▸ %s%s\n' \
            "$(_ctl_encryption_label "$(_ctl_effective "$state" "$base")" \
              "$(_ctl_secret_tag enc)")" \
            "$([[ "$_fov" == "true" ]] && printf '  ●')"
        fi
        continue
      fi
      # Impermanence collapses to ONE drill-down row (ADR 0066): the toggle +
      # persist-directory management live in the Impermanence Editor, not on a
      # bool row plus a separate Add-persist action. Carries the override dot.
      if [[ "$cat" == "Disks" \
            && "$_ffield" == "options.impermanence.enabled" ]]; then
        if manual_partition_kind_active "$state"; then
          printf 'Impermanence ▸ off (manual)\n'   # forced off (ADR 0073)
          continue
        fi
        local _impon; _impon=off
        [[ "$(config_state_get "$(_ctl_effective "$state" "$base")" \
          options.impermanence.enabled)" == "true" ]] && _impon=on
        printf 'Impermanence ▸ %s%s\n' "$_impon" \
          "$([[ "$_fov" == "true" ]] && printf '  ●')"
        continue
      fi
      # Manual Partitioning is an on/off toggle (ADR 0073): the stored kind is
      # auto/manual, but the operator sees on/off. Enter flips it in place.
      if [[ "$cat" == "Disks" && "$_ffield" == "disk_config.kind" ]]; then
        local _mp=off
        [[ "$_fval" == "manual" ]] && _mp=on
        printf 'Manual partitioning: %s%s\n' "$_mp" \
          "$([[ "$_fov" == "true" ]] && printf '  ●')"
        continue
      fi
      printf '%s: %s%s\n' "$(display_label "$_flabel")" \
        "$(_ctl_display_value_str "$_ffield" "$_fval")" \
        "$([[ "$_fov" == "true" ]] && printf '  ●')"
    done < <(menu_category_rows "$cat" "$state" "$base" | jq -r \
      '.[] | [.field, .label, (.value // ""), (.overridden // false | tostring),
               (.locked // false | tostring)]
             | join("\u001f")')
    _ctl_action_row "← Back" ;;
  pkgcat)
    # The categories inside one slot, each with its package count — mirroring
    # the Categorized List shape so the screen matches the file.
    local _pslot; _pslot="$(navigation_get "$nav" slot)"
    local _peff; _peff="$(_ctl_effective "$state" "$base")"
    local _pk _pn
    while IFS= read -r _pk; do
      [[ -n "$_pk" ]] || continue
      _pn="$(_ctl_pkg_union "$_peff" "$_pslot" "$_pk" | grep -c .)"
      printf '%s ▸ %s\n' "$_pk" "$_pn"
    done < <(_ctl_pkg_categories "$_peff" "$_pslot")
    # Both slots open the in-place browser (ADR 0086): repo from the local sync
    # DB, aur from the fetched packages.gz list.
    if [[ "$_pslot" == "aur" ]]; then
      _ctl_action_row "+ Add package ▸ browse all aur packages"
    else
      _ctl_action_row "+ Add package ▸ browse all repo packages"
    fi
    _ctl_action_row "← Back" ;;
  pkgs)
    # Package toggles with three-state provenance. An inherited entry renders
    # checked WITHOUT a dot; anything this profile or session touched carries
    # one, whether it was added or excluded.
    local _pslot _pcat _peff
    _pslot="$(navigation_get "$nav" slot)"; _pcat="$(navigation_get "$nav" pkgcat)"
    _peff="$(_ctl_effective "$state" "$base")"
    local _pp _mark _dot
    while IFS= read -r _pp; do
      [[ -n "$_pp" ]] || continue
      if _ctl_pkg_excluded "$_peff" "$_pp"; then
        _mark="[ ]"; _dot="  ●"          # excluded by this profile
      else
        _mark="[x]"
        if _ctl_pkg_in_core "$_pslot" "$_pcat" "$_pp"; then
          _dot=""                        # inherited from Host Core
        else
          _dot="  ●"                     # added here
        fi
      fi
      printf '%s %s%s\n' "$_mark" "$_pp" "$_dot"
    done < <(_ctl_pkg_union "$_peff" "$_pslot" "$_pcat")
    _ctl_action_row "← Back" ;;
  pkgbrowse)
    # Every package in the slot as toggle rows IN this fzf (ADR 0086) — no
    # execute() hand-off, so no bare-tty flash. repo reads the local prewarm
    # cache (pacman -Slq); aur lazily fetches packages.gz. Back leads (the list
    # runs to ~15k/~100k rows, so trailing Back is unreachable; Esc backs too).
    _ctl_action_row "← Back"
    local _bslot _blist
    _bslot="$(navigation_get "$nav" slot)"
    if [[ "$_bslot" == "aur" ]]; then
      _blist="$(_ctl_aur_list)"
    else
      _blist="$(cat "${GUIDED_PKGLIST_FILE:-/dev/null}" 2>/dev/null)"
      [[ -n "$_blist" ]] || _blist="$(pacman -Slq 2>/dev/null)"
    fi
    if [[ -z "$_blist" ]]; then
      if [[ "$_bslot" == "aur" ]]; then
        printf '%s\n' \
          "(no AUR list — offline? type a package name and press Enter to add)"
      else
        printf '%s\n' "(no repo packages — run 'pacman -Sy' first, then retry)"
      fi
    else
      # Mark the ~15k rows in one awk pass off precomputed sets (a per-row jq
      # would fork per package). `●` flags a session/profile-touched row; `⟲`
      # a package another choice already pulls in (derived, read-only here).
      local _beff _bcore _bextra _bexcl _bderiv
      _beff="$(_ctl_effective "$state" "$base")"
      _bcore="$(jq -rn --argjson c "$(config_state_host_core)" --arg s "$_bslot" \
        '($c.packages[$s] // {}) | [ .[] | .[]? ] | unique | .[]')"
      _bextra="$(jq -rn --argjson e "$_beff" --arg s "$_bslot" \
        '($e.packages[$s].extra // []) | .[]')"
      _bexcl="$(jq -rn --argjson e "$_beff" '($e.packages.exclude // [])|.[]')"
      _bderiv="$(_ctl_pkg_derived_names "$_beff")"
      awk -v core="$_bcore" -v extra="$_bextra" -v excl="$_bexcl" \
          -v deriv="$_bderiv" -v dot='  ●' -v der='  ⟲ derived' '
        BEGIN{ n=split(core,a,"\n"); for(i=1;i<=n;i++) if(a[i]!="") C[a[i]]=1
               n=split(extra,b,"\n"); for(i=1;i<=n;i++) if(b[i]!="") X[b[i]]=1
               n=split(excl,d,"\n"); for(i=1;i<=n;i++) if(d[i]!="") E[d[i]]=1
               n=split(deriv,g,"\n"); for(i=1;i<=n;i++) if(g[i]!="") D[g[i]]=1 }
        { p=$0
          if      (E[p]) print "[ ] " p dot   # core, excluded here
          else if (C[p]) print "[x] " p       # inherited from core
          else if (X[p]) print "[x] " p dot   # added here
          else if (D[p]) print "[x] " p der   # derived by another choice
          else           print "[ ] " p }     # available to add
      ' <<<"$_blist"
    fi ;;
  pkgderived)
    # Read-only (ADR 0021 keeps the DE adapter owning its own package set).
    # Each row names the category that drives it, so the operator knows where
    # to go to change it.
    # Resolve ONCE, then count per source — the resolver is the expensive part
    # of this render and the loop used to re-run it for every source.
    local _drows
    _drows="$(_ctl_pkg_derived "$(_ctl_effective "$state" "$base")")"
    local _dsrc _dn
    while IFS= read -r _dsrc; do
      [[ -n "$_dsrc" ]] || continue
      _dn="$(awk -F'\t' -v s="$_dsrc" '$1 == s { print $3 }' <<<"$_drows" \
        | sort -u | grep -c .)"
      [[ "$_dn" -gt 0 ]] || continue
      printf '%s ▸ %s   (from %s)\n' "$_dsrc" "$_dn" \
        "$(package_resolver_source_origin "$_dsrc")"
    done < <(package_resolver_sources 2>/dev/null)
    _ctl_action_row "← Back" ;;
  pkgderivedsrc)
    # One derived source's package list. Not toggleable — these are
    # consequences of choices made elsewhere in the menu.
    local _dsrc2; _dsrc2="$(navigation_get "$nav" source)"
    _ctl_pkg_derived "$(_ctl_effective "$state" "$base")" \
      | awk -F'\t' -v s="$_dsrc2" '$1 == s { print "    " $3 }' | sort -u
    _ctl_action_row "← Back" ;;
  values)
    local vf; vf="$(navigation_get "$nav" field)"
    if [[ "$vf" == "sysctl" ]]; then
      _ctl_sysctl_lines "$state" "$base"
      _ctl_action_row "+ Add sysctl (key=value)"
    elif [[ "$vf" == "options.mirror_servers" ]]; then
      # Custom mirror Server= URLs (ADR 0072): one per line + an Add action.
      jq -r '(.options.mirror_servers // [])[]' \
        <<<"$(_ctl_effective "$state" "$base")"
      _ctl_action_row "+ Add server (URL)"
    elif [[ "$vf" == "options.custom_repositories" ]]; then
      # Custom repositories (ADR 0072): "name — url · <SigLevel>" + an Add
      # action.
      jq -r '(.options.custom_repositories // [])[]
        | "\(.name) — \(.url) · "
          + "\(.sign_check // "Required") \(.sign_option // "TrustedOnly")"' \
        <<<"$(_ctl_effective "$state" "$base")"
      _ctl_action_row "+ Add repository (name url [check] [trust])"
    elif [[ "$vf" == "users" ]]; then
      # Flattened Users screen — the account override surface. One merged root
      # row (ADR 0063) symmetric with a user row, then one row per user, each
      # tagged with its password source (default 12345 / custom / from age).
      # Never the value. Enter on the root row opens the Root Editor (password +
      # shell); Enter on a user row opens its User Editor. The disk passphrase
      # lives on the Disks Encryption Editor, not here (ADR 0059).
      local _rsh; _rsh="$(_ctl_root_shell)"
      printf 'root — %s · pw %s\n' "$_rsh" "$(_ctl_secret_tag root)"
      local _um _un _ushell _utag
      while IFS= read -r _um; do
        _un="${_um:4}"
        if [[ "${_um:0:3}" == "[x]" ]]; then
          _ushell="$(_ctl_user_shell "$_un")"
          _utag="$(_ctl_secret_tag user "$_un")"
          printf '%s — %s · pw %s\n' "$_un" "$_ushell" "$_utag"
          printf '      password (%s): %s\n' "$_un" "$_utag"
        else
          printf '%s — disabled\n' "$_un"
        fi
      done < <(_ctl_user_marked "$state" "$base")
      _ctl_action_row "+ Create user (name)"
    elif [[ "$(_ctl_field_kind "$vf")" == "biglist" ]]; then
      _ctl_biglist_options "$vf"
    elif [[ "$(_ctl_field_kind "$vf")" == "toggle" ]]; then
      if _ctl_display_values "$vf"; then
        local _ml; while IFS= read -r _ml; do
          printf '%s %s\n' "${_ml:0:3}" "$(display_label "${_ml:4}")"
        done < <(_ctl_marked_options "$vf" "$state" "$base")
      else
        _ctl_marked_options "$vf" "$state" "$base"
      fi
    else
      if _ctl_display_values "$vf"; then
        local _el; while IFS= read -r _el; do display_label "$_el"; done \
          < <(_ctl_enum_options "$vf")
      else
        _ctl_enum_options "$vf"
      fi
    fi
    _ctl_action_row "← Back" ;;
  text)
    local path cur
    path="$(navigation_get "$nav" field)"
    # the menu-displayed value (effective, else the field default) so a
    # defaulted
    # field shows e.g. "current: 2G" rather than "current: (unset)".
    cur="$(_ctl_field_display "$path" "$state" "$base")"
    printf 'current: %s\n' "${cur:-(unset)}"
    printf '%s\n' "(type above, Enter saves · Esc cancels)" ;;
  swapedit)
    local _eff; _eff="$(_ctl_effective "$state" "$base")"
    if [[ "$(_ctl_swap_on "$_eff")" == "false" ]]; then
      printf 'enabled: off\n'
    else
      printf 'enabled: on\n'
      printf 'size: %s\n' "$(jq -r '.options.swap_size // "auto"' <<<"$_eff")"
      if [[ "$(_ctl_zswap_on "$_eff")" == "false" ]]; then
        printf 'zswap: off\n'
      else
        printf 'zswap: on\n'
        printf 'compressor: %s   (Enter cycles)\n' \
          "$(jq -r '.options.zswap.compressor // "zstd"' <<<"$_eff")"
        printf 'max pool %%: %s   (Enter cycles)\n' \
          "$(jq -r '.options.zswap.max_pool_percent // 20' <<<"$_eff")"
      fi
    fi
    _ctl_action_row "← Back" ;;
  manualparts)
    # Manual Partitioning assignment table (ADR 0073): a validity line, the
    # cfdisk hand-off, then one row per partition (device → mountpoint · fs).
    local _pj _probs
    _pj="$(config_state_get "$state" disk_config.partitions)"; _pj="${_pj:-[]}"
    if _probs="$(layout_manual_partition_problems "$_pj")"; then
      printf '✓ layout is valid — ready to Proceed\n'
    else
      printf '⚠ not installable: %s\n' \
        "$(printf '%s' "$_probs" | head -n1 | sed 's/^• //')"
    fi
    _ctl_action_row "⟳ Run cfdisk (edit the partition table)"
    jq -c '.[]' <<< "$_pj" | while IFS= read -r _p; do
      manual_partition_row_label "$_p"; printf '\n'
    done
    _ctl_action_row "← Back" ;;
  partedit)
    # Per-partition editor: mountpoint / filesystem / format, each cycled by
    # Enter. Only supported values are offered (ADR 0073).
    local _dev _mp _fs _fmt
    _dev="$(navigation_get "$nav" device)"
    _mp="$(_ctl_manual_field "$state" "$_dev" mountpoint)"
    _fs="$(_ctl_manual_field "$state" "$_dev" fs)"
    _fmt="$(_ctl_manual_field "$state" "$_dev" format)"
    printf 'device: %s\n' "$_dev"
    printf 'mountpoint: %s   (Enter cycles)\n' \
      "${_mp:-(unassigned)}"
    printf 'filesystem: %s   (Enter cycles)\n' "${_fs:-(none)}"
    printf 'format: %s   (Enter toggles)\n' \
      "$([[ "$_fmt" == "true" ]] && echo on || echo off)"
    _ctl_action_row "← Back" ;;
  encryption)
    # The Encryption Editor (ADR 0059), collapsing like the swap editor above:
    # only the enablement row when off (a passphrase configures nothing then),
    # the passphrase row too when on. The passphrase row shows its source tag,
    # never the value.
    local _eff; _eff="$(_ctl_effective "$state" "$base")"
    if [[ "$(config_state_get "$_eff" options.encryption)" == "true" ]]; then
      printf 'enabled: on\n'
      printf 'password: %s\n' "$(_ctl_secret_tag enc)"
    else
      printf 'enabled: off\n'
    fi
    _ctl_action_row "← Back" ;;
  impermanence)
    # The Impermanence Editor (ADR 0066), collapsing like swap/encryption: only
    # the enablement row when off; when on, the persist directories (each a
    # removable row), a read-only curated-defaults count, and the Add action.
    local _eff _impen; _eff="$(_ctl_effective "$state" "$base")"
    _impen="$(config_state_get "$_eff" options.impermanence.enabled)"
    if [[ "$_impen" != "true" ]]; then
      printf 'enabled: off\n'
    else
      printf 'enabled: on\n'
      local _pd
      while IFS= read -r _pd; do
        [[ -n "$_pd" ]] && printf '%s\n' "$_pd"
      done < <(jq -r '(.persist.directories // [])[]' <<<"$_eff")
      printf 'curated defaults: %s paths always persisted (read-only)\n' \
        "$(_ctl_curated_persist_count)"
      _ctl_action_row "Add persist directory ▸ extend the curated defaults"
    fi
    _ctl_action_row "← Back" ;;
  datapools)
    # Unified layout editor (ADR 0047): OS pool + storage groups + data pools,
    # each row opening its per-kind editor. Distinct prefixes keep the enter
    # dispatch unambiguous: "OS pool:" (singleton), "<name> (storage):", and the
    # bare "<name>:" data-pool rows.
    local _eff; _eff="$(_ctl_effective "$state" "$base")"
    jq -e '.os_pool' <<<"$_eff" >/dev/null 2>&1 \
      && jq -r '"OS pool: \(.os_pool.topology // "?") "
                + "×\(.os_pool.disk_count // "?")"' \
        <<<"$_eff"
    jq -r '(.storage_groups // [])[]
             | "\(.name) (storage): \(.topology) ×\(.disk_count)"' <<<"$_eff"
    jq -r '(.data_pools // [])[] | "\(.name): \(.topology) ×\(.disk_count)"' \
      <<<"$_eff"
    # The "+ Add …" rows stay visible in BOTH chromes: building the layout is
    # this
    # screen's primary action, and a footer-only ^A hint proved undiscoverable
    # (users saw tank0 and no way to add more). The parentheticals spell out the
    # distinction so the choice is obvious at author time: a data pool is an
    # independent zpool (own filesystem + own key); a storage group folds into
    # the
    # shared `dpool` (zfs, disk-wide key). Offering both lets Custom reconstruct
    # every preset (incl. os-mirror-raidz1). ← Back is legacy-only (Esc in
    # rich).
    printf '%s\n' \
      "+ Add data pool  (standalone pool · any filesystem · own key)" \
      "+ Add storage group  (shared dpool · zfs · disk-wide key)"
    _ctl_action_row "← Back" ;;
  pooledit)
    local i kind p _eff _rootfs
    i="$(navigation_get "$nav" index)"; kind="$(_ctl_pool_kind "$nav")"
    _eff="$(_ctl_effective "$state" "$base")"
    p="$(_ctl_pool_get "$_eff" "$kind" "$i")"
    # A group with no explicit filesystem inherits the root's (ADR 0043), so the
    # displayed value matches what the topology/disks cycles use.
    _rootfs="$(jq -r '.filesystem // "zfs"' <<<"$_eff")"
    printf 'name: %s\n' "$(jq -r '.name // .pool_name // "?"' <<<"$p")"
    case "$kind" in
    os)
      # OS pool: topology + disks only. Root filesystem/encryption live at their
      # top-level rows (ADR 0047), never duplicated here.
      printf 'topology: %s   (Enter cycles)\n' \
        "$(jq -r '.topology // "?"' <<<"$p")"
      _ctl_disks_row "$p" 1
      _ctl_action_row "← Back" ;;
    storage)
      # Storage group: a redundant data area folded into the shared `dpool`. Its
      # topology + disk count are editable (so Custom can rebuild
      # os-mirror-raidz1);
      # the mount is display-only (defaults to /<name>). It inherits the root
      # filesystem — no per-group fs/encryption rows (that is the data-pool
      # path).
      printf 'topology: %s   (Enter cycles)\n' \
        "$(jq -r '.topology // "?"' <<<"$p")"
      _ctl_disks_row "$p" 1
      printf 'mount: %s\n' \
        "$(jq -r '.mount // ("/" + (.name // "data"))' <<<"$p")"
      # Storage groups share dpool's encryption (the disk-wide setting) — shown
      # read-only, since they have no independent key (that is the data-pool
      # path).
      printf 'encryption: %s   (disk-wide, shared)\n' \
        "$([[ "$(jq -r '.options.encryption // false' <<<"$_eff")" \
           == "true" ]] \
           && echo on || echo off)"
      _ctl_action_row "✗ remove this group" "← Back" ;;
    *)
      printf 'filesystem: %s   (Enter cycles)\n' \
        "$(jq -r --arg r "$_rootfs" '.filesystem // $r' <<<"$p")"
      printf 'topology: %s   (Enter cycles)\n' \
        "$(jq -r '.topology // "?"' <<<"$p")"
      _ctl_disks_row "$p" 1
      printf 'encryption: %s   (Enter toggles)\n' \
        "$(jq -r '.encryption // false' <<<"$p")"
      # mount defaults to /<name> (blank keeps the default); editable free-text.
      printf 'mount: %s   (Enter to edit)\n' \
        "$(jq -r '.mount // ("/" + (.name // "pool"))' <<<"$p")"
      _ctl_action_row "✗ remove this pool" "← Back" ;;
    esac ;;
  pooldisks)
    local i kind p _eff d
    i="$(navigation_get "$nav" index)"; kind="$(_ctl_pool_kind "$nav")"
    _eff="$(_ctl_effective "$state" "$base")"
    p="$(_ctl_pool_get "$_eff" "$kind" "$i")"
    # Bound disks first (marked), then the still-free ones (unmarked) — an
    # Enter-toggle multi-select; an exhausted Free Set simply shows no [ ] rows.
    while IFS= read -r d; do
      [[ -n "$d" ]] && printf '[x] %s\n' "$(_ctl_disk_label "$d")"
    done < <(jq -r '(.devices // [])[]' <<<"$p")
    while IFS= read -r d; do
      [[ -n "$d" ]] && printf '[ ] %s\n' "$(_ctl_disk_label "$d")"
    done < <(_ctl_free_disks "$state")
    _ctl_action_row "← Back" ;;
  rootdisk)
    # Single-select radio: the current root_disk marked (*) first (it is bound,
    # so
    # the Free Set excludes it — add it back), then every free candidate ( ).
    # Picking one replaces the prior choice.
    local _rd d
    _rd="$(jq -r '.root_disk // ""' <<<"$(_ctl_effective "$state" "$base")")"
    [[ -n "$_rd" ]] && printf '(*) %s\n' "$(_ctl_disk_label "$_rd")"
    while IFS= read -r d; do
      [[ -n "$d" ]] && printf '( ) %s\n' "$(_ctl_disk_label "$d")"
    done < <(_ctl_free_disks "$state")
    _ctl_action_row "← Back" ;;
  rooteditor)
    # Root Editor (ADR 0063): root's two settings behind one editor, symmetric
    # with the per-user editor. Password uses the same masked capture + no-SOPS
    # root role; shell cycles /bin/bash → /bin/zsh → /bin/fish. Storage is
    # unchanged (options.root_shell + the root manifest role); only the surface
    # differs.
    printf 'password: %s\n' "$(_ctl_secret_tag root)"
    printf 'shell: %s   (Enter cycles)\n' "$(_ctl_root_shell)"
    _ctl_action_row "← Back" ;;
  useredit)
    # Per-user User Editor (ADR 0051): a committed user shows an `enabled`
    # toggle
    # (in/out of the install), an ad-hoc user a `✗ remove user` row; both show
    # the
    # full profile — shell, sudo, groups, git identity, ssh keys, programs —
    # read
    # from the effective (committed `*` install-scoped override) view.
    local un ueff; un="$(navigation_get "$nav" user)"
    ueff="$(_ctl_user_effective "$un")"
    if _ctl_user_is_committed "$un"; then
      local _en; _en="$(jq -r --arg u "$un" \
        'if ((.users // []) | any(. == $u)) then "on" else "off" end' \
        <<<"$(_ctl_effective "$state" "$base")")"
      printf 'enabled: %s   (Enter toggles)\n' "$_en"
    fi
    printf 'shell: %s   (Enter cycles)\n' "$(_ctl_user_shell "$un")"
    printf 'sudo: %s   (Enter toggles)\n' \
      "$(jq -r 'if .sudo then "on" else "off" end' <<<"$ueff")"
    printf 'groups: %s   (Enter edits)\n' \
      "$(jq -r '(.groups // []) | join(", ")
                | if . == "" then "(none)" else . end' \
        <<<"$ueff")"
    printf 'git name: %s   (Enter edits)\n' \
      "$(jq -r '.git.name // "(unset)"' <<<"$ueff")"
    printf 'git email: %s   (Enter edits)\n' \
      "$(jq -r '.git.email // "(unset)"' <<<"$ueff")"
    printf 'ssh keys: %s   (Enter edits)\n' \
      "$(jq -r '(.ssh_authorized_keys // []) | length' <<<"$ueff")"
    printf 'programs: %s   (Enter edits)\n' \
      "$(jq -r '(.programs // []) | join(", ")
                | if . == "" then "(none)" else . end' \
        <<<"$ueff")"
    printf '%s\n' "⧉ Clone this user"
    _ctl_user_is_committed "$un" || printf '%s\n' "✗ remove user"
    _ctl_action_row "← Back" ;;
  userfield)
    # A user-scoped sub-editor (ADR 0051): multi (groups/programs) marks options
    # against the effective value; text (git.name/git.email) shows current +
    # hint;
    # list (ssh) shows the keys + an add action.
    local un field; un="$(navigation_get "$nav" user)"; field="$(navigation_get "$nav" field)"
    case "$(_ctl_userfield_kind "$field")" in
    multi)
      local _sel _opt
      _sel="$(jq -c --arg f "$field" '.[$f] // []' \
        <<<"$(_ctl_user_effective "$un")")"
      while IFS= read -r _opt; do
        if jq -ne --argjson s "$_sel" --arg o "$_opt" 'any($s[]; . == $o)' \
            >/dev/null 2>&1; then printf '[x] %s\n' "$_opt"
        else printf '[ ] %s\n' "$_opt"; fi
      done < <(_ctl_userfield_options "$field")
      _ctl_action_row "← Back" ;;
    text)
      local _cur
      if [[ "$field" == git.* ]]; then
        _cur="$(jq -r --arg k "${field#git.}" '.git[$k] // ""' \
          <<<"$(_ctl_user_effective "$un")")"
        printf 'current: %s\n' "${_cur:-(unset)}"
      fi
      printf '%s\n' "(type above, Enter saves · Esc cancels)" ;;
    list)
      local _k
      while IFS= read -r _k; do [[ -n "$_k" ]] && printf '%s\n' "$_k"; done \
        < <(jq -r '(.ssh_authorized_keys // [])[]' \
          <<<"$(_ctl_user_effective "$un")")
      _ctl_action_row "+ Add SSH key" ;;
    esac ;;
  secret)
    # Inline masked password entry (ADR 0051): the operator types into the fzf
    # query line (masked to bullets by the change bind); this body is just the
    # hint for the current target + phase. The value is read from the buffer
    # file
    # on Enter, never shown here.
    local _tgt _ph _who
    _tgt="$(navigation_get "$nav" target)"; _ph="$(navigation_get "$nav" phase)"
    case "$_tgt" in
    user) _who="$(navigation_get "$nav" user)" ;;
    enc)  _who="encryption" ;;
    *)    _who="root" ;;
    esac
    if [[ "$_ph" == "confirm" ]]; then
      printf 'confirm %s password — type it again, Enter saves\n' "$_who"
    else
      printf 'set %s password — type it, Enter continues\n' "$_who"
    fi
    printf '%s\n' "(masked · backspace to fix · Esc cancels)" ;;
  esac
}
