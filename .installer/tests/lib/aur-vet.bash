# bats `load` helper for the aur-vet suites (ADR 0143). Builds fixture AUR
# clones as real git repos — the shape paru hands PreBuildCommand — and runs
# the real command against an isolated data dir and allowlist store.

AUR_VET_SRC="$BATS_TEST_DIRNAME/../../aur"
AUR_VET_FIXTURES="$BATS_TEST_DIRNAME/../fixtures/aur"
# The Atomic Arch deps payload hash (indicators.tsv, ioctl).
_AURVET_PAYLOAD=6144d433f8a0316869877b5f834c801251bbb936e5f1577c5680878c7443c98b
# A Monero wallet address (95 chars), for the miner rule.
_AURVET_XMR=44AFFq5kSiGBoZ4NMDwYtN18obc8AemS33DBLWs3H7otXft3
_AURVET_XMR+=XjrpDtQGv7SqSsaBYBb98uNbr2VBBEt7f2wfn3RVGQBEP3A

aur_vet_setup() {
  T="$(mktemp -d)"
  export AUR_VET_DATA="$T/data" AUR_VET_STORE="$T/store"
  mkdir -p "$AUR_VET_DATA" "$AUR_VET_STORE"
  cp "$AUR_VET_SRC"/*.tsv "$AUR_VET_DATA/"
  # An empty allowlist: fixtures opt into accepted rules explicitly.
  : > "$AUR_VET_STORE/allow.tsv"
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
  # Trust signals come from fixtures, never the network; retries never wait.
  export AUR_VET_RPC_FIXTURE_DIR="$T/rpc" AUR_VET_RETRY_DELAYS=0,0
  mkdir -p "$AUR_VET_RPC_FIXTURE_DIR"
}

aur_vet_teardown() { rm -rf "$T"; }

# Copy fixture <name> into a fresh git clone at $T/clone/<name>; commit it as
# <author> (default fixture-maintainer). Prints the clone dir.
aur_vet_clone() {
  local name="$1" author="${2:-fixture-maintainer}" clone_directory="$T/clone/$1"
  mkdir -p "$clone_directory"
  cp -r "$AUR_VET_FIXTURES/$name/." "$clone_directory/"
  git -C "$clone_directory" init -q
  git -C "$clone_directory" add -A
  git -C "$clone_directory" -c user.name="$author" -c user.email="$author@aur" \
    commit -q -m "init"
  printf '%s\n' "$clone_directory"
}

# Run the hook the way paru does: cwd = clone, $PKGBASE set.
aur_vet_hook() {
  local clone_directory="$1" base="${2:-${1##*/}}"
  _aur_vet_default_rpc "$base"
  run bash -c 'cd "$1" && PKGBASE="$2" "$3"' _ "$clone_directory" "$base" \
    "$AUR_VET_SRC/aur-vet"
}

# A reviewed-looking default RPC answer unless the test wrote its own.
_aur_vet_default_rpc() {
  [[ -n "${AURVET_NO_RPC:-}" || -e "$AUR_VET_RPC_FIXTURE_DIR/$1.json" ]] \
    || aur_vet_rpc "$1"
}

# Inject <text> into a fresh copy of the rulecase fixture per <placement> (see
# fixtures/aur/rule-cases.tsv), commit, and print the clone dir. Text goes via
# ENVIRON so awk never interprets its backslashes.
aur_vet_case() {
  local placement="$1" text="$2" clone_directory="$T/clone/${3:-case}"
  text="${text//@BLOB@/$(printf 'QUJD%.0s' {1..30})}"
  text="${text//@XMR@/$_AURVET_XMR}"
  text="${text//@PAYLOAD@/$_AURVET_PAYLOAD}"
  local when=""
  [[ "$placement" == pkgbase && "$text" == *@* ]] && when="${text#*@}"
  rm -rf "$clone_directory"; mkdir -p "$clone_directory"
  cp -r "$AUR_VET_FIXTURES/rulecase/." "$clone_directory/"
  local pkgbuild="$clone_directory/PKGBUILD" srcinfo="$clone_directory/.SRCINFO" sum
  _aur_vet_ins() { # <file> <after-ERE> <line>: insert after first match
    L="$3" awk -v re="$2" \
      '{ print } !d && $0 ~ re { print ENVIRON["L"]; d = 1 }' \
      "$1" > "$1.new" && mv "$1.new" "$1"
  }
  case "$placement" in
    build) _aur_vet_ins "$pkgbuild" '^  make$' "  $text" ;;
    install)
      _aur_vet_ins "$pkgbuild" '^license=' 'install=rulecase.install'
      printf 'post_install() {\n  %s\n}\n' "$text" > "$clone_directory/rulecase.install" ;;
    top) _aur_vet_ins "$pkgbuild" '^license=' "$text" ;;
    file) printf '#!/bin/sh\n%s\n' "$text" > "$clone_directory/helper.sh" ;;
    source | source-skip)
      sum=3333333333333333333333333333333333333333333333333333333333333333
      [[ "$placement" == source-skip ]] && sum=SKIP
      [[ "$text" == *@SHA=* ]] && \
        { sum="${text#*@SHA=}"; text="${text%@SHA=*}"; }
      _aur_vet_ins "$pkgbuild" '^source=' "source+=(\"$text\")"
      _aur_vet_ins "$pkgbuild" '^sha256sums=' "sha256sums+=('$sum')"
      _aur_vet_ins "$srcinfo" '^\tsource = ' "	source = $text"
      _aur_vet_ins "$srcinfo" '^\tsha256sums = ' "	sha256sums = $sum" ;;
    nosrcinfo) rm -f "$srcinfo" ;;
    heredoc | shheredoc)
      local command=cat; [[ "$placement" == shheredoc ]] && command=sh
      _aur_vet_ins "$pkgbuild" '^license=' 'install=rulecase.install'
      printf 'post_install() {\n%s << EOF\n%s\nEOF\n}\n' "$command" "$text" \
        > "$clone_directory/rulecase.install" ;;
    srcvar) # a host hidden behind a variable; .SRCINFO shows a benign one
      _aur_vet_ins "$pkgbuild" '^license=' "_h=$text"
      _aur_vet_ins "$pkgbuild" '^source=' 'source+=("https://${_h}/rulecase/p.tgz")'
      _aur_vet_ins "$pkgbuild" '^sha256sums=' "sha256sums+=('SKIP')"
      _aur_vet_ins "$srcinfo" '^\tsource = ' \
        "	source = https://github.com/rulecase/p.tgz"
      _aur_vet_ins "$srcinfo" '^\tsha256sums = ' "	sha256sums = SKIP" ;;
    binary) printf '\x89PNG\0\1' > "$clone_directory/icon.png" ;;
    path) # "<relpath>::<content>": a tracked file at that path
      mkdir -p "$clone_directory/$(dirname "${text%%::*}")"
      printf '%s\n' "${text#*::}" > "$clone_directory/${text%%::*}" ;;
    sums) # "<algo>[:SKIP]": swap the sha256 algorithm (and digest)
      sed -i "s/sha256sums/${text%%:*}sums/" "$pkgbuild" "$srcinfo"
      [[ "$text" == *:SKIP ]] && sed -i "s/2\{64\}/SKIP/" "$pkgbuild" "$srcinfo" ;;
    srcinfo) _aur_vet_ins "$srcinfo" '^\tsource = ' "	$text" ;;
    nulpkgbuild) printf '# \0\n' >> "$pkgbuild" ;;
    pkgbase) ;;
    *) echo "unknown placement: $placement" >&2; return 1 ;;
  esac
  git -C "$clone_directory" init -q
  git -C "$clone_directory" add -A
  GIT_COMMITTER_DATE="$when" GIT_AUTHOR_DATE="$when" \
    git -C "$clone_directory" -c user.name=m -c user.email=m@aur commit -q -m case
  printf '%s\n' "$clone_directory"
}

# Commit a change in <dir>: <file> gets <sed-expr> applied.
aur_vet_commit() {
  local dir="$1" file="$2" expr="$3"
  sed -i "$expr" "$dir/$file"
  git -C "$dir" -c user.name=m -c user.email=m@aur commit -q -am change
}

# Interactive run: answers on stdin.
aur_vet_hook_answer() {
  local dir="$1" answer="$2" base="${3:-$(basename "$1")}"
  _aur_vet_default_rpc "$base"
  run bash -c 'cd "$1" && printf "%s\n" "$4" | AUR_VET_INTERACTIVE=1 \
    PKGBASE="$2" "$3"' _ "$dir" "$base" "$AUR_VET_SRC/aur-vet" "$answer"
}

# AUR RPC fixture for <pkgbase> (ADR 0143): one `info` result. Args are
# jq-style overrides, e.g. Maintainer=evil NumVotes=0 (values are JSON).
aur_vet_rpc() {
  local base="$1"; shift
  local now; now="$(date +%s)"
  local j
  j="$(jq -n --arg b "$base" --argjson t "$((now - 400 * 86400))" '{
    Name: $b, PackageBase: $b, Maintainer: "fixture-maintainer",
    Submitter: "fixture-maintainer", FirstSubmitted: $t, LastModified: $t,
    OutOfDate: null, NumVotes: 100 }')"
  local kv
  for kv in "$@"; do
    j="$(jq --arg k "${kv%%=*}" --argjson v "${kv#*=}" '.[$k] = $v' <<<"$j")"
  done
  jq -n --argjson r "$j" '{ resultcount: 1, results: [$r], type: "multiinfo",
    version: 5 }' > "$AUR_VET_RPC_FIXTURE_DIR/$base.json"
}
