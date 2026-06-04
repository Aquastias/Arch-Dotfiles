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
}

# Users with access to the pool — one per line. Each gets a ~/Disks/<pool>
# symlink. Omitted owners grant access to just the Primary User; a userless
# host grants access to no one.
pool_owners_access_users() {
  local owners="$1" users="$2"
  if [[ -z "$owners" ]]; then
    [[ -n "$users" ]] && printf '%s\n' "${users%% *}"
    return 0
  fi
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

# Orchestrator: make every data-pool mountpoint usable by its owner(s) and
# create the ~/Disks/<pool> symlinks. Runs install-time inside the new root
# (after the Runner created users/groups, while pools are mounted under the
# altroot), so it survives a first-boot import hiccup (ADR 0031). Covers both
# Combined Data Pool datasets (per Storage Group) and Standalone Data Pools.
pool_owners_apply() {
  section "Applying Data-Pool Ownership"
  local users; users="$(_pool_owners_declared_users)"
  local groupmap=""  # populated for @group ACLs (slice 04)

  # owners is always omitted in this slice (the `owners` field arrives with the
  # schema in issue 03); every pool defaults to the Primary User.
  local sg i name mount owners="" target
  sg="$(jsonc "$CONFIG_FILE" | jq '.storage_groups | length')"
  for ((i = 0; i < sg; i++)); do
    name="$(cfg ".storage_groups[$i].name")"
    mount="$(cfg ".storage_groups[$i].mount")"
    target="${MOUNT_ROOT}${mount}"
    [[ -d "$target" ]] || { info "Skip group '${name}': ${mount} not mounted."
      continue; }
    pool_owners_apply_mount "$name" "$mount" "$owners" "$users" "$groupmap"
  done

  local dp; dp="$(install_config_data_pools_count)"
  for ((i = 0; i < dp; i++)); do
    name="$(install_config_data_pool_name "$i")"
    mount="$(install_config_data_pool_mount "$i")"
    target="${MOUNT_ROOT}${mount}"
    [[ -d "$target" ]] || { info "Skip pool '${name}': ${mount} not mounted."
      continue; }
    pool_owners_apply_mount "$name" "$mount" "$owners" "$users" "$groupmap"
  done

  info "Data-pool ownership applied."
}
