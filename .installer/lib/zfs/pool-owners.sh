#!/usr/bin/env bash
# =============================================================================
# lib/zfs/pool-owners.sh — Owners Resolver (pure) + Owners Applier (thin I/O)
# =============================================================================
# The Owners Resolver decides how a data pool's mountpoint becomes usable by a
# human (ADR 0031): the base user-owner, whether POSIX ACLs are needed, which
# users get a ~/Disks/<pool> symlink, and whether the `owners` declaration is
# valid. It is pure — it never touches the filesystem. The Owners Applier
# consumes that decision and performs the chown/setfacl/symlink I/O.
#
# Input contract shared by the resolver accessors:
#   owners    space-separated tokens; a bare name is a user, @name a group;
#             "" means `owners` was omitted
#   users     space-separated declared usernames, Primary User first
#   groupmap  space-separated "group:member1,member2" pairs ("" when none)
#
# Sourced by 03-install.sh.
# =============================================================================

# The resolved multi-disk layout is read through the layout_* record accessors
# (lib/layout/state.sh) — never by naming the adapter-private _LAYOUT_IMPL_*.
declare -F layout_has_leftover >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../layout/state.sh"

# Ownership mode for the pool:
#   chown — plain `chown <base>:` (the common single-human case)
#   acl   — POSIX ACLs (more than one principal, or any @group)
#   root  — leave root-owned (a host with no declared users + omitted owners)
zfs_pool_owners_mode() {
  local owners="$1" users="$2"
  if [[ -z "$owners" ]]; then
    [[ -n "$users" ]] && printf 'chown' || printf 'root'
    return
  fi
  # More than one principal, or any @group, can't be expressed with chown +
  # one group-owner — that needs POSIX ACLs (ADR 0031).
  local token_count=0 owner_token has_group=0
  for owner_token in $owners; do
    ((token_count++))
    [[ "$owner_token" == @* ]] && has_group=1
  done
  if ((token_count > 1)) || ((has_group)); then printf 'acl'
  else printf 'chown'; fi
}

# Base user-owner of the mountpoint (the human shown by `ls -l`). Omitted
# owners default to the Primary User (the first declared user). Empty when no
# user can own the pool (a host with no declared users).
zfs_pool_owners_base() {
  local owners="$1" users="$2"
  if [[ -z "$owners" ]]; then
    printf '%s' "${users%% *}"
    return
  fi
  # The nominal owner is the first listed *user* (a @group can't own a dir).
  local owner_token
  for owner_token in $owners; do
    [[ "$owner_token" == @* ]] || { printf '%s' "$owner_token"; return; }
  done
}

# Users with access to the pool — one per line. Each gets a ~/Disks/<pool>
# symlink. Omitted owners grant access to just the Primary User; a userless
# host grants access to no one.
zfs_pool_owners_access_users() {
  local owners="$1" users="$2" groupmap="$3"
  if [[ -z "$owners" ]]; then
    [[ -n "$users" ]] && printf '%s\n' "${users%% *}"
    return 0
  fi
  # Union of listed users and the members of listed @groups, in order, deduped.
  local out=() owner_token member
  for owner_token in $owners; do
    if [[ "$owner_token" == @* ]]; then
      for member in \
          $(_pool_owners_group_members "${owner_token#@}" "$groupmap"); do
        _pool_owners_in_list "$member" "${out[*]}" || out+=("$member")
      done
    else
      _pool_owners_in_list "$owner_token" "${out[*]}" || out+=("$owner_token")
    fi
  done
  ((${#out[@]})) && printf '%s\n' "${out[@]}"
  return 0
}

# Space-separated members of <group> from the "group:m1,m2 group2:m3" <map>.
_pool_owners_group_members() {
  local group="$1" map="$2" pair
  for pair in $map; do
    if [[ "$pair" == "${group}:"* ]]; then
      local members_csv="${pair#*:}"
      printf '%s' "${members_csv//,/ }"
      return
    fi
  done
}

# setfacl entries for an ACL pool — one per line. Each listed user gets
# u:<user>:rwx, each @group g:<group>:rwx, every entry mirrored as a default
# ACL (d:...) so newly created files inherit the grant, plus the ACL mask set
# to rwx (m::rwx + d:m::rwx) so the named grants are effective (ADR 0031).
zfs_pool_owners_acl_entries() {
  local owners="$1" owner_token
  for owner_token in $owners; do
    if [[ "$owner_token" == @* ]]; then
      printf 'g:%s:rwx\n' "${owner_token#@}"
    else
      printf 'u:%s:rwx\n' "$owner_token"
    fi
  done
  for owner_token in $owners; do
    if [[ "$owner_token" == @* ]]; then
      printf 'd:g:%s:rwx\n' "${owner_token#@}"
    else
      printf 'd:u:%s:rwx\n' "$owner_token"
    fi
  done
  printf 'm::rwx\n'
  printf 'd:m::rwx\n'
}

# Pure validation: silent + 0 when the `owners` declaration is usable; prints a
# reason + returns 1 when not. Mirrors zfs-pools.sh's validation idiom so
# layout_validate can fail the install before any disk is touched. Rules: a
# bare name must be a declared user; an @group must have ≥1 declared member.
# Omitted owners is always valid (it defaults to the Primary User, or is left
# root-owned with a warning on a userless host).
zfs_pool_owners_validate() {
  local owners="$1" users="$2" groupmap="$3" owner_token members
  [[ -n "$owners" ]] || return 0
  for owner_token in $owners; do
    if [[ "$owner_token" == @* ]]; then
      members="$(_pool_owners_group_members "${owner_token#@}" "$groupmap")"
      [[ -n "${members// }" ]] || {
        printf '%s' "group '${owner_token#@}' has no declared members"
        return 1
      }
    else
      _pool_owners_in_list "$owner_token" "$users" || {
        printf '%s' "owner '${owner_token}' is not a declared user"
        return 1
      }
    fi
  done
  return 0
}

# 0 when <needle> appears in the space-separated <haystack>.
_pool_owners_in_list() {
  local needle="$1" hay="$2" word
  for word in $hay; do
    [[ "$word" == "$needle" ]] && return 0
  done
  return 1
}

# =============================================================================
# OWNERS APPLIER (thin I/O, host-side numeric translation)
# =============================================================================
# Runs on the live ISO against the new system mounted under ${MOUNT_ROOT}, after
# the Runner created users/groups. The ISO has no knowledge of the chroot's
# users, so every owner name is resolved to a numeric UID/GID read from the
# INSTALLED /etc/passwd + /etc/group; a name-based chown on the host would fail
# (ADR 0031). POOL_OWNERS_HOME_BASE is only a fallback when a user has no home
# field; tests may override it.

# Field <n> of <user>'s row in the installed passwd; empty when absent.
_pool_owners_passwd_field() {
  awk -F: -v u="$1" -v n="$2" '$1==u{print $n; exit}' \
    "${MOUNT_ROOT}/etc/passwd" 2>/dev/null
}
_pool_owners_uid()      { _pool_owners_passwd_field "$1" 3; }
_pool_owners_user_gid() { _pool_owners_passwd_field "$1" 4; }
_pool_owners_home()     { _pool_owners_passwd_field "$1" 6; }

# GID of <group> from the installed group db; empty when absent.
_pool_owners_group_gid() {
  awk -F: -v g="$1" '$1==g{print $3; exit}' \
    "${MOUNT_ROOT}/etc/group" 2>/dev/null
}

# Rewrite one name-based ACL spec to numeric ids. u:NAME / g:NAME (and their
# default d:-mirrors) become u:UID / g:GID; mask entries (m::) pass through.
# Prints nothing when a name can't be resolved, so the caller skips it.
_pool_owners_acl_to_numeric() {
  local entry="$1" pre name perm id
  case "$entry" in
  d:u:*) pre="d:u"; name="${entry#d:u:}" ;;
  d:g:*) pre="d:g"; name="${entry#d:g:}" ;;
  u:*)   pre="u";   name="${entry#u:}" ;;
  g:*)   pre="g";   name="${entry#g:}" ;;
  *)     printf '%s' "$entry"; return 0 ;;   # m::rwx / d:m::rwx — no name
  esac
  perm="${name##*:}"; name="${name%%:*}"
  case "$pre" in
  *u) id="$(_pool_owners_uid "$name")" ;;
  *g) id="$(_pool_owners_group_gid "$name")" ;;
  esac
  [[ -n "$id" ]] && printf '%s:%s:%s' "$pre" "$id" "$perm"
}

# The runtime mountpoints to own for a pool/group. A non-independent pool is
# one mountpoint; an `independent` storage group splits into per-disk child
# datasets (<mount>/disk1 … <mount>/diskN) — the parent is canmount=off, so the
# children are the writable datasets (mirrors create_multi_dpool's layout).
_pool_owners_group_mounts() {
  local mount="$1" topology="$2" disk_count="$3"
  if [[ "$topology" == "independent" ]]; then
    local key
    for ((key = 1; key <= disk_count; key++)); do
      printf '%s/disk%s\n' "$mount" "$key"
    done
  else
    printf '%s\n' "$mount"
  fi
}

# chown/ACL one mounted path under the altroot to its owners. Returns non-zero
# (no change) when the base owner can't be resolved in the installed passwd.
_pool_owners_own_path() {
  local mount="$1" owners="$2" users="$3" groupmap="$4"
  local target="${MOUNT_ROOT}${mount}"
  local base base_uid base_gid
  base="$(zfs_pool_owners_base "$owners" "$users")"
  base_uid="$(_pool_owners_uid "$base")"
  base_gid="$(_pool_owners_user_gid "$base")"
  [[ -n "$base_uid" ]] || {
    warn "Owner '${base:-<none>}' is not in the installed passwd —" \
      "leaving ${mount} root-owned."
    return 1; }
  chown "${base_uid}:${base_gid}" "$target"
  chmod 0755 "$target"
  local mode; mode="$(zfs_pool_owners_mode "$owners" "$users" "$groupmap")"
  if [[ "$mode" == "acl" ]]; then
    # The base chown above gives a human user-owner (so `ls -l` shows a name);
    # the named ACL grants are what actually share the pool.
    local entry numeric_entry
    while IFS= read -r entry; do
      [[ -n "$entry" ]] || continue
      numeric_entry="$(_pool_owners_acl_to_numeric "$entry")"
      [[ -n "$numeric_entry" ]] && setfacl -m "$numeric_entry" "$target"
    done < <(zfs_pool_owners_acl_entries "$owners")
  fi
}

# Create ~/Disks/<label> → <target> for every user with access, owned by them.
# <target> is the runtime path (the pool/group mountpoint), so it resolves on
# the booted system regardless of the altroot.
_pool_owners_link() {
  local label="$1" target="$2" owners="$3" users="$4" groupmap="$5"
  local home_base="${POOL_OWNERS_HOME_BASE:-/home}"
  local user uid gid home disks
  while IFS= read -r user; do
    [[ -n "$user" ]] || continue
    uid="$(_pool_owners_uid "$user")"
    [[ -n "$uid" ]] || {
      warn "Pool '${label}': user '${user}' is not in the installed passwd —" \
        "no ~/Disks/${label} symlink."
      continue; }
    gid="$(_pool_owners_user_gid "$user")"
    home="$(_pool_owners_home "$user")"; home="${home:-${home_base}/${user}}"
    disks="${MOUNT_ROOT}${home}/Disks"
    mkdir -p "$disks"
    ln -sfn "$target" "${disks}/${label}"
    chown -h "${uid}:${gid}" "${disks}/${label}"
    chown "${uid}:${gid}" "$disks"
  done < <(zfs_pool_owners_access_users "$owners" "$users" "$groupmap")
}

# Own every (child) mountpoint of a pool/group and create one ~/Disks/<label>
# symlink to its top mountpoint.
#   $1 label   ~/Disks basename + log name
#   $2 mount   top mountpoint (symlink target)
#   $3 topo    topology (independent → per-disk children)
#   $4 dc      disk count (children for independent)
#   $5 owners / $6 users / $7 groupmap  (resolver inputs)
_pool_owners_apply_pool() {
  local label="$1" mount="$2" topology="$3" disk_count="$4"
  local owners="$5" users="$6" groupmap="$7"
  local mode; mode="$(zfs_pool_owners_mode "$owners" "$users" "$groupmap")"
  if [[ "$mode" == "root" ]]; then
    warn "Pool '${label}' (${mount}) has no user to own it — left" \
      "root-owned. Declare a user or an 'owners' list to fix."
    return 0
  fi
  local mountpoint
  while IFS= read -r mountpoint; do
    [[ -d "${MOUNT_ROOT}${mountpoint}" ]] \
      || { info "Skip ${mountpoint} — not mounted."; continue; }
    _pool_owners_own_path "$mountpoint" "$owners" "$users" "$groupmap" || true
  done < <(_pool_owners_group_mounts "$mount" "$topology" "$disk_count")
  _pool_owners_link "$label" "$mount" "$owners" "$users" "$groupmap"
}

# Apply ownership to one single-mount pool + its ~/Disks symlink. Thin wrapper
# over _pool_owners_apply_pool for the common (non-independent) case.
#   $1 label  $2 mount  $3 owners  $4 users  $5 groupmap
zfs_pool_owners_apply_mount() {
  _pool_owners_apply_pool "$1" "$2" stripe 1 "$3" "$4" "$5"
}

# Declared usernames (Primary User first), space-separated, read from the
# assembled effective config (ADR 0036 — the same source the Runner consumes,
# not the legacy per-host config.jsonc). Empty on a host that declares no users.
_pool_owners_declared_users() {
  local users=() user
  while IFS= read -r user; do
    [[ -n "$user" ]] && users+=("$user")
  done < <(jsonc_read "$CONFIG_FILE" '.users[]?' 2>/dev/null)
  printf '%s' "${users[*]}"
}

# Group→members map as "group:m1,m2 ..." for @group resolution/validation. A
# declared user is a member of every group in their effective group set
# (resolve_user_groups — includes wheel for sudo users), sourced from the
# User Profile so membership stays dynamic (ADR 0031). Empty when nothing is
# declared. Glue around the profile loader; covered by the VM smoke test.
_pool_owners_group_map() {
  local users user user_json group groups_csv out=()
  declare -A members=()
  users="$(_pool_owners_declared_users)"
  for user in $users; do
    user_json="$(load_user_profile "$user" 2>/dev/null)" || continue
    groups_csv="$(resolve_user_groups "$user_json" 2>/dev/null)" || true
    for group in ${groups_csv//,/ }; do
      [[ -n "$group" ]] || continue
      if [[ -n "${members[$group]:-}" ]]; then members[$group]+=",$user"
      else members[$group]="$user"; fi
    done
  done
  for group in "${!members[@]}"; do out+=("${group}:${members[$group]}"); done
  printf '%s' "${out[*]}"
}

# owners (space-separated) for the declarative data_pool named <name>, or empty
# when no such config entry exists (e.g. an interactively-synthesized pool,
# which defaults to the Primary User).
_pool_owners_data_pool_owners_by_name() {
  local want="$1" pool_count i name
  pool_count="$(install_config_data_pools_count)"
  for ((i = 0; i < pool_count; i++)); do
    name="$(install_config_data_pool_name "$i")"
    [[ "$name" == "$want" ]] || continue
    install_config_data_pool_owners "$i" | awk '{ printf "%s ", $0 }'
    return
  done
}

# Orchestrator: make every data-pool mountpoint usable by its owner(s) and
# create the ~/Disks/<pool> symlinks. Runs install-time after the Runner
# created users/groups, on the host against the altroot-mounted pools (ADR
# 0031). Covers Standalone Data Pools (declarative + interactive), the Combined
# Data Pool's per-Storage-Group datasets, and folded leftover OS disks.
zfs_pool_owners_apply() {
  section "Applying Data-Pool Ownership"
  local users; users="$(_pool_owners_declared_users)"
  local groupmap; groupmap="$(_pool_owners_group_map)"
  _pool_owners_apply_standalone_pools "$users" "$groupmap"
  _pool_owners_apply_storage_groups "$users" "$groupmap"
  _pool_owners_apply_leftover "$users" "$groupmap"
  info "Data-pool ownership applied."
}

# Standalone Data Pools — from layout state, so interactively-synthesized
# leftover→own-pool pools are covered (owners default to the Primary User).
# A standalone pool is always a single <name>/data mountpoint (ADR 0027
# rejects independent/none for standalone).
_pool_owners_apply_standalone_pools() {
  local users="$1" groupmap="$2" name mount owners
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    mount="$(layout_data_pool_mount "$name")"
    owners="$(_pool_owners_data_pool_owners_by_name "$name")"
    _pool_owners_apply_pool "$name" "$mount" stripe 1 "$owners" "$users" \
      "$groupmap"
  done < <(layout_data_pool_names)
}

# Combined Data Pool — one dataset per declared Storage Group. Topology is
# the resolved runtime choice (covers interactive selection); independent
# groups expand to per-disk child datasets.
_pool_owners_apply_storage_groups() {
  local users="$1" groupmap="$2"
  local storage_group_count i name mount owners topology disk_count
  storage_group_count="$(jsonc "$CONFIG_FILE" | jq '.storage_groups | length')"
  for ((i = 0; i < storage_group_count; i++)); do
    name="$(config_required ".storage_groups[$i].name")"
    mount="$(config_required ".storage_groups[$i].mount")"
    owners="$(install_config_storage_group_owners "$i" \
      | awk '{ printf "%s ", $0 }')"
    topology="$(layout_group_topology "$name")"
    topology="${topology:-$(config_optional ".storage_groups[$i].topology")}"
    topology="${topology:-stripe}"
    disk_count="$(jsonc "$CONFIG_FILE" \
      | jq ".storage_groups[$i].disks | length")"
    _pool_owners_apply_pool "$name" "$mount" "$topology" "$disk_count" \
      "$owners" "$users" "$groupmap"
  done
}

# Folded leftover OS disks → dpool/DATA/extra (interactive, no config entry)
# — default to the Primary User. Topology mirrors create_multi_dpool's
# leftover default (independent).
_pool_owners_apply_leftover() {
  local users="$1" groupmap="$2"
  layout_has_leftover || return 0
  local leftover_partitions leftover_topology
  local -a leftover_list
  leftover_partitions="$(layout_leftover_parts)"
  leftover_topology="$(layout_group_topology _leftover)"
  leftover_topology="${leftover_topology:-independent}"
  read -ra leftover_list <<<"$leftover_partitions"
  _pool_owners_apply_pool extra /data/extra "$leftover_topology" \
    "${#leftover_list[@]}" "" "$users" "$groupmap"
}
