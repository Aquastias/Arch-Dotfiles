#!/usr/bin/env bash
# =============================================================================
# lib/profiles/runner-user-config.sh — the Runner's per-user config
# =============================================================================
# Used by: lib/profiles/runner.sh (sources it). Dotfiles clone,
# sysctl drop-ins, the Config Apply Pass, and /etc/skel seeding.
# =============================================================================

runner_clone_dotfiles() {
  local user="$1" repo="$2"
  [[ -n "$repo" ]] || return 0
  info "Cloning dotfiles for user: ${user}  (${repo})"
  arch-chroot "$MOUNT_ROOT" /usr/bin/bash -s -- \
    "$user" "$repo" <<'CHROOT_DOTFILES'
set -e
USER_NAME="$1"; REPO="$2"
CLONE_SCRIPT="$(mktemp)"
cat > "$CLONE_SCRIPT" <<CLONE_INNER
set -e
DOTFILES="\${HOME}/.dotfiles"
if [[ -d "\$DOTFILES" ]]; then
  echo "  dotfiles dir exists — skipping" >&2
  exit 0
fi
git clone "${REPO}" "\$DOTFILES"
# ADR 0134: config is applied by the Config Apply pass from the staged tree;
# the installer never stows (ADR 0095). The operator runs ./stow-configs.sh on
# their installed system for live symlinks. This path just places the repo.
CLONE_INNER
# mktemp created the script as root (0600); make it readable so the su'd user
# can run it — otherwise "bash: <tmp>: Permission denied" aborts the install.
# Only reachable once a host sets dotfiles_repo (the VM path exercises it).
chmod 0644 "$CLONE_SCRIPT"
su - "$USER_NAME" -c "bash '$CLONE_SCRIPT'"
rm -f "$CLONE_SCRIPT"
CHROOT_DOTFILES
}

runner_apply_sysctl() {
  local host_json="$1"
  local sysctl_json
  sysctl_json="$(printf '%s' "$host_json" \
    | jq -c '.sysctl // empty' 2>/dev/null)"
  [[ -n "$sysctl_json" ]] || return 0
  info "Writing sysctl defaults to /etc/sysctl.d/99-os.conf"
  mkdir -p "${MOUNT_ROOT}/etc/sysctl.d"
  printf '%s' "$sysctl_json" \
    | jq -r 'to_entries[] | "\(.key) = \(.value)"' \
    > "${MOUNT_ROOT}/etc/sysctl.d/99-os.conf"
}

# _runner_user_config_names_to_relative_paths <names-json> — map a JSON array of
# program names to their "<cat>/<name>" rel paths (one per line), skipping any
# that do not resolve. Shared by the plan and the skel/root seed so the walk
# lives once.
_runner_user_config_names_to_relative_paths() {
  local name relative_path
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    relative_path="$(program_registry_resolve "$name" 2>/dev/null)" || continue
    printf '%s\n' "$relative_path"
  done < <(jq -r '.[]' <<<"$1")
}

# _runner_user_config_plan_relative_paths <user-json> <ships-home-json>
# <sys-progs-json>
#   → the ordered "<cat>/<name>" rel paths whose home/ config applies for this
#   user: (user programs ∪ host programs) that ship a home/ and are not in the
#   user's config_exclude. Pure planning delegated to config_apply_plan.
_runner_user_config_plan_relative_paths() {
  local user_json="$1" ships="$2" sysprogs="$3"
  local selected exclude plan
  selected="$(jq -c -n \
    --argjson u "$(jq -c '.programs // []' <<<"$user_json")" \
    --argjson s "$sysprogs" '$s + $u')"
  exclude="$(jq -c '.config_exclude // []' <<<"$user_json")"
  plan="$(config_apply_plan "$selected" "$ships" "$exclude")"
  _runner_user_config_names_to_relative_paths "$plan"
}

# runner_seed_skeleton_root <selected-home-json> — copy the config of each
# home/-shipping program SELECTED on this host into /etc/skel and /root (the
# machine default, ADR 0095). Scoped to the host's selection (not the whole
# catalog) so a program no user installs never leaves a dangling config under
# /root; not config_exclude-aware, since skel/root is the shared fallback for
# later-created users and for root, which never receives /etc/skel.
runner_seed_skeleton_root() {
  local selected="$1"
  local -a relative_paths=()
  mapfile -t relative_paths \
    < <(_runner_user_config_names_to_relative_paths "$selected")
  ((${#relative_paths[@]})) || return 0
  info "Config Apply: seeding /etc/skel + /root from ${#relative_paths[@]} home/ tree(s)"
  arch-chroot "$MOUNT_ROOT" /usr/bin/bash -s -- \
    "$_RUNNER_RUNTIME_DIR" "${relative_paths[@]}" <<'CHROOT_SKEL'
set -e
RT="$1"; shift
mkdir -p /etc/skel
for rel in "$@"; do
  src="${RT}/programs/${rel}/home"
  [ -d "$src" ] || continue
  cp -a "${src}/." /etc/skel/
  cp -a "${src}/." /root/
done
chown -R root:root /root
CHROOT_SKEL
}

# runner_apply_user_config <user> <user-json> <ships-json> <sys-progs-json>
#   Copy the user's planned home/ trees into their $HOME, then chown to them
#   (cp -a from the root-owned staged tree would otherwise land root-owned).
runner_apply_user_config() {
  local user="$1" user_json="$2" ships="$3" sysprogs="$4"
  local -a relative_paths=()
  mapfile -t relative_paths < <(_runner_user_config_plan_relative_paths \
    "$user_json" "$ships" "$sysprogs")
  ((${#relative_paths[@]})) || { info "User '${user}': no home/ config to apply."; \
    return 0; }
  info "User '${user}': applying ${#relative_paths[@]} program config tree(s) to \$HOME"
  arch-chroot "$MOUNT_ROOT" /usr/bin/bash -s -- \
    "$user" "$_RUNNER_RUNTIME_DIR" "${relative_paths[@]}" <<'CHROOT_APPLYCFG'
set -e
USER_NAME="$1"; RT="$2"; shift 2
HOME_DIR="$(getent passwd "$USER_NAME" | cut -d: -f6)"
for rel in "$@"; do
  src="${RT}/programs/${rel}/home"
  [ -d "$src" ] || continue
  cp -a "${src}/." "${HOME_DIR}/"
done
chown -R "${USER_NAME}:${USER_NAME}" "${HOME_DIR}"
CHROOT_APPLYCFG
}

