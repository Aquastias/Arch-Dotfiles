#!/usr/bin/env bats
# The AUR-helper bootstrap ladder + Runner AUR pass (ADR 0052), in
# lib/profiles/runner.sh. The chroot-executing rung (_profiles_bootstrap_rung)
# and the chroot helper probe (_profiles_detect_user_helper) are stubbed, so
# these assert the pure orchestration: rung ordering, which helper the winning
# rung resolves to, all-rungs-fail abort, the skip path, and the AUR pass
# (real install only, retried). No paru, no arch-chroot.

setup() {
  T="$(mktemp -d)"
  export MOUNT_ROOT=/mnt

  # shellcheck source=../../lib/common.sh
  source "$BATS_TEST_DIRNAME/../../lib/common.sh"
  # shellcheck source=../../lib/config/categorized-list.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/categorized-list.sh"
  # shellcheck source=../../lib/profiles/runner.sh
  source "$BATS_TEST_DIRNAME/../../lib/profiles/runner.sh"

  # Never wait during retry backoff.
  sleep() { :; }
  # Landed helpers run unless a test says otherwise.
  _profiles_helper_runs() { return 0; }
}

teardown() { rm -rf "$T"; }

# ── ladder ordering + resolved helper name ──────────────────────────────────

@test "ladder: rung 1 (paru source) wins → resolves paru" {
  _profiles_detect_user_helper() { return 1; }        # nothing installed yet
  _profiles_bootstrap_rung() { [[ "$2" == paru ]]; }  # only paru succeeds
  local h st
  h="$(_profiles_bootstrap_helper alice 2>/dev/null)"; st=$?
  [ "$st" -eq 0 ]
  [ "$h" = paru ]
}

@test "ladder: paru fails, paru-bin wins → resolves paru" {
  _profiles_detect_user_helper() { return 1; }
  _profiles_bootstrap_rung() { [[ "$2" == paru-bin ]]; }
  local h st
  h="$(_profiles_bootstrap_helper alice 2>/dev/null)"; st=$?
  [ "$st" -eq 0 ]
  [ "$h" = paru ]
}

@test "ladder: chatty rung build output never leaks into the helper name" {
  # Regression: a real rung streams makepkg/cargo output (incl. lines with
  # parens like 'Compiling paru (…/src)' / 'target(s)'). That must not land on
  # the function's stdout, or the captured helper name becomes a multi-line
  # blob that corrupts the downstream `su -c "${helper} -S …"` command.
  _profiles_detect_user_helper() { return 1; }
  _profiles_bootstrap_rung() {
    printf 'Compiling paru v2.1.0 (/home/x/.aur-helper-bootstrap/src/paru)\n'
    printf "   Finished \`release\` profile [optimized] target(s) in 2m\n"
    [[ "$2" == paru ]]
  }
  local h st
  h="$(_profiles_bootstrap_helper alice 2>/dev/null)"; st=$?
  [ "$st" -eq 0 ]
  [ "$h" = paru ]        # exactly the name, no build chatter
}

@test "ladder: only yay-bin succeeds → resolves yay" {
  _profiles_detect_user_helper() { return 1; }
  _profiles_bootstrap_rung() { [[ "$2" == yay-bin ]]; }
  local h st
  h="$(_profiles_bootstrap_helper alice 2>/dev/null)"; st=$?
  [ "$st" -eq 0 ]
  [ "$h" = yay ]
}

@test "ladder: all rungs fail → aborts non-zero" {
  _profiles_detect_user_helper() { return 1; }
  _profiles_bootstrap_rung() { return 1; }   # every rung fails
  # error() exits 1; `run` captures it (repo idiom, cf. profiles-aur.bats).
  run _profiles_bootstrap_helper alice
  [ "$status" -ne 0 ]
}

@test "ladder: tries rungs in order paru → paru-bin → yay-bin" {
  _profiles_detect_user_helper() { return 1; }
  _profiles_bootstrap_rung() { printf '%s\n' "$2" >> "$T/order"; return 1; }
  run _profiles_bootstrap_helper alice
  # Each rung retried 3x; collapse to first-seen order.
  [ "$(awk '!seen[$0]++' "$T/order" | paste -sd, -)" = "paru,paru-bin,yay-bin" ]
}

@test "ladder: skips bootstrap when a helper already exists" {
  _profiles_detect_user_helper() { echo paru; }   # already installed
  _profiles_bootstrap_rung() { echo ran >> "$T/rung"; return 0; }
  local h st
  h="$(_profiles_bootstrap_helper alice 2>/dev/null)"; st=$?
  [ "$st" -eq 0 ]
  [ "$h" = paru ]
  [ ! -f "$T/rung" ]           # no rung executed
}

@test "ladder: a rung whose helper does not run drops to the next rung" {
  # Regression (Audit Run 20260929): paru-bin installed but linked an old
  # libalpm, so every later `paru` call failed. A rung only counts if the
  # helper it landed actually runs.
  _profiles_detect_user_helper() { return 1; }
  _profiles_bootstrap_rung() { [[ "$2" != paru ]]; }   # source rung fails
  _profiles_helper_runs() { [[ "$2" == yay ]]; }       # paru-bin is broken
  local h st
  h="$(_profiles_bootstrap_helper alice 2>/dev/null)"; st=$?
  [ "$st" -eq 0 ]
  [ "$h" = yay ]
}

@test "rung build env: source paru builds without LTO, few jobs" {
  run _profiles_rung_build_env paru
  [ "$status" -eq 0 ]
  [[ "$output" == *CARGO_PROFILE_RELEASE_LTO=false* ]]
  [[ "$output" == *CARGO_BUILD_JOBS=2* ]]
}

@test "rung build env: -bin rungs get no build overrides" {
  run _profiles_rung_build_env paru-bin
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ── AUR pass ────────────────────────────────────────────────────────────────

@test "aur_install: paru runs only the real install (no -Sp pre-flight)" {
  # paru -Sp cannot resolve AUR targets ("target not found"), so the old
  # pre-flight never caught a conflict and warned on every install (Audit Run
  # 20261002). A real conflict surfaces through the install's ERR trap.
  : > "$T/calls"
  arch-chroot() { echo "$*" >> "$T/calls"; }
  _profiles_aur_install alice paru pkg1 pkg2
  [ -z "$(grep -- "-Sp" "$T/calls")" ]
  grep -q "AUR_VET_UNATTENDED=1 paru -S --noconfirm --needed pkg1 pkg2" \
    "$T/calls"
}

@test "aur_install: a transient RPC failure retries the real install" {
  # arch-chroot fails the first two real-install tries, then succeeds — the
  # kind of aur.archlinux.org/rpc blip that used to abort the whole install.
  echo 0 > "$T/n"
  arch-chroot() {
    local n; n=$(< "$T/n"); echo $((n + 1)) > "$T/n"
    (( n >= 2 ))                                        # succeed on 3rd try
  }
  run _profiles_aur_install alice paru pkg1
  [ "$status" -eq 0 ]
  [ "$(< "$T/n")" -eq 3 ]                               # retried to success
}

@test "aur_install: an unreachable source skips just that package, warns" {
  # Regression (Audit Run 20261003): codeberg 503'd through every retry and
  # one package's sources ended the whole install.
  arch-chroot() {
    case "$*" in
      *"--needed pkg1 pkg2"*) return 1 ;;                 # batch fails
      *"--needed pkg2"*) echo "error: failed to download sources for" \
                           "'pkg2-1-1':"; return 1 ;;
      *) return 0 ;;
    esac
  }
  run _profiles_aur_install alice paru pkg1 pkg2
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipped for alice: pkg2"* ]]
}

@test "aur_install: a package failing for another reason still aborts" {
  arch-chroot() {
    case "$*" in
      *"--needed pkg1 pkg2"*) return 1 ;;
      *"--needed pkg2"*) echo "==> ERROR: A failure occurred in build()."
                         return 1 ;;
      *) return 0 ;;
    esac
  }
  run _profiles_aur_install alice paru pkg1 pkg2
  [ "$status" -ne 0 ]
}


# ── user-program install retry ──────────────────────────────────────────────

@test "userprog: heredoc is re-fed on every retry (not EOF after try one)" {
  # The heredoc-fed `bash -s` reads the program script from stdin; a naive
  # heredoc on the _retry line would EOF after try one, so later tries would
  # run an empty script and falsely pass. Fail every try and assert each of
  # the 3 attempts saw the same non-empty script.
  resolve_program() { echo "cat/prog"; }
  arch-chroot() { wc -c >> "$T/sizes"; return 1; }     # consume stdin, fail
  run _profiles_install_user_program alice prog yay
  [ "$status" -ne 0 ]                                   # all tries failed
  [ "$(wc -l < "$T/sizes")" -eq 3 ]                     # ran 3 times
  [ "$(sort -u "$T/sizes" | wc -l)" -eq 1 ]             # every try identical...
  [ "$(sort -u "$T/sizes" | tr -d ' ')" -gt 0 ]         # ...and non-empty
}

@test "userprog: install_user_program retries the chroot on a blip" {
  resolve_program() { echo "cat/prog"; }
  echo 0 > "$T/n"
  arch-chroot() {
    local n; n=$(< "$T/n"); echo $((n + 1)) > "$T/n"
    (( n >= 2 ))                                        # succeed on 3rd try
  }
  run _profiles_install_user_program alice prog yay
  [ "$status" -eq 0 ]
  [ "$(< "$T/n")" -eq 3 ]                               # retried to success
}
