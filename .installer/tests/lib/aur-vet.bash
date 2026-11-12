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
  local clone_directory="$1" base="${2:-}"
  [[ -n "$base" ]] || base="$(basename "$1")"
  _aur_vet_default_rpc "$base"
  run bash -c 'cd "$1" && PKGBASE="$2" "$3"' _ "$clone_directory" "$base" \
    "$AUR_VET_SRC/aur-vet"
}

# A reviewed-looking default RPC answer unless the test wrote its own.
_aur_vet_default_rpc() {
  [[ -n "${AURVET_NO_RPC:-}" || -e "$AUR_VET_RPC_FIXTURE_DIR/$1.json" ]] \
    || aur_vet_rpc "$1"
}

# _aur_vet_replace_all <text> <from> <to> — <text> with every <from>
# replaced by <to>, read left to right.
_aur_vet_replace_all() {
  local text="$1" from="$2" to="$3" result="" index=0
  while (( index < ${#text} )); do
    if [[ "${text:index:${#from}}" == "$from" ]]; then
      result+="$to"
      index=$(( index + ${#from} ))
    else
      result+="${text:index:1}"
      index=$(( index + 1 ))
    fi
  done
  printf '%s\n' "$result"
}

# _aur_vet_insert_after <file> <after-ERE> <line> — put <line> right after
# the first line of <file> matching <after-ERE>.
_aur_vet_insert_after() {
  local file="$1" pattern="$2" text="$3" line placed=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    printf '%s\n' "$line"
    if (( ! placed )) && [[ "$line" =~ $pattern ]]; then
      printf '%s\n' "$text"
      placed=1
    fi
  done < "$file" > "$file.new" && mv "$file.new" "$file"
}

# Inject <text> into a fresh copy of the rulecase fixture per <placement> (see
# fixtures/aur/rule-cases.tsv), commit, and print the clone dir.
aur_vet_case() {
  local placement="$1" text="$2" clone_directory="$T/clone/${3:-case}"
  text="$(_aur_vet_replace_all "$text" @BLOB@ "$(printf 'QUJD%.0s' {1..30})")"
  text="$(_aur_vet_replace_all "$text" @XMR@ "$_AURVET_XMR")"
  text="$(_aur_vet_replace_all "$text" @PAYLOAD@ "$_AURVET_PAYLOAD")"
  local when=""
  # A pkgbase case may carry a commit date: "<pkgbase>@<date>".
  [[ "$placement" == pkgbase && "$text" == *@* ]] \
    && when="$(printf '%s\n' "$text" | cut -d@ -f2-)"
  rm -rf "$clone_directory"; mkdir -p "$clone_directory"
  cp -r "$AUR_VET_FIXTURES/rulecase/." "$clone_directory/"
  _aur_vet_place "$placement" "$text" "$clone_directory" || return 1
  git -C "$clone_directory" init -q
  git -C "$clone_directory" add -A
  GIT_COMMITTER_DATE="$when" GIT_AUTHOR_DATE="$when" \
    git -C "$clone_directory" -c user.name=m -c user.email=m@aur commit -q -m case
  printf '%s\n' "$clone_directory"
}

# _aur_vet_place <placement> <text> <clone> — put <text> into the clone's
# files the way <placement> says.
_aur_vet_place() {
  local placement="$1" text="$2" clone_directory="$3"
  local pkgbuild="$clone_directory/PKGBUILD" srcinfo="$clone_directory/.SRCINFO"
  local tab=$'\t' command
  case "$placement" in
    build) _aur_vet_insert_after "$pkgbuild" '^  make$' "  $text" ;;
    install)
      _aur_vet_insert_after "$pkgbuild" '^license=' 'install=rulecase.install'
      printf 'post_install() {\n  %s\n}\n' "$text" > "$clone_directory/rulecase.install" ;;
    top) _aur_vet_insert_after "$pkgbuild" '^license=' "$text" ;;
    file) printf '#!/bin/sh\n%s\n' "$text" > "$clone_directory/helper.sh" ;;
    source | source-skip) _aur_vet_place_source "$@" ;;
    nosrcinfo) rm -f "$srcinfo" ;;
    heredoc | shheredoc)
      command=cat; [[ "$placement" == shheredoc ]] && command=sh
      _aur_vet_insert_after "$pkgbuild" '^license=' 'install=rulecase.install'
      printf 'post_install() {\n%s << EOF\n%s\nEOF\n}\n' "$command" "$text" \
        > "$clone_directory/rulecase.install" ;;
    srcvar) _aur_vet_place_srcvar "$@" ;;
    binary) printf '\x89PNG\0\1' > "$clone_directory/icon.png" ;;
    path | sums) _aur_vet_place_file "$@" ;;
    srcinfo) _aur_vet_insert_after "$srcinfo" "^${tab}source = " "	$text" ;;
    nulpkgbuild) printf '# \0\n' >> "$pkgbuild" ;;
    pkgbase) ;;
    *) echo "unknown placement: $placement" >&2; return 1 ;;
  esac
}

# _aur_vet_place_source <placement> <text> <clone> — <text> as one more
# source URL (source-skip: with a SKIP sum). "<url>@SHA=<sum>" sets the sum.
_aur_vet_place_source() {
  local placement="$1" text="$2" clone_directory="$3" sum tab=$'\t'
  local pkgbuild="$clone_directory/PKGBUILD" srcinfo="$clone_directory/.SRCINFO"
  sum=3333333333333333333333333333333333333333333333333333333333333333
  [[ "$placement" == source-skip ]] && sum=SKIP
  if [[ "$text" == *@SHA=* ]]; then
    # The sum after "@SHA=", then the URL before it (the fixture URLs hold
    # no other @).
    sum="$(printf '%s\n' "$text" | cut -d@ -f2 | cut -c5-)"
    text="$(printf '%s\n' "$text" | cut -d@ -f1)"
  fi
  _aur_vet_insert_after "$pkgbuild" '^source=' "source+=(\"$text\")"
  _aur_vet_insert_after "$pkgbuild" '^sha256sums=' "sha256sums+=('$sum')"
  _aur_vet_insert_after "$srcinfo" "^${tab}source = " "	source = $text"
  _aur_vet_insert_after "$srcinfo" "^${tab}sha256sums = " "	sha256sums = $sum"
}

# _aur_vet_place_srcvar <placement> <text> <clone> — a source host hidden
# behind a variable; .SRCINFO shows a benign one.
_aur_vet_place_srcvar() {
  local text="$2" clone_directory="$3" tab=$'\t'
  local pkgbuild="$clone_directory/PKGBUILD" srcinfo="$clone_directory/.SRCINFO"
  _aur_vet_insert_after "$pkgbuild" '^license=' "_h=$text"
  _aur_vet_insert_after "$pkgbuild" '^source=' 'source+=("https://${_h}/rulecase/p.tgz")'
  _aur_vet_insert_after "$pkgbuild" '^sha256sums=' "sha256sums+=('SKIP')"
  _aur_vet_insert_after "$srcinfo" "^${tab}source = " \
    "	source = https://github.com/rulecase/p.tgz"
  _aur_vet_insert_after "$srcinfo" "^${tab}sha256sums = " "	sha256sums = SKIP"
}

# _aur_vet_place_file <placement> <text> <clone> — path: "<relpath>::<content>"
# adds a tracked file at that path; sums: "<algo>[:SKIP]" swaps the sha256
# algorithm (and digest).
_aur_vet_place_file() {
  local placement="$1" text="$2" clone_directory="$3"
  local pkgbuild="$clone_directory/PKGBUILD" srcinfo="$clone_directory/.SRCINFO"
  local relative_path content algorithm
  if [[ "$placement" == path ]]; then
    relative_path="$(printf '%s\n' "$text" | cut -d: -f1)"
    content="$(printf '%s\n' "$text" | cut -d: -f3-)"
    mkdir -p "$clone_directory/$(dirname "$relative_path")"
    printf '%s\n' "$content" > "$clone_directory/$relative_path"
    return 0
  fi
  algorithm="$(printf '%s\n' "$text" | cut -d: -f1)"
  # Rename the sums arrays.
  sed -i "s/sha256sums/${algorithm}sums/" "$pkgbuild" "$srcinfo"
  # For :SKIP, the digests too.
  [[ "$text" == *:SKIP ]] && sed -i "s/2\{64\}/SKIP/" "$pkgbuild" "$srcinfo"
  return 0
}

# Commit a change in <directory>: <file> gets <sed-expr> applied.
aur_vet_commit() {
  local directory="$1" file="$2" expression="$3"
  # The test's edit.
  sed -i "$expression" "$directory/$file"
  git -C "$directory" -c user.name=m -c user.email=m@aur commit -q -am change
}

# Interactive run: answers on stdin.
aur_vet_hook_answer() {
  local directory="$1" answer="$2" base="${3:-}"
  [[ -n "$base" ]] || base="$(basename "$1")"
  _aur_vet_default_rpc "$base"
  run bash -c 'cd "$1" && printf "%s\n" "$4" | AUR_VET_INTERACTIVE=1 \
    PKGBASE="$2" "$3"' _ "$directory" "$base" "$AUR_VET_SRC/aur-vet" "$answer"
}

# AUR RPC fixture for <pkgbase> (ADR 0143): one `info` result. Args are
# overrides, e.g. Maintainer=evil NumVotes=0 (values are JSON).
aur_vet_rpc() {
  local base="$1"; shift
  local now submitted result override key value
  now="$(date +%s)"
  submitted="$(( now - 400 * 86400 ))"
  result="$(printf '{"Name":"%s","PackageBase":"%s",' "$base" "$base")"
  result+='"Maintainer":"fixture-maintainer",'
  result+='"Submitter":"fixture-maintainer",'
  result+="$(printf '"FirstSubmitted":%s,"LastModified":%s,' \
    "$submitted" "$submitted")"
  result+='"OutOfDate":null,"NumVotes":100}'
  for override in "$@"; do
    # "<key>=<json value>"
    key="$(printf '%s\n' "$override" | cut -d= -f1)"
    value="$(printf '%s\n' "$override" | cut -d= -f2-)"
    # The result with <key> set to <value>.
    result="$(printf '%s\n' "$result" \
      | jq -c --arg k "$key" --argjson v "$value" '.[$k] = $v')"
  done
  printf '{"resultcount":1,"results":[%s],"type":"multiinfo","version":5}\n' \
    "$result" > "$AUR_VET_RPC_FIXTURE_DIR/$base.json"
}
