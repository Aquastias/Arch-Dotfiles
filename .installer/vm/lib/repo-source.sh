#!/usr/bin/env bash
# =============================================================================
# vm/lib/repo-source.sh — which repo a VM run installs
# =============================================================================
# The guest clones REPO_URL. By default that is the pushed GitHub repo, so a
# run silently tests origin/main, not local commits. REPO_URL=local (vm.sh
# --local, matrix.sh run --local) stages a bare clone of local HEAD under
# CACHE_DIR, which the flow's HTTP server already serves; the guest clones it
# over dumb HTTP. Every run announces its source + commit so a pushed-repo run
# is never mistaken for a local one.
#
# Public API:
#   vm_repo_source_stage_local <directory> <name>  → URL of the staged bare repo
#   vm_repo_source_resolve           REPO_URL=local → staged URL; then announce
#   vm_repo_source_commit <url>      → short commit the URL's HEAD points at
#
# Used by: vm/lib/core.sh, lib/feature-audit/live.sh, lib/matrix/run.sh.
# =============================================================================

# shellcheck source=../../lib/common.sh
[[ "$(type -t info)" == "function" ]] \
  || source "${BASH_SOURCE[0]%/*}/../../lib/common.sh"

: "${LIBVIRT_GATEWAY:=192.168.122.1}"
: "${HTTP_PORT:=9876}"

# vm_repo_source_stage_local <directory> <name> — bare-clone the committed HEAD
# to <directory>/<name> (dumb-HTTP ready); print its URL on the harness HTTP
# root. Uncommitted changes are NOT installed (the guest clones HEAD).
vm_repo_source_stage_local() {
  local directory="$1" name="$2" top destination
  top="$(git -C "$INSTALLER_DIR" rev-parse --show-toplevel)"
  destination="$directory/$name"
  [[ -z "$(git -C "$top" status --porcelain --untracked-files=no)" ]] \
    || warn "Uncommitted changes are NOT installed (the guest clones HEAD)." >&2
  mkdir -p "$directory"
  rm -rf "$destination"
  git clone -q --bare "$top" "$destination"
  git -C "$destination" repack -a -d -q
  git -C "$destination" update-server-info
  printf 'http://%s:%s/%s\n' "$LIBVIRT_GATEWAY" "$HTTP_PORT" "$name"
}

# vm_repo_source_commit <url> — a repo on the harness HTTP root is read from its
# staged bare clone under CACHE_DIR (the server may not be up yet); any other
# URL is asked over the network. Prints "unknown" when neither answers.
vm_repo_source_commit() {
  local url="$1" root commit=""
  root="http://${LIBVIRT_GATEWAY}:${HTTP_PORT}/"
  if [[ "$url" == "$root"* ]]; then
    commit="$(git -C "$CACHE_DIR/${url#"$root"}" rev-parse --short HEAD \
      2>/dev/null)"
  else
    commit="$(GIT_TERMINAL_PROMPT=0 timeout 20 git ls-remote "$url" HEAD \
      2>/dev/null | awk '{ print substr($1, 1, 7) }')"
  fi
  printf '%s\n' "${commit:-unknown}"
}

# vm_repo_source_resolve — turn REPO_URL=local into the staged local HEAD, then
# announce what the guest will install.
vm_repo_source_resolve() {
  if [[ "$REPO_URL" == local ]]; then
    REPO_URL="$(vm_repo_source_stage_local "$CACHE_DIR" local-repo.git)"
  fi
  local commit; commit="$(vm_repo_source_commit "$REPO_URL")"
  if [[ "$REPO_URL" == "http://${LIBVIRT_GATEWAY}:${HTTP_PORT}/"* ]]; then
    info "Repo source: local HEAD ${commit} (${REPO_URL})."
  else
    info "Repo source: ${REPO_URL} at ${commit} — the PUSHED repo; local" \
      "commits are not installed (use --local)."
  fi
}
