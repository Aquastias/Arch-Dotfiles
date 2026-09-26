# bats `load` helper for the aur-vet suites (ADR 0143). Builds fixture AUR
# clones as real git repos — the shape paru hands PreBuildCommand — and runs
# the real command against an isolated data dir and pin store.

AUR_VET_SRC="$BATS_TEST_DIRNAME/../../aur"
AUR_VET_FIXTURES="$BATS_TEST_DIRNAME/../fixtures/aur"
# The Atomic Arch deps payload hash (indicators.tsv, ioctl).
_AURVET_PAYLOAD=6144d433f8a0316869877b5f834c801251bbb936e5f1577c5680878c7443c98b

aurvet_setup() {
  T="$(mktemp -d)"
  export AUR_VET_DATA="$T/data" AUR_VET_STORE="$T/store"
  mkdir -p "$AUR_VET_DATA" "$AUR_VET_STORE"
  cp "$AUR_VET_SRC"/*.tsv "$AUR_VET_DATA/"
  # An empty store: fixtures opt into pins explicitly.
  : > "$AUR_VET_STORE/vetted.tsv"; : > "$AUR_VET_STORE/allow.tsv"
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
  # Trust signals come from fixtures, never the network; retries never wait.
  export AUR_VET_RPC_FIXTURE_DIR="$T/rpc" AUR_VET_RETRY_DELAYS=0,0
  mkdir -p "$AUR_VET_RPC_FIXTURE_DIR"
}

aurvet_teardown() { rm -rf "$T"; }

# Copy fixture <name> into a fresh git clone at $T/clone/<name>; commit it as
# <author> (default fixture-maintainer). Prints the clone dir.
aurvet_clone() {
  local name="$1" author="${2:-fixture-maintainer}" dir="$T/clone/$1"
  mkdir -p "$dir"
  cp -r "$AUR_VET_FIXTURES/$name/." "$dir/"
  git -C "$dir" init -q
  git -C "$dir" add -A
  git -C "$dir" -c user.name="$author" -c user.email="$author@aur" \
    commit -q -m "init"
  printf '%s\n' "$dir"
}

# Run the hook the way paru does: cwd = clone, $PKGBASE set.
aurvet_hook() {
  local dir="$1" base="${2:-$(basename "$1")}"
  _aurvet_default_rpc "$base"
  run bash -c 'cd "$1" && PKGBASE="$2" "$3"' _ "$dir" "$base" \
    "$AUR_VET_SRC/aur-vet"
}

# A reviewed-looking default RPC answer unless the test wrote its own.
_aurvet_default_rpc() {
  [[ -n "${AURVET_NO_RPC:-}" || -e "$AUR_VET_RPC_FIXTURE_DIR/$1.json" ]] \
    || aurvet_rpc "$1"
}

# Inject <text> into a fresh copy of the rulecase fixture per <placement> (see
# fixtures/aur/rule-cases.tsv), commit, and print the clone dir. Text goes via
# ENVIRON so awk never interprets its backslashes.
aurvet_case() {
  local placement="$1" text="$2" dir="$T/clone/${3:-case}"
  text="${text//@BLOB@/$(printf 'QUJD%.0s' {1..30})}"
  text="${text//@PAYLOAD@/$_AURVET_PAYLOAD}"
  local when=""
  [[ "$placement" == pkgbase && "$text" == *@* ]] && when="${text#*@}"
  rm -rf "$dir"; mkdir -p "$dir"
  cp -r "$AUR_VET_FIXTURES/rulecase/." "$dir/"
  local pb="$dir/PKGBUILD" si="$dir/.SRCINFO" sum
  _aurvet_ins() { # <file> <after-ERE> <line>: insert after first match
    L="$3" awk -v re="$2" \
      '{ print } !d && $0 ~ re { print ENVIRON["L"]; d = 1 }' \
      "$1" > "$1.new" && mv "$1.new" "$1"
  }
  case "$placement" in
    build) _aurvet_ins "$pb" '^  make$' "  $text" ;;
    install)
      _aurvet_ins "$pb" '^license=' 'install=rulecase.install'
      printf 'post_install() {\n  %s\n}\n' "$text" > "$dir/rulecase.install" ;;
    top) _aurvet_ins "$pb" '^license=' "$text" ;;
    file) printf '#!/bin/sh\n%s\n' "$text" > "$dir/helper.sh" ;;
    source | source-skip)
      sum=3333333333333333333333333333333333333333333333333333333333333333
      [[ "$placement" == source-skip ]] && sum=SKIP
      [[ "$text" == *@SHA=* ]] && \
        { sum="${text#*@SHA=}"; text="${text%@SHA=*}"; }
      _aurvet_ins "$pb" '^source=' "source+=(\"$text\")"
      _aurvet_ins "$pb" '^sha256sums=' "sha256sums+=('$sum')"
      _aurvet_ins "$si" '^\tsource = ' "	source = $text"
      _aurvet_ins "$si" '^\tsha256sums = ' "	sha256sums = $sum" ;;
    nosrcinfo) rm -f "$si" ;;
    pkgbase) ;;
    *) echo "unknown placement: $placement" >&2; return 1 ;;
  esac
  git -C "$dir" init -q
  git -C "$dir" add -A
  GIT_COMMITTER_DATE="$when" GIT_AUTHOR_DATE="$when" \
    git -C "$dir" -c user.name=m -c user.email=m@aur commit -q -m case
  printf '%s\n' "$dir"
}

# Pin <dir>'s HEAD as the Vetted Commit for <pkgbase> (default: dir name).
aurvet_pin() {
  local dir="$1" base="${2:-$(basename "$1")}" maint="${3-fixture-maintainer}"
  printf '%s\t%s\t%s\t2026-01-01\ttest\n' "$base" \
    "$(git -C "$dir" rev-parse HEAD)" "$maint" >> "$AUR_VET_STORE/vetted.tsv"
}

# Commit a change in <dir>: <file> gets <sed-expr> applied.
aurvet_commit() {
  local dir="$1" file="$2" expr="$3"
  sed -i "$expr" "$dir/$file"
  git -C "$dir" -c user.name=m -c user.email=m@aur commit -q -am change
}

# Interactive run: answers on stdin.
aurvet_hook_answer() {
  local dir="$1" answer="$2" base="${3:-$(basename "$1")}"
  _aurvet_default_rpc "$base"
  run bash -c 'cd "$1" && printf "%s\n" "$4" | AUR_VET_INTERACTIVE=1 \
    PKGBASE="$2" "$3"' _ "$dir" "$base" "$AUR_VET_SRC/aur-vet" "$answer"
}

# aurvet_clone + pin its HEAD: a reviewed package, so only findings decide.
aurvet_clone_pinned() {
  local d; d="$(aurvet_clone "$@")"
  aurvet_pin "$d" "$1"
  printf '%s\n' "$d"
}

# AUR RPC fixture for <pkgbase> (ADR 0143): one `info` result. Args are
# jq-style overrides, e.g. Maintainer=evil NumVotes=0 (values are JSON).
aurvet_rpc() {
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
