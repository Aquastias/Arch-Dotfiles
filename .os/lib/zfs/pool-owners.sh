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

# Ownership mode for the pool:
#   chown — plain `chown <base>:` (the common single-human case)
#   acl   — POSIX ACLs (more than one principal, or any @group)
#   root  — leave root-owned (a host with no declared users + omitted owners)
pool_owners_mode() {
  local owners="$1" users="$2"
  if [[ -z "$owners" ]]; then
    [[ -n "$users" ]] && printf 'chown' || printf 'root'
    return
  fi
  # More than one principal, or any @group, can't be expressed with chown +
  # one group-owner — that needs POSIX ACLs (ADR 0031).
  local n=0 tok has_group=0
  for tok in $owners; do
    ((n++))
    [[ "$tok" == @* ]] && has_group=1
  done
  if ((n > 1)) || ((has_group)); then printf 'acl'; else printf 'chown'; fi
}

# Base user-owner of the mountpoint (the human shown by `ls -l`). Omitted
# owners default to the Primary User (the first declared user). Empty when no
# user can own the pool (a host with no declared users).
pool_owners_base() {
  local owners="$1" users="$2"
  if [[ -z "$owners" ]]; then
    printf '%s' "${users%% *}"
    return
  fi
  # The nominal owner is the first listed *user* (a @group can't own a dir).
  local tok
  for tok in $owners; do
    [[ "$tok" == @* ]] || { printf '%s' "$tok"; return; }
  done
}

# Users with access to the pool — one per line. Each gets a ~/Disks/<pool>
# symlink. Omitted owners grant access to just the Primary User; a userless
# host grants access to no one.
pool_owners_access_users() {
  local owners="$1" users="$2" groupmap="$3"
  if [[ -z "$owners" ]]; then
    [[ -n "$users" ]] && printf '%s\n' "${users%% *}"
    return 0
  fi
  # Union of listed users and the members of listed @groups, in order, deduped.
  local out=() tok m
  for tok in $owners; do
    if [[ "$tok" == @* ]]; then
      for m in $(_pool_owners_group_members "${tok#@}" "$groupmap"); do
        _pool_owners_in_list "$m" "${out[*]}" || out+=("$m")
      done
    else
      _pool_owners_in_list "$tok" "${out[*]}" || out+=("$tok")
    fi
  done
  ((${#out[@]})) && printf '%s\n' "${out[@]}"
  return 0
}

# Space-separated members of <group> from the "group:m1,m2 group2:m3" <map>.
_pool_owners_group_members() {
  local g="$1" map="$2" pair
  for pair in $map; do
    [[ "$pair" == "${g}:"* ]] && { printf '%s' "${pair#*:}" | tr ',' ' '
      return; }
  done
}

# setfacl entries for an ACL pool — one per line. Each listed user gets
# u:<user>:rwx, each @group g:<group>:rwx, every entry mirrored as a default
# ACL (d:...) so newly created files inherit the grant, plus the ACL mask set
# to rwx (m::rwx + d:m::rwx) so the named grants are effective (ADR 0031).
pool_owners_acl_entries() {
  local owners="$1" tok
  for tok in $owners; do
    if [[ "$tok" == @* ]]; then
      printf 'g:%s:rwx\n' "${tok#@}"
    else
      printf 'u:%s:rwx\n' "$tok"
    fi
  done
  for tok in $owners; do
    if [[ "$tok" == @* ]]; then
      printf 'd:g:%s:rwx\n' "${tok#@}"
    else
      printf 'd:u:%s:rwx\n' "$tok"
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
pool_owners_validate() {
  local owners="$1" users="$2" groupmap="$3" tok members
  [[ -n "$owners" ]] || return 0
  for tok in $owners; do
    if [[ "$tok" == @* ]]; then
      members="$(_pool_owners_group_members "${tok#@}" "$groupmap")"
      [[ -n "${members// }" ]] || {
        printf '%s' "group '${tok#@}' has no declared members"
        return 1
      }
    else
      _pool_owners_in_list "$tok" "$users" || {
        printf '%s' "owner '${tok}' is not a declared user"
        return 1
      }
    fi
  done
  return 0
}

# 0 when <needle> appears in the space-separated <haystack>.
_pool_owners_in_list() {
  local needle="$1" hay="$2" w
  for w in $hay; do
    [[ "$w" == "$needle" ]] && return 0
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
  local e="$1" pre name perm id
  case "$e" in
  d:u:*) pre="d:u"; name="${e#d:u:}" ;;
  d:g:*) pre="d:g"; name="${e#d:g:}" ;;
  u:*)   pre="u";   name="${e#u:}" ;;
  g:*)   pre="g";   name="${e#g:}" ;;
  *)     printf '%s' "$e"; return 0 ;;   # m::rwx / d:m::rwx — no name
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
  local mount="$1" topo="$2" dc="$3"
  if [[ "$topo" == "independent" ]]; then
    local k
    for ((k = 1; k <= dc; k++)); do printf '%s/disk%s\n' "$mount" "$k"; done
  else
    printf '%s\n' "$mount"
  fi
}

# chown/ACL one mounted path under the altroot to its owners. Returns non-zero
# (no change) when the base owner can't be resolved in the installed passwd.
_pool_owners_own_path() {
  local mount="$1" owners="$2" users="$3" groupmap="$4"
  local target="${MOUNT_ROOT}${mount}"
  local base buid bgid
  base="$(pool_owners_base "$owners" "$users")"
  buid="$(_pool_owners_uid "$base")"
  bgid="$(_pool_owners_user_gid "$base")"
  [[ -n "$buid" ]] || {
    warn "Owner '${base:-<none>}' is not in the installed passwd —" \
      "leaving ${mount} root-owned."
    return 1; }
  chown "${buid}:${bgid}" "$target"
  chmod 0755 "$target"
  if [[ "$(pool_owners_mode "$owners" "$users" "$groupmap")" == "acl" ]]; then
    # The base chown above gives a human user-owner (so `ls -l` shows a name);
    # the named ACL grants are what actually share the pool.
    local e ne
    while IFS= read -r e; do
      [[ -n "$e" ]] || continue
      ne="$(_pool_owners_acl_to_numeric "$e")"
      [[ -n "$ne" ]] && setfacl -m "$ne" "$target"
    done < <(pool_owners_acl_entries "$owners")
  fi
}

# Create ~/Disks/<label> → <target> for every user with access, owned by them.
# <target> is the runtime path (the pool/group mountpoint), so it resolves on
# the booted system regardless of the altroot.
_pool_owners_link() {
  local label="$1" target="$2" owners="$3" users="$4" groupmap="$5"
  local home_base="${POOL_OWNERS_HOME_BASE:-/home}"
  local u uid gid home disks
  while IFS= read -r u; do
    [[ -n "$u" ]] || continue
    uid="$(_pool_owners_uid "$u")"
    [[ -n "$uid" ]] || {
      warn "Pool '${label}': user '${u}' is not in the installed passwd —" \
        "no ~/Disks/${label} symlink."
      continue; }
    gid="$(_pool_owners_user_gid "$u")"
    home="$(_pool_owners_home "$u")"; home="${home:-${home_base}/${u}}"
    disks="${MOUNT_ROOT}${home}/Disks"
    mkdir -p "$disks"
    ln -sfn "$target" "${disks}/${label}"
    chown -h "${uid}:${gid}" "${disks}/${label}"
    chown "${uid}:${gid}" "$disks"
  done < <(pool_owners_access_users "$owners" "$users" "$groupmap")
}

# Own every (child) mountpoint of a pool/group and create one ~/Disks/<label>
# symlink to its top mountpoint.
#   $1 label   ~/Disks basename + log name
#   $2 mount   top mountpoint (symlink target)
#   $3 topo    topology (independent → per-disk children)
#   $4 dc      disk count (children for independent)
#   $5 owners / $6 users / $7 groupmap  (resolver inputs)
_pool_owners_apply_pool() {
  local label="$1" mount="$2" topo="$3" dc="$4"
  local owners="$5" users="$6" groupmap="$7"
  if [[ "$(pool_owners_mode "$owners" "$users" "$groupmap")" == "root" ]]; then
    warn "Pool '${label}' (${mount}) has no user to own it — left" \
      "root-owned. Declare a user or an 'owners' list to fix."
    return 0
  fi
  local m
  while IFS= read -r m; do
    [[ -d "${MOUNT_ROOT}${m}" ]] || { info "Skip ${m} — not mounted."; continue; }
    _pool_owners_own_path "$m" "$owners" "$users" "$groupmap" || true
  done < <(_pool_owners_group_mounts "$mount" "$topo" "$dc")
  _pool_owners_link "$label" "$mount" "$owners" "$users" "$groupmap"
}

# Apply ownership to one single-mount pool + its ~/Disks symlink. Thin wrapper
# over _pool_owners_apply_pool for the common (non-independent) case.
#   $1 label  $2 mount  $3 owners  $4 users  $5 groupmap
pool_owners_apply_mount() {
  _pool_owners_apply_pool "$1" "$2" stripe 1 "$3" "$4" "$5"
}

# Declared usernames (Primary User first), space-separated, read from the
# assembled effective config (ADR 0036 — the same source the Runner consumes,
# not the legacy per-host config.jsonc). Empty on a host that declares no users.
_pool_owners_declared_users() {
  local arr=() u
  while IFS= read -r u; do
    [[ -n "$u" ]] && arr+=("$u")
  done < <(jsonc_read "$CONFIG_FILE" '.users[]?' 2>/dev/null)
  printf '%s' "${arr[*]}"
}

# Group→members map as "group:m1,m2 ..." for @group resolution/validation. A
# declared user is a member of every group in their effective group set
# (resolve_user_groups — includes wheel for sudo users), sourced from User
# Config so membership stays dynamic (ADR 0031). Empty when nothing is
# declared. Glue around the configs loader; covered by the VM smoke test.
_pool_owners_group_map() {
  local users u uj g out=()
  declare -A members=()
  users="$(_pool_owners_declared_users)"
  for u in $users; do
    uj="$(load_user_config "$u" 2>/dev/null)" || continue
    for g in $(resolve_user_groups "$uj" 2>/dev/null | tr ',' ' '); do
      [[ -n "$g" ]] || continue
      if [[ -n "${members[$g]:-}" ]]; then members[$g]+=",$u"
      else members[$g]="$u"; fi
    done
  done
  for g in "${!members[@]}"; do out+=("${g}:${members[$g]}"); done
  printf '%s' "${out[*]}"
}

# owners (space-separated) for the declarative data_pool named <name>, or empty
# when no such config entry exists (e.g. an interactively-synthesized pool,
# which defaults to the Primary User).
_pool_owners_data_pool_owners_by_name() {
  local want="$1" n i nm
  n="$(install_config_data_pools_count)"
  for ((i = 0; i < n; i++)); do
    nm="$(install_config_data_pool_name "$i")"
    [[ "$nm" == "$want" ]] || continue
    install_config_data_pool_owners "$i" | tr '\n' ' '
    return
  done
}

# 0 if an interactively-folded leftover OS-disk pool exists in layout state,
# 1 otherwise. _LAYOUT_IMPL_STORAGE_PARTS is a layout-MULTI global; in
# single-disk mode it is never declared, so a bare `[[ -v arr[_leftover] ]]`
# would arithmetic-evaluate the subscript and abort the install under `set -u`
# ("_leftover: unbound variable"). The `declare -p` guard short-circuits before
# the subscript is touched, so the check is safe when the array is absent.
_pool_owners_has_leftover() {
  declare -p _LAYOUT_IMPL_STORAGE_PARTS &>/dev/null || return 1
  [[ -v _LAYOUT_IMPL_STORAGE_PARTS[_leftover] ]]
}

# Orchestrator: make every data-pool mountpoint usable by its owner(s) and
# create the ~/Disks/<pool> symlinks. Runs install-time after the Runner
# created users/groups, on the host against the altroot-mounted pools (ADR
# 0031). Covers Standalone Data Pools (declarative + interactive), the Combined
# Data Pool's per-Storage-Group datasets, and folded leftover OS disks.
pool_owners_apply() {
  section "Applying Data-Pool Ownership"
  local users; users="$(_pool_owners_declared_users)"
  local groupmap; groupmap="$(_pool_owners_group_map)"

  # ── Standalone Data Pools — from layout state, so interactively-synthesized
  # leftover→own-pool pools are covered (owners default to the Primary User).
  # A standalone pool is always a single <name>/data mountpoint (ADR 0027
  # rejects independent/none for standalone).
  local nm mount owners
  for nm in "${_LAYOUT_IMPL_DATA_POOL_NAMES[@]:-}"; do
    [[ -n "$nm" ]] || continue
    mount="${_LAYOUT_IMPL_DATA_POOL_MOUNT[$nm]}"
    owners="$(_pool_owners_data_pool_owners_by_name "$nm")"
    _pool_owners_apply_pool "$nm" "$mount" stripe 1 "$owners" "$users" "$groupmap"
  done

  # ── Combined Data Pool — one dataset per declared Storage Group. Topology is
  # the resolved runtime choice (covers interactive selection); independent
  # groups expand to per-disk child datasets.
  local sg i name topo dc
  sg="$(jsonc "$CONFIG_FILE" | jq '.storage_groups | length')"
  for ((i = 0; i < sg; i++)); do
    name="$(cfg ".storage_groups[$i].name")"
    mount="$(cfg ".storage_groups[$i].mount")"
    owners="$(install_config_storage_group_owners "$i" | tr '\n' ' ')"
    topo="${_LAYOUT_IMPL_TOPOLOGIES[$name]:-$(cfgo ".storage_groups[$i].topology")}"
    topo="${topo:-stripe}"
    dc="$(jsonc "$CONFIG_FILE" | jq ".storage_groups[$i].disks | length")"
    _pool_owners_apply_pool "$name" "$mount" "$topo" "$dc" \
      "$owners" "$users" "$groupmap"
  done

  # ── Folded leftover OS disks → dpool/DATA/extra (interactive, no config
  # entry) — default to the Primary User. Topology mirrors create_multi_dpool's
  # leftover default (independent).
  if _pool_owners_has_leftover; then
    local lparts ltopo ldc
    lparts="${_LAYOUT_IMPL_STORAGE_PARTS[_leftover]}"
    ltopo="${_LAYOUT_IMPL_TOPOLOGIES[_leftover]:-independent}"
    ldc="$(wc -w <<< "$lparts")"
    _pool_owners_apply_pool extra /data/extra "$ltopo" "$ldc" \
      "" "$users" "$groupmap"
  fi

  info "Data-pool ownership applied."
}
