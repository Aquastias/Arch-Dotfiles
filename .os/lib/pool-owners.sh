#!/usr/bin/env bash
# =============================================================================
# lib/pool-owners.sh — Owners Resolver (pure) + Owners Applier (thin I/O)
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
# OWNERS APPLIER (thin I/O)
# =============================================================================
# Operates on the new system mounted under ${MOUNT_ROOT}. POOL_OWNERS_HOME_BASE
# overrides the home root (defaults to /home) for tests.

# Apply ownership to one mountpoint and create the ~/Disks/<label> symlink in
# each access-user's home.
#   $1 label    symlink basename under ~/Disks (pool or storage-group name)
#   $2 mount    runtime mountpoint (e.g. /data/tank0) — also the symlink target
#   $3 owners   owners tokens ("" = omitted)
#   $4 users    declared usernames, Primary User first
#   $5 groupmap "group:member1,member2" pairs ("" when none)
pool_owners_apply_mount() {
  local label="$1" mount="$2" owners="$3" users="$4" groupmap="$5"
  local home_base="${POOL_OWNERS_HOME_BASE:-/home}"
  local mode base
  mode="$(pool_owners_mode "$owners" "$users" "$groupmap")"
  base="$(pool_owners_base "$owners" "$users")"

  if [[ "$mode" == "root" ]]; then
    warn "Data pool '${label}' (${mount}) has no user to own it —" \
      "left root-owned. Declare a user or an 'owners' list to fix."
    return 0
  fi

  local target="${MOUNT_ROOT}${mount}"
  if [[ "$mode" == "chown" ]]; then
    chown "${base}:${base}" "$target"
    chmod 0755 "$target"
  elif [[ "$mode" == "acl" ]]; then
    # Nominal user-owner is the first listed user (so `ls -l` shows a human);
    # the named ACL grants are what actually share the pool.
    [[ -n "$base" ]] && chown "${base}:${base}" "$target"
    chmod 0755 "$target"
    local e
    while IFS= read -r e; do
      [[ -n "$e" ]] && setfacl -m "$e" "$target"
    done < <(pool_owners_acl_entries "$owners")
  fi

  # ~/Disks/<label> → the runtime mountpoint, for every user with access.
  local u home disks
  while IFS= read -r u; do
    [[ -n "$u" ]] || continue
    home="${MOUNT_ROOT}${home_base}/${u}"
    disks="${home}/Disks"
    mkdir -p "$disks"
    ln -sfn "$mount" "${disks}/${label}"
    chown -h "${u}:${u}" "${disks}/${label}"
    chown "${u}:${u}" "$disks"
  done < <(pool_owners_access_users "$owners" "$users" "$groupmap")
}

# Declared usernames (Primary User first), space-separated, read from the
# resolved host config. Empty on a host that declares no users.
_pool_owners_declared_users() {
  local arr=() u
  while IFS= read -r u; do
    [[ -n "$u" ]] && arr+=("$u")
  done < <(load_host_config "$RESOLVED_HOST_PROFILE" 2>/dev/null \
    | jq -r '.users[]?' 2>/dev/null)
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

# Orchestrator: make every data-pool mountpoint usable by its owner(s) and
# create the ~/Disks/<pool> symlinks. Runs install-time inside the new root
# (after the Runner created users/groups, while pools are mounted under the
# altroot), so it survives a first-boot import hiccup (ADR 0031). Covers both
# Combined Data Pool datasets (per Storage Group) and Standalone Data Pools.
pool_owners_apply() {
  section "Applying Data-Pool Ownership"
  local users; users="$(_pool_owners_declared_users)"
  local groupmap; groupmap="$(_pool_owners_group_map)"

  local sg i name mount owners target
  sg="$(jsonc "$CONFIG_FILE" | jq '.storage_groups | length')"
  for ((i = 0; i < sg; i++)); do
    name="$(cfg ".storage_groups[$i].name")"
    mount="$(cfg ".storage_groups[$i].mount")"
    owners="$(install_config_storage_group_owners "$i" | tr '\n' ' ')"
    target="${MOUNT_ROOT}${mount}"
    [[ -d "$target" ]] || { info "Skip group '${name}': ${mount} not mounted."
      continue; }
    pool_owners_apply_mount "$name" "$mount" "$owners" "$users" "$groupmap"
  done

  local dp; dp="$(install_config_data_pools_count)"
  for ((i = 0; i < dp; i++)); do
    name="$(install_config_data_pool_name "$i")"
    mount="$(install_config_data_pool_mount "$i")"
    owners="$(install_config_data_pool_owners "$i" | tr '\n' ' ')"
    target="${MOUNT_ROOT}${mount}"
    [[ -d "$target" ]] || { info "Skip pool '${name}': ${mount} not mounted."
      continue; }
    pool_owners_apply_mount "$name" "$mount" "$owners" "$users" "$groupmap"
  done

  info "Data-pool ownership applied."
}
