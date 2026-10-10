#!/usr/bin/env bash
# =============================================================================
# lib/profiles/runner-aur.sh — the Runner's AUR side
# =============================================================================
# Used by: lib/profiles/runner.sh (sources it). AUR Vetting install + the paru
# hook, the AUR Helper bootstrap ladder (rungs), and per-user AUR installs.
# =============================================================================

# Install AUR Vetting into the target (ADR 0143): the command on PATH, its
# engine + data under /usr/local/share/aur-vet, and the root-owned
# allowlist /etc/aur-vet/allow.tsv seeded from the repo (ADR 0149), plus the
# login check /etc/profile.d/aur-vet.sh (`aur-vet doctor`). Runs before any
# AUR Helper bootstrap, so the very first AUR build is vetted. Mandatory —
# not a Program, never toggled.
runner_install_aur_vet() {
  local source_path="${INSTALLER_DIR}/aur" root="${MOUNT_ROOT}" file
  install -Dm0755 "$source_path/aur-vet" "${root}${_RUNNER_AUR_VET_BIN}"
  install -d -m0755 "$root/usr/local/share/aur-vet" "$root/etc/aur-vet"
  for file in "${_AUR_VET_SHARE_FILES[@]}"; do
    install -m0644 "$source_path/$file" "$root/usr/local/share/aur-vet/$file"
  done
  install -m0644 "$source_path/allow.tsv" "$root/etc/aur-vet/"
  install -Dm0644 "$source_path/profile.d-aur-vet.sh" "$root/etc/profile.d/aur-vet.sh"
}

# Point paru's PreBuildCommand at the vetter in <conf> (a system or per-user
# paru.conf): drop any other PreBuildCommand, set ours under [bin] — the only
# section paru parses it in (src/config.rs parse_bin; under [options] it is
# an "unknown option" and builds run unhooked). paru reads a user's own
# paru.conf *instead of* /etc/paru.conf, so each one must carry the hook
# (ADR 0143). Idempotent; a missing file is a no-op unless `create` is passed
# (the system paru.conf).
runner_wire_paru_hook() {
  local config_file="$1" line="PreBuildCommand = ${_RUNNER_AUR_VET_BIN}"
  [[ "${2:-}" == create && ! -f "$config_file" ]] && : > "$config_file"
  [[ -f "$config_file" ]] || return 0
  awk -v hook="$line" '
    /^[[:space:]]*#?[[:space:]]*PreBuildCommand[[:space:]]*=/ { next }
    { print }
    /^\[bin\][[:space:]]*$/ && !done { print hook; done = 1 }
    END { if (!done) { print ""; print "[bin]"; print hook } }' "$config_file" \
    > "${config_file}.new"
  cat "${config_file}.new" > "$config_file"
  rm -f "${config_file}.new"
}

# Stop <user>'s gpg daemons before leaving the chroot. paru's key fetch starts
# keyboxd, which holds public-keys.d/pubring.db.lock stamped with the ISO
# hostname; it dies with the ISO, and gpg on the installed host can't prove a
# foreign-host lock stale, so every later --recv-keys fails. A clean kill drops
# the lock; the sweep catches one a daemon left anyway (no daemon runs after).
runner_quiesce_gpg() {
  arch-chroot "$MOUNT_ROOT" /usr/bin/bash -s -- "$1" <<'CHROOT_GPG'
USER_NAME="$1"
GNUPG="$(getent passwd "$USER_NAME" | cut -d: -f6)/.gnupg"
[ -d "$GNUPG" ] || exit 0
su - "$USER_NAME" -c 'gpgconf --kill all' >/dev/null 2>&1 || true
find "$GNUPG" -type f \( -name '.#lk*' -o -name '*.lock' \) -delete
CHROOT_GPG
}

# Probe the AUR Helper already installed for <user> inside the chroot. Prints
# `paru`/`yay` (paru preferred) and returns 0 when one exists; non-zero and no
# output when neither does. The in-chroot mirror of aur_helper_detect.
_runner_aur_detect_user_helper() {
  local user="$1"
  # shellcheck disable=SC2016  # $h is expanded by the chroot's shell, not here.
  arch-chroot "$MOUNT_ROOT" su - "$user" -c '
    for h in paru yay; do
      if "$h" --version >/dev/null 2>&1; then echo "$h"; exit 0; fi
    done
    exit 1'
}

# _runner_aur_helper_runs <user> <helper> — rc 0 when <helper> executes for
# <user> in the chroot. A package can install yet not run (paru-bin linked
# against an older libalpm than the system pacman), so a rung only counts once
# this passes.
_runner_aur_helper_runs() {
  local user="$1" helper="$2"
  arch-chroot "$MOUNT_ROOT" su - "$user" -c "${helper} --version" \
    >/dev/null 2>&1
}

# _runner_aur_rung_build_environment <pkg> — env assignments for building
# <pkg>'s rung. The source rung's release profile (LTO, one codegen unit) gets
# OOM-killed on a 4G host; Cargo env overrides the manifest profile, so the
# bootstrap builds without LTO on two jobs. -bin rungs compile nothing and get
# no overrides.
_runner_aur_rung_build_environment() {
  [[ "$1" == paru ]] || return 0
  printf '%s\n' CARGO_PROFILE_RELEASE_LTO=false \
    CARGO_PROFILE_RELEASE_CODEGEN_UNITS=16 CARGO_BUILD_JOBS=2
}

# One rung of the bootstrap ladder: build+install <aur-pkg> as <user> in the
# chroot via git clone + AUR Vetting + makepkg. The helper package is the
# first AUR build, so it is vetted like any other (ADR 0143); the full clone
# keeps HEAD~1 for the Gained Finding comparison (ADR 0149). Returns the
# rung's status. Wrapped in _retry by the ladder and stubbed in unit tests.
_runner_aur_bootstrap_rung() {
  local user="$1" package="$2"
  local environment_lines env
  mapfile -t environment_lines \
    < <(_runner_aur_rung_build_environment "$package")
  env="${environment_lines[*]}"
  arch-chroot "$MOUNT_ROOT" /usr/bin/bash -s -- "$user" "$package" \
    "$_RUNNER_AUR_VET_BIN" "$env" <<'CHROOT_RUNG'
set -e
USER_NAME="$1"; PKG="$2"; VET="$3"; BUILD_ENV="$4"
HOME_DIR="$(getent passwd "$USER_NAME" | cut -d: -f6)"
BUILD="${HOME_DIR}/.aur-helper-bootstrap"
rm -rf "$BUILD"
su - "$USER_NAME" -c "
  set -e
  git clone https://aur.archlinux.org/${PKG}.git '${BUILD}'
  cd '${BUILD}'
  AUR_VET_UNATTENDED=1 PKGBASE='${PKG}' '${VET}'
  env ${BUILD_ENV} makepkg -si --noconfirm
"
rm -rf "$BUILD"
CHROOT_RUNG
}

# Bootstrap an AUR Helper for <user> via the resilience ladder (ADR 0052):
# `paru` source → `paru-bin` → `yay-bin`, each shallow-retried before dropping
# to the next (different) endpoint. Prints the landed helper's name
# (`paru`/`yay`) on stdout; logs go to stderr so the name is cleanly capturable.
# Skips when the user already has a helper. Aborts the install only if every
# rung fails.
runner_bootstrap_helper() {
  local user="$1"
  local existing
  if existing="$(_runner_aur_detect_user_helper "$user")"; then
    info "AUR helper already present for ${user}: ${existing}" >&2
    printf '%s\n' "$existing"
    return 0
  fi
  info "Bootstrapping AUR helper for user: ${user}" >&2
  local package landed
  for package in "${_AUR_HELPER_LADDER[@]}"; do
    # Rung stdout (git clone + makepkg build log) → stderr, so it stays visible
    # on the terminal but never contaminates this function's stdout, which
    # carries only the resolved helper name for the caller's capture.
    if _retry 3 "3,10" -- \
        _runner_aur_bootstrap_rung "$user" "$package" >&2; then
      case "$package" in
        yay-bin) landed=yay ;;
        *)       landed=paru ;;
      esac
      if ! _runner_aur_helper_runs "$user" "$landed"; then
        warn "AUR-helper rung '${package}' installed but ${landed} does not run" \
             "for ${user}; trying next rung." >&2
        continue
      fi
      info "AUR helper bootstrapped via ${package} (${landed}) for ${user}" >&2
      printf '%s\n' "$landed"
      return 0
    fi
    warn "AUR-helper rung '${package}' failed for ${user}; trying next rung." >&2
  done
  error "All AUR-helper bootstrap rungs failed for ${user}" \
        "(paru, paru-bin, yay-bin) — upstream AUR/GitHub may be unavailable."
}

# Resolve + install an AUR set for a user with their <helper>. AUR builds
# need paru: its PreBuildCommand runs AUR Vetting per package base, and yay
# has no such hook, so the yay fallback rung refuses here (ADR 0143). The
# install streams live, the hook unattended. (No `paru -Sp` pre-flight: it
# cannot resolve AUR targets, so it never caught a conflict — ADR 0052.)
runner_aur_install() {
  local user="$1" helper="$2"; shift 2
  local -a packages=("$@")
  ((${#packages[@]} > 0)) || return 0
  aur_helper_vets_aur "$helper" \
    || error "AUR install for ${user} landed on ${helper}: vetting needs paru" \
             "(ADR 0143) — retry once the paru rung can bootstrap."

  # The real install hits aur.archlinux.org/rpc to resolve deps; a transient
  # RPC/network blip there must not abort the whole install (ADR 0052). Retry
  # with backoff — --needed keeps it idempotent, so a re-run skips what landed.
  # A genuine build/conflict failure still aborts after the last try.
  _retry 3 "5,15" -- _runner_aur_paru "$user" /dev/null "${packages[@]}" \
    && return 0

  # The batch still fails: isolate it per package. A package whose sources
  # are unreachable (an upstream outage, not ours) is skipped with a warning;
  # any other failure aborts as before. --needed makes landed ones no-ops.
  local package log; log="$(mktemp)"
  local -a skipped=()
  for package in "${packages[@]}"; do
    _retry 2 "30" -- _runner_aur_paru "$user" "$log" "$package" && continue
    if grep -qE "$_RUNNER_AUR_UNREACHABLE" "$log"; then
      skipped+=("$package"); continue
    fi
    rm -f "$log"
    error "AUR install of ${package} for ${user} failed (see the output above)."
  done
  rm -f "$log"
  ((${#skipped[@]} == 0)) || warn "AUR sources unreachable; skipped for" \
    "${user}: ${skipped[*]} (later: paru -S ${skipped[*]})."
}

# _runner_aur_paru <user> <log> <pkg…> — one unattended paru install,
# streamed live and copied to <log> for the unreachable-source check.
_runner_aur_paru() {
  local user="$1" log="$2"; shift 2
  arch-chroot "$MOUNT_ROOT" su - "$user" -c \
    "AUR_VET_UNATTENDED=1 paru -S --noconfirm --needed $*" 2>&1 | tee "$log"
  return "${PIPESTATUS[0]}"
}

