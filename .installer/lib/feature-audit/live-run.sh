#!/usr/bin/env bash
# =============================================================================
# lib/feature-audit/live-run.sh — Audit Cache, install, variant + run loop
# =============================================================================
# Part of the live Audit Run (lib/feature-audit/live.sh, ADR 0152).
#
# Used by: lib/feature-audit/live.sh (sources it).
# =============================================================================

# ── Audit Cache (ADR 0152) ───────────────────────────────────────────────────
# The uncached base variant fills it (repo packages + its built AUR packages
# as the [audit-aur] repo); every later install of the run is pointed at it
# through the harness HTTP root. Base still exercises the real mirrors, AUR
# builds and AUR Vetting.

FA_CACHE_SOURCE=base   # the variant that installs uncached and fills it

feature_audit_cache_directory() { printf '%s\n' "$CACHE_DIR/audit-cache"; }

# feature_audit_cache_install_env <variant-id> — the test-only install env (K=V
# list).
feature_audit_cache_install_env() {
  local cache_directory url
  cache_directory="$(feature_audit_cache_directory)"
  url="http://$LIBVIRT_GATEWAY:$HTTP_PORT/audit-cache"
  if [[ "$1" == "$FA_CACHE_SOURCE" ]]; then
    echo INSTALL_PKG_CACHE_KEEP=1; return
  fi
  compgen -G "$cache_directory/pkg/*.pkg.tar.zst" >/dev/null || return 0
  printf '%s' "INSTALL_PKG_CACHE_SERVER=$url/pkg"
  [[ -e "$cache_directory/aur/audit-aur.db" ]] \
    && printf ' %s' "INSTALL_AUDIT_AUR_URL=$url/aur"
  echo
}

# feature_audit_cache_harvest — after base's boot1: copy its kept repo packages
# and its built AUR packages to the host, index the AUR ones as [audit-aur],
# then clear the guest's pacman cache (the shipped state the install would
# leave). A failed copy drops the cache: the rest install uncached, never from a
# partial set.
feature_audit_cache_harvest() {
  local cache_directory ok=1; cache_directory="$(feature_audit_cache_directory)"
  mkdir -p "$cache_directory/pkg" "$cache_directory/aur"
  feature_audit_agent sudo <<'SH' | tar -xf - -C "$cache_directory/pkg" || ok=0
# with its .sig: a cache hit lacking one fails the whole transaction
cd /var/cache/pacman/pkg && for p in *.pkg.tar.zst; do
  [ -f "$p.sig" ] && printf '%s\n%s\n' "$p" "$p.sig"
done | tar -cf - -T -
SH
  ((PIPESTATUS[0] == 0)) || ok=0
  feature_audit_agent sudo <<'SH' | tar -xf - -C "$cache_directory/aur" || ok=0
cd / && find home root -path '*/.cache/paru/clone/*' -name '*.pkg.tar.zst' \
  ! -name '*-debug-*' | tar -cf - -T - --transform 's|.*/||'
SH
  ((PIPESTATUS[0] == 0)) || ok=0
  if compgen -G "$cache_directory/aur/*.pkg.tar.zst" >/dev/null; then
    repo-add -q "$cache_directory/aur/audit-aur.db.tar.gz" \
      "$cache_directory/aur"/*.pkg.tar.zst || ok=0
  fi
  if ((!ok)); then
    # the guest keeps its cache, so a manual retry can still harvest it
    warn "Audit Cache harvest failed; later variants install uncached."
    rm -rf "$cache_directory"; return 0
  fi
  printf '%s\n' 'rm -f /var/cache/pacman/pkg/*.pkg.tar.zst' \
    | feature_audit_agent sudo \
    >/dev/null 2>&1 || true
}

# feature_audit_install <variant-dir> <vm-profile-file> [<variant-id>] — install
# through the persistent flow (Audit Cache env per variant); 0 iff the installer
# exited 0.
feature_audit_install() {
  local directory="$1/install" profile="$2" rc
  mkdir -p "$directory"
  VM_INSTALL_ENV="$(feature_audit_cache_install_env "${3:-}")" \
    VM_ARTIFACT_DIR="$directory" VM_HOLD_FOR_LOG_PULL=1 VM_SKIP_FINAL_BOOT=1 \
    VM_PM=1 \
    REPO_URL="$FA_REPO_URL" \
    bash "$INSTALLER_DIR/vm/vm.sh" --profile "$profile" --recreate \
    > "$directory/harness.txt" 2>&1 || true
  rc="$(cat "$directory/install-rc" 2>/dev/null || echo none)"
  case "$rc" in
    0) return 0 ;;
    none) feature_audit_fatal "$directory" \
            "installer never reported an exit (see harness.txt)" ;;
    124) feature_audit_fatal "$directory" "installer timed out" ;;
    *) feature_audit_fatal "$directory" "installer exited $rc" ;;
  esac
  return 1
}

feature_audit_destroy_vm() {
  feature_audit_serial_stop
  VM_NAME="$VM_NAME" _core_vm_destroy_undefine >/dev/null 2>&1 || true
}

# feature_audit_run_guided <variant-dir> <profile-ref> — the menu-driven path
# runs the disposable guided test flow (install + boot-verify), not the
# persistent one: the guest assembles its config from replayed menu answers.
# Only the install and boot phases apply; it is not agent-controllable.
feature_audit_run_guided() {
  local directory="$1" reference="$2" guided_name rc=0
  guided_name="$(jsonc_strip \
    "$INSTALLER_DIR/tests/vm/profiles/$reference.jsonc" \
    | jq -r .name)"
  mkdir -p "$directory/install" "$directory/boot1"
  LOG_FILE="$directory/install/installer.log" \
    BOOT_LOG_FILE="$directory/boot1/serial.log" REPO_URL="$FA_REPO_URL" \
    CACHE_DIR="$CACHE_DIR" \
    VM_INSTALL_ENV="$(feature_audit_cache_install_env guided)" \
    bash "$INSTALLER_DIR/vm/vm.sh" --guided --profile "$reference" \
    --verify-boot \
    --recreate > "$directory/install/harness.txt" 2>&1 || rc=$?
  ((rc == 0)) || feature_audit_fatal "$directory/install" \
    "guided install or boot-verify failed (vm.sh exit $rc; see harness.txt)"
  VM_NAME="$guided_name" _core_vm_destroy_undefine >/dev/null 2>&1 || true
}

# feature_audit_phase_wanted <variant-dir> <phase> — run this phase?
# FEATURE_AUDIT_SKIP (space list) drops phases silently, for a quick partial run
# while iterating; a phase outside the variant's Variant Phases is recorded as a
# SKIP (never passed, never silent).
feature_audit_phase_wanted() {
  local directory="$1" phase="$2"
  [[ " ${FEATURE_AUDIT_SKIP:-} " != *" $phase "* ]] || return 1
  [[ -z "${FA_VARIANT_PHASES:-}" \
     || " $FA_VARIANT_PHASES " == *" $phase "* ]] && return 0
  mkdir -p "$directory/$phase"
  echo "SKIP phase-$phase not in this variant's Variant Phases" \
    > "$directory/$phase/phase@gate.probe"
  return 1
}

# feature_audit_run_variant <id> <run-dir> — every phase for one variant.
feature_audit_run_variant() {
  local id="$1" run="$2" directory profile config variant
  directory="$run/$id"
  mkdir -p "$directory"
  section "Audit Variant: $id"
  variant="$(feature_audit_variant_json "$id")"
  jq --arg sha "$(git -C "$INSTALLER_DIR" rev-parse HEAD)" \
    --arg at "$(date -Is)" \
    '{variant: .id, adrs: (.adrs // []), commit: $sha, started: $at}' \
    <<<"$variant" > "$directory/variant.json"
  local guided
  guided="$(jq -r '.guided // empty' <<<"$variant")"
  if [[ -n "$guided" ]]; then feature_audit_run_guided "$directory" \
    "$guided"; return; fi
  profile="$directory/vm-profile.json"
  feature_audit_variant_vm_profile "$id" > "$profile" \
    || { feature_audit_fatal "$directory/install" \
    "variant does not resolve"; return 1; }
  config="$(feature_audit_variant_config "$id")" || config='{}'
  # the Fleet gate the probes read (feature_audit_fleet)
  config="$(jq -c \
    --argjson fleet "$(feature_audit_variant_fleet "$id" || echo true)" \
    '. + {_audit: {fleet: $fleet}}' <<<"$config")"
  # shellcheck disable=SC2034 # read by live-phases.sh / live-probes.sh
  FA_USER="$(jq -r '.users[0] // "aquastias"' <<<"$config")"
  FA_VARIANT_PHASES="$(feature_audit_variant_phases "$id")"
  VM_RAM_MB="$(jq -r '.hardware.ram_mb' "$profile")"   # capacity preflight
  export VM_RAM_MB

  _live_bring_up_variant "$directory" "$profile" "$id" || return 1
  feature_audit_collect "$directory/boot1"
  _live_run_phases "$directory" "$config" || return 1
  feature_audit_serial_stop
}

# _live_bring_up_variant <dir> <vm-profile> <id> — install + first boot, or
# with --reuse (FA_REUSE) audit the already-installed VM as it stands
# (iterate on the later phases or re-check a fix without a reinstall).
_live_bring_up_variant() {
  local directory="$1" profile="$2" id="$3"
  if [[ -n "${FA_REUSE:-}" ]]; then
    mkdir -p "$directory/boot1"
    _core_vm_running || feature_audit_vm_start "$directory/boot1" || return 1
    feature_audit_serial_start "$directory/boot1/serial.log"
    feature_audit_wait_ssh "$FA_BOOT_TIMEOUT_SEC" \
      || { feature_audit_fatal "$directory/boot1" "reused VM never reached SSH"
           return 1; }
  else
    feature_audit_install "$directory" "$profile" "$id" || return 1
    feature_audit_boot "$directory/boot1" || return 1
    [[ "$id" == "$FA_CACHE_SOURCE" ]] && feature_audit_cache_harvest
  fi
  return 0
}

# _live_run_phases <dir> <config> — every wanted phase after the first boot;
# rc 1 when a reboot phase loses the VM.
_live_run_phases() {
  local directory="$1" config="$2"
  feature_audit_phase_wanted "$directory" sessions \
    && feature_audit_phase_sessions "$directory" "$config"
  feature_audit_phase_wanted "$directory" probes \
    && feature_audit_phase_probes "$directory" "$config"
  feature_audit_phase_wanted "$directory" keybinds \
    && feature_audit_phase_keybinds "$directory" "$config"
  feature_audit_phase_wanted "$directory" timers \
    && feature_audit_phase_timers "$directory"
  if feature_audit_phase_wanted "$directory" boot2; then
    feature_audit_phase_boot2 "$directory" "$config" || return 1
  fi
  if feature_audit_phase_wanted "$directory" upgrade; then
    feature_audit_phase_upgrade "$directory" || return 1
  fi
  # last: a QEMU virtio-gpu guest can come back from S3 with its compositor
  # / seatd wedged, which would hang every later reboot (base, 20261002)
  feature_audit_phase_wanted "$directory" power \
    && feature_audit_phase_power "$directory"
  return 0
}

# feature_audit_run [--variant X] [--from X] [--keep] [--reuse] — the Audit Run.
feature_audit_run() {
  local only="" from="" keep=0
  while (($#)); do
    case "$1" in
      --variant) only="${2:?}"; shift 2 ;;
      --from)    from="${2:?}"; shift 2 ;;
      --keep)    keep=1; shift ;;
      --reuse)   FA_REUSE=1; keep=1; shift ;;
      *) echo "feature-audit: unknown run option '$1'" >&2; return 2 ;;
    esac
  done
  _core_ensure_libvirt_reachable
  VM_NAME="$(feature_audit_manifest_json | jq -r .vm_name)"
  export VM_NAME
  local -a ids
  mapfile -t ids < <(_live_select_variants "$only" "$from")
  ((${#ids[@]})) || { echo "feature-audit: no variant selected" >&2; return 2; }

  local run; run="$(feature_audit_runs_root)/$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$run"
  info "Audit Run → $run"
  mkdir -p "$run/audit/check"
  feature_audit_check_variant > "$run/audit/check/check.lines" \
    || warn "check found problems (recorded as Findings); running anyway."
  [[ -n "${FA_REUSE:-}" && ${#ids[@]} -ne 1 ]] \
    && { echo "feature-audit: --reuse needs one --variant" >&2; return 2; }
  [[ -n "${FA_REUSE:-}" ]] || FA_REPO_URL="$(feature_audit_stage_repo)"
  local i count=${#ids[@]}
  # the Audit Cache is per run: never reused from an earlier one
  [[ -n "${FA_REUSE:-}" ]] || rm -rf "$(feature_audit_cache_directory)"
  for ((i = 0; i < count; i++)); do
    feature_audit_run_variant "${ids[i]}" "$run" || true
    feature_audit_report "$run" >/dev/null \
      || true   # findings so far, per variant
    feature_audit_serial_stop
    if ((keep && i == count - 1)); then
      info "Keeping VM '$VM_NAME' for inspection (--keep)."
    else
      feature_audit_destroy_vm
    fi
  done
  feature_audit_report "$run"
}

# _live_select_variants <only> <from> — the variant ids to run, one per
# line: just <only> when set, else every id from <from> on (all when empty).
_live_select_variants() {
  local only="$1" from="$2" id started=0
  while IFS= read -r id; do
    if [[ -n "$only" ]]; then [[ "$id" == "$only" ]] && printf '%s\n' "$id"
    elif [[ -n "$from" ]]; then
      [[ "$id" == "$from" ]] && started=1
      ((started)) && printf '%s\n' "$id"
    else printf '%s\n' "$id"; fi
  done < <(feature_audit_variant_ids)
  return 0
}
