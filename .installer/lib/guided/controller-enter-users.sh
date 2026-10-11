#!/usr/bin/env bash
# =============================================================================
# lib/guided/controller-enter-users.sh — enter dispatch: packages, secrets, users
# =============================================================================
# Part of the guided controller (lib/guided/controller.sh, ADR 0042).
#
# Used by: lib/guided/controller.sh (sources it).
# =============================================================================

# ── enter dispatch (one directive + a file mutation) ─────────────────────────
# guided_controller_enter <line> [<query>] — <query> is fzf's typed text, used only on
# the text screen (the value being entered).
guided_controller_enter() {
  local line="$1" query="${2:-}" screen; screen="$(navigation_screen "$(_controller_navigation)")"
  case "$screen" in
  top)       _controller_enter_top "$line" ;;
  category)  _controller_enter_category "$line" ;;
  values)    _controller_enter_values "$line" ;;
  text)      _controller_enter_text "$query" ;;
  profiles)  _controller_enter_profiles "$line" ;;
  newhost)   _controller_enter_new_host "$line" ;;
  rooteditor) _controller_enter_root_editor "$line" ;;
  swapedit)  _controller_enter_swap_edit "$line" ;;
  manualparts) _controller_enter_manual_partitions "$line" ;;
  partedit)  _controller_enter_partition_edit "$line" ;;
  encryption) _controller_enter_encryption "$line" ;;
  impermanence) _controller_enter_impermanence "$line" ;;
  datapools) _controller_enter_data_pools "$line" ;;
  pooledit)  _controller_enter_pool_edit "$line" ;;
  pooldisks) _controller_enter_pool_disks "$line" ;;
  rootdisk)  _controller_enter_root_disk "$line" ;;
  useredit)  _controller_enter_user_edit "$line" ;;
  userfield) _controller_enter_user_field "$line" "$query" ;;
  secret)    _controller_enter_secret ;;
  pkgcat)    _controller_enter_package_category "$line" "$query" ;;
  pkgs)      _controller_enter_packages "$line" ;;
  pkgbrowse) _controller_enter_package_browse "$line" "$query" ;;
  pkgderived)    _controller_enter_package_derived "$line" ;;
  pkgderivedsrc) _controller_enter_package_derived_source "$line" ;;
  *)         echo noop ;;
  esac
}

# _controller_enter_package_category <line> [query] — drill into a category, or take a free-text
# package name. The universe of Arch packages is not enumerable, so a name
# outside the declared union arrives here rather than as a toggle.
_controller_enter_package_category() {
  local line="$1" query="${2:-}" nav cat slot
  nav="$(_controller_navigation)"; cat="$(navigation_get "$nav" category)"
  slot="$(navigation_get "$nav" slot)"
  case "$line" in
  "← Back") _controller_write_navigation "$(navigation_back "$nav")"; echo render; return ;;
  "+ Add package"*)
    # Both slots open the in-place browser (ADR 0086): repo lists the local
    # pacman -Slq universe; aur lazily fetches the packages.gz names. Either way
    # a typed name that matches nothing still adds (query-as-add, aur), so a
    # brand-new/offline AUR package is never locked out.
    _controller_write_navigation "$(navigation_to_package_browse "$cat" "$slot")"
    echo render
    return ;;
  esac
  # A typed name that matched no row still adds — same free-text affordance.
  if [[ -z "$line" && -n "$query" ]]; then
    _controller_write_state \
      "$(_controller_route_package_entry "$(_controller_state)" "$query")"
    echo refresh; return
  fi
  _controller_write_navigation "$(navigation_to_packages "$cat" "$slot" "${line%% ▸*}")"
  echo render
}

# _controller_enter_packages <line> — toggle one package. Unchecking an INHERITED entry
# writes a packages.exclude entry (that is what makes the exclusion mechanism
# reachable from the menu at all); re-checking removes it. Unchecking a package
# this session added just drops it from the override.
_controller_enter_packages() {
  local line="$1" nav cat slot pcat pkg
  nav="$(_controller_navigation)"; cat="$(navigation_get "$nav" category)"
  slot="$(navigation_get "$nav" slot)"; pcat="$(navigation_get "$nav" pkgcat)"
  [[ "$line" == "← Back" ]] && {
    _controller_write_navigation "$(navigation_back "$nav")"; echo render; return; }

  # strip the "[x] " / "[ ] " mark and any trailing override dot
  pkg="${line:4}"; pkg="${pkg%%  ●}"
  [[ -n "$pkg" ]] || { echo noop; return; }

  local state; state="$(_controller_state)"
  if [[ "${line:0:3}" == "[x]" ]]; then
    # currently installed → remove it
    if _controller_package_in_core "$slot" "$pcat" "$pkg"; then
      state="$(jq --arg p "$pkg" \
        '.packages.exclude = (((.packages.exclude // []) + [$p]) | unique)' \
        <<<"$state")"
    else
      state="$(jq --arg s "$slot" --arg k "$pcat" --arg p "$pkg" \
        'if .packages[$s][$k] then
           .packages[$s][$k] |= map(select(. != $p)) else . end' <<<"$state")"
    fi
  else
    # currently excluded or absent → put it back
    state="$(jq --arg p "$pkg" \
      'if .packages.exclude then
         .packages.exclude |= map(select(. != $p)) else . end
       | if (.packages.exclude // null) == [] then del(.packages.exclude)
         else . end' <<<"$state")"
    _controller_package_in_core "$slot" "$pcat" "$pkg" || state="$(jq \
      --arg s "$slot" --arg k "$pcat" --arg p "$pkg" \
      '.packages[$s][$k] = (((.packages[$s][$k] // []) + [$p]) | unique)' \
      <<<"$state")"
  fi
  _controller_write_state "$state"
  echo refresh
}

# _controller_package_in_core_any <slot> <pkg> — rc 0 when <pkg> is in ANY of the Host
# Core's <slot> category arrays. The browser has no single pkgcat, so it tests
# the whole slot to decide add-vs-exclude the way _controller_enter_packages does per-cat.
_controller_package_in_core_any() {
  jq -e --arg s "$1" --arg p "$2" \
    '[(.packages[$s] // {}) | .[] | .[]?] | index($p)' \
    <<<"$(config_state_host_core)" >/dev/null 2>&1
}

# _controller_enter_package_browse <line> — toggle one package from the full repo browser
# (ADR 0086). Adds route through the ＋Add guard (repo extra / host / user
# program); removes drop a session-added extra or exclude an inherited core
# package — mirroring _controller_enter_packages without a per-category context.
_controller_enter_package_browse() {
  local line="$1" query="${2:-}" navigation slot package state
  navigation="$(_controller_navigation)"; slot="$(navigation_get "$navigation" slot)"
  [[ "$line" == "← Back" ]] && {
    _controller_write_navigation "$(navigation_back "$navigation")"; echo render; return; }
  # query-as-add (aur only): a typed name matching no row still adds, so a
  # brand-new or offline AUR package is reachable when the list can't list it
  # (ADR 0086). repo is fully enumerable, so an unmatched repo name is a typo,
  # not a package — no query-add there.
  if [[ "$slot" == "aur" && -z "$line" && -n "$query" ]]; then
    _controller_write_state "$(_controller_route_package_entry "$(_controller_state)" "$query" aur)"
    echo refresh; return
  fi
  # only the "[x] "/"[ ] " rows toggle — skip the empty-list notice etc.
  [[ "${line:0:1}" == "[" ]] || { echo noop; return; }
  # A derived row is read-only here — its source (Environment/GPU/…) owns it
  # (ADR 0021); toggling would only duplicate it into extra. Say where to change
  # it instead of silently no-op'ing.
  [[ "$line" == *"⟲ derived"* ]] && {
    echo "notice ⟲ already included by another choice — change it there"
    return; }
  # strip the "[x] "/"[ ] " mark and any trailing annotation (a name has no
  # embedded double space, so cutting at the first one is safe)
  package="${line:4}"; package="${package%%  *}"
  [[ -n "$package" ]] || { echo noop; return; }

  _controller_write_state "$(_controller_toggle_browsed_package \
    "$(_controller_state)" "$slot" "$package" "${line:0:3}")"
  echo refresh
}

# _controller_toggle_browsed_package <state> <slot> <package> <mark> — the
# state with <package> flipped: a checked ([x]) core package is excluded, a
# checked extra is dropped; an unchecked core package is un-excluded, an
# unchecked other is routed in as an extra.
_controller_toggle_browsed_package() {
  local state="$1" slot="$2" package="$3" mark="$4"
  if [[ "$mark" == "[x]" ]]; then
    if _controller_package_in_core_any "$slot" "$package"; then
      state="$(jq --arg p "$package" \
        '.packages.exclude = (((.packages.exclude // []) + [$p]) | unique)' \
        <<<"$state")"
    else
      state="$(jq --arg s "$slot" --arg p "$package" \
        'if .packages[$s].extra then
           .packages[$s].extra |= map(select(. != $p)) else . end' <<<"$state")"
    fi
  else
    if _controller_package_in_core_any "$slot" "$package"; then
      state="$(jq --arg p "$package" \
        'if .packages.exclude then
           .packages.exclude |= map(select(. != $p)) else . end
         | if (.packages.exclude // null) == [] then del(.packages.exclude)
           else . end' <<<"$state")"
    else
      state="$(_controller_route_package_entry "$state" "$package" "$slot")"
    fi
  fi
  printf '%s\n' "$state"
}

# _controller_enter_package_derived <line> — drill into one derived source. Nothing here is
# toggleable: these are consequences of choices made in Environment, Security
# and Backup, and ADR 0021 gives the DE adapter ownership of its own set.
_controller_enter_package_derived() {
  local line="$1" nav cat
  nav="$(_controller_navigation)"; cat="$(navigation_get "$nav" category)"
  [[ "$line" == "← Back" ]] && {
    _controller_write_navigation "$(navigation_back "$nav")"; echo render; return; }
  _controller_write_navigation "$(navigation_to_package_derived_source "$cat" "${line%% ▸*}")"
  echo render
}

# _controller_enter_package_derived_source <line> — Back only; every other row is read-only.
_controller_enter_package_derived_source() {
  [[ "$1" == "← Back" ]] && {
    _controller_write_navigation "$(navigation_back "$(_controller_navigation)")"; echo render; return; }
  echo noop
}

# _controller_open_secret <root|user> [name] — start inline masked entry: clear the
# typed
# buffer + any pending first entry, then render the secret screen (phase entry).
# The render directive turns masking on (rebind change, unbind cursor). Writes
# the
# directive to stdout like the other enter handlers.
_controller_open_secret() {
  : > "${GUIDED_PWBUF_FILE:-/dev/null}"
  : > "${GUIDED_PWPENDING_FILE:-/dev/null}"
  # The screen we open from IS the screen the capture returns to (ADR 0059):
  # carry the current nav as the secret's origin so both cancel and save land
  # back here, whether that is the Disks category, the Users list, or the
  # Encryption Editor — no per-target conditional.
  local nav; nav="$(_controller_navigation)"
  local cat; cat="$(navigation_get "$nav" category)"
  _controller_write_navigation "$(navigation_to_secret "$cat" "$1" "${2:-}" entry "$nav")"
  echo render
}

# _controller_enter_secret — Enter on the masked screen: the typed value lives in the
# buffer file. Phase entry stashes it as pending and switches to confirm; phase
# confirm compares — a match writes the password to GUIDED_SECRETS_FILE and
# backs
# to the Users list, a mismatch notices and restarts entry. An empty first entry
# is refused (stay). Never echoes the value.
_controller_enter_secret() {
  local nav cat tgt user phase origin buf pending
  nav="$(_controller_navigation)"; cat="$(navigation_get "$nav" category)"
  tgt="$(navigation_get "$nav" target)"; user="$(navigation_get "$nav" user)"
  phase="$(navigation_get "$nav" phase)"
  # The return screen carried since open (ADR 0059); propagated across the
  # entry↔confirm phase rewrites so it survives to the save.
  origin="$(jq -c '.origin // empty' <<<"$nav")"
  buf="$(cat "${GUIDED_PWBUF_FILE:-/dev/null}" 2>/dev/null)"
  if [[ "$phase" != "confirm" ]]; then
    [[ -n "$buf" ]] || { echo "notice ⚠ password cannot be empty"; return; }
    # The encryption passphrase must be ≥ 8 (ZFS keyformat=passphrase minimum,
    # ADR 0054): reject a short first entry inline before it can fail at pool
    # creation. Passwords keep the non-empty-only rule.
    if [[ "$tgt" == "enc" && ${#buf} -lt 8 ]]; then
      echo "notice ⚠ passphrase must be 8+ chars"; return
    fi
    printf '%s' "$buf" > "${GUIDED_PWPENDING_FILE:-/dev/null}"
    : > "${GUIDED_PWBUF_FILE:-/dev/null}"
    _controller_write_navigation "$(navigation_to_secret "$cat" "$tgt" "$user" confirm "$origin")"
    echo render; return
  fi
  pending="$(cat "${GUIDED_PWPENDING_FILE:-/dev/null}" 2>/dev/null)"
  if [[ "$buf" != "$pending" ]]; then
    : > "${GUIDED_PWBUF_FILE:-/dev/null}"
    : > "${GUIDED_PWPENDING_FILE:-/dev/null}"
    _controller_write_navigation "$(navigation_to_secret "$cat" "$tgt" "$user" entry "$origin")"
    echo "secret-mismatch"; return
  fi
  case "$tgt" in
  user) guided_secrets_file_set_user "${GUIDED_SECRETS_FILE}" "$user" "$buf" ;;
  enc)  guided_secrets_file_set_encryption  "${GUIDED_SECRETS_FILE}" "$buf" ;;
  *)    guided_secrets_file_set_root "${GUIDED_SECRETS_FILE}" "$buf" ;;
  esac
  : > "${GUIDED_PWBUF_FILE:-/dev/null}"
  : > "${GUIDED_PWPENDING_FILE:-/dev/null}"
  # Return to the screen the capture was opened from — the same place Esc lands,
  # read from the carried origin (ADR 0059).
  _controller_write_navigation "$(navigation_back "$nav")"
  echo render
}

# _controller_user_committed_shell <name> — the committed User Profile's effective
# shell
# (merged over User Core), or the User Core default. The strict-delta baseline
# the editor compares an override against.
_controller_user_committed_shell() {
  local s=""
  _controller_user_is_committed "$1" \
    && s="$(profile_loader_load_user "$1" 2>/dev/null \
              | jq -r '.shell // empty' 2>/dev/null)"
  printf '%s' "${s:-$(_controller_default_user_shell)}"
}

# _controller_enter_user_edit <line> — the User Editor dispatch (ADR 0051): toggle a
# committed user in/out of the install (enabled), cycle its shell into an
# install-scoped override (dropped when it lands on the committed shell — strict
# delta), or remove a session-created user. Shell/remove write the userforms
# file;
# enable/disable writes the Config State users list.
_controller_enter_user_edit() {
  local line="$1" navigation category user
  navigation="$(_controller_navigation)"
  category="$(navigation_get "$navigation" category)"
  user="$(navigation_get "$navigation" user)"
  case "$line" in
  "← Back")
    _controller_write_navigation "$(navigation_back "$navigation")"
    echo render ;;
  "enabled:"*)
    _controller_write_state "$(_controller_toggle_users "$(_controller_state)" \
      "$(_controller_baseline)" "$user")"
    echo refresh ;;
  "sudo:"*) _controller_toggle_user_sudo "$user" ;;
  "groups:"* | "git name:"* | "git email:"* | "ssh keys:"* | "programs:"*)
    _controller_open_user_field "$line" "$category" "$user" ;;
  "shell:"*) _controller_cycle_user_shell "$user" ;;
  "⧉ Clone this user")
    # Clone (ADR 0064): drop to a name-entry text screen carrying THIS user
    # as the source. A valid name copies the source's account-shape into a new
    # ad-hoc user and lands in its editor.
    _controller_write_navigation "$(navigation_to_clone "$category" "$user")"
    echo render ;;
  "✗ remove user") _controller_remove_session_user "$user" "$navigation" ;;
  *) echo refresh ;;
  esac
}

# _controller_open_user_field <line> <category> <user> — the User Editor's
# drill-down rows: groups, git name/email, ssh keys, programs.
_controller_open_user_field() {
  local line="$1" category="$2" user="$3" field label
  case "$line" in
  "groups:"*)    field=groups;    label=groups ;;
  "git name:"*)  field=git.name;  label="git name" ;;
  "git email:"*) field=git.email; label="git email" ;;
  "ssh keys:"*)  field=ssh;       label="ssh keys" ;;
  "programs:"*)  field=programs;  label=programs ;;
  esac
  _controller_write_navigation \
    "$(navigation_to_user_field "$category" "$user" "$field" "$label")"
  echo render
}

# _controller_toggle_user_sudo <user> — flip sudo in the user's form delta
# (strict: landing back on the committed value clears the override).
_controller_toggle_user_sudo() {
  local user="$1" current next committed
  [[ -n "${GUIDED_USERFORMS_FILE:-}" ]] || { echo refresh; return; }
  current="$(jq -r 'if .sudo then true else false end' \
    <<<"$(_controller_user_effective "$user")")"
  next="$([[ "$current" == "true" ]] && echo false || echo true)"
  committed="$(jq -c 'if .sudo then true else false end' \
    <<<"$(_controller_user_committed "$user")")"
  _controller_user_form_set_strict "$user" sudo "$next" "$committed"
  echo refresh
}

# _controller_cycle_user_shell <user> — bash → zsh → fish; landing on the
# committed shell drops the override.
_controller_cycle_user_shell() {
  local user="$1" current next
  [[ -n "${GUIDED_USERFORMS_FILE:-}" ]] || { echo refresh; return; }
  current="$(_controller_user_shell_full "$user")"
  next="$(_controller_cycle_next "$current" /bin/bash /bin/zsh /bin/fish)"
  if [[ "$next" == "$(_controller_user_committed_shell "$user")" ]]; then
    guided_userform_unset "$GUIDED_USERFORMS_FILE" "$user" shell
  else
    guided_userform_set "$GUIDED_USERFORMS_FILE" "$user" shell \
      "$(jq -n --arg x "$next" '$x')"
  fi
  echo refresh
}

# _controller_remove_session_user <user> <navigation> — drop a
# session-created user from the install list and its held-aside form, then
# return to the Users list.
_controller_remove_session_user() {
  local user="$1" navigation="$2"
  _controller_write_state "$(config_state_set "$(_controller_state)" users \
    "$(jq -c --arg u "$user" '(.users // []) - [$u]' \
      <<<"$(_controller_effective "$(_controller_state)" \
        "$(_controller_baseline)")")")"
  [[ -n "${GUIDED_USERFORMS_FILE:-}" ]] \
    && guided_userform_clear "$GUIDED_USERFORMS_FILE" "$user"
  _controller_write_navigation "$(navigation_back "$navigation")"
  echo render
}

# _controller_enter_user_field <line> [<query>] — the user-scoped sub-editor dispatch
# (ADR 0051): a multi field toggles membership (STAY), a git text commits the
# typed query and backs to the editor, the ssh list opens an add-key text screen
# and an add commits then re-lists so more keys can follow.
_controller_enter_user_field() {
  local line="$1" query="${2:-}" nav cat un field
  nav="$(_controller_navigation)"; cat="$(navigation_get "$nav" category)"
  un="$(navigation_get "$nav" user)"; field="$(navigation_get "$nav" field)"
  if [[ "$line" == "← Back" ]]; then
    _controller_write_navigation "$(navigation_back "$nav")"; echo render; return
  fi
  case "$(_controller_user_field_kind "$field")" in
  multi)
    _controller_user_field_toggle_multi "$un" "$field" "${line:4}"
    echo refresh; return ;;
  text)
    if [[ "$field" == git.* ]]; then
      [[ -n "$query" ]] && _controller_user_field_set_git "$un" "${field#git.}" "$query"
      _controller_write_navigation "$(navigation_to_user_edit "$cat" "$un")"; echo render; return
    fi
    # ssh.add: append the key, then return to the key list for more.
    [[ -n "$query" ]] && _controller_user_field_add_ssh "$un" "$query"
    _controller_write_navigation "$(navigation_to_user_field "$cat" "$un" ssh "ssh keys")"
    echo render; return ;;
  list)
    [[ "$line" == "+ Add"* ]] && {
      _controller_write_navigation "$(navigation_to_user_field "$cat" "$un" ssh.add "ssh key")"
      echo render; return; }
    echo refresh; return ;;   # an existing key row is display-only
  esac
  echo refresh
}

# _controller_proceed_directive — the in-menu Proceed action (ADR 0055). Proceed is
# NEVER gated on a secret: root, every user, and the encryption passphrase
# default to 12345 (filled by the manifest builder), so install always runs. The
# always-on WILL ERASE / typed-INSTALL consent (back-end) remains the real
# guard.
# Any unset secret is surfaced as `default 12345` on the Users screen, not here.
_controller_proceed_directive() {
  local state; state="$(_controller_state)"
  # Manual Partitioning (ADR 0073): refuse to Proceed on an out-of-bounds layout
  # (missing root/ESP, an unsupported filesystem or mountpoint). The full list
  # of problems is shown live on the Partitions screen; this just blocks Proceed
  # with a header notice. The back-end validator is the ultimate hard stop.
  if manual_partition_kind_active "$state"; then
    local _p; _p="$(config_state_get "$state" disk_config.partitions)"
    layout_manual_partition_problems "${_p:-[]}" >/dev/null || {
      echo "notice Manual layout not installable — fix it on Partitions ▸"
      return
    }
  fi
  echo "terminal proceed"
}
