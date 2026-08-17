#!/usr/bin/env bats
# Tests for .os/lib/config/layer-resolver.sh — the Layer Resolver (ADR 0057).
#
# The module is pure JSON-in/JSON-out, so every assertion is external: given
# these layers, this is the effective set. Nothing here reaches into
# intermediate state or asserts how the merge is implemented.
#
# The contract has four parts:
#   1. Additive keys concat + dedupe; replace keys are overwritten wholesale.
#   2. `exclude` subtracts what a lower layer contributed.
#   3. The LAST layer wins — it may re-add what an earlier layer excluded.
#   4. `packages.inherit: false` is scoped to packages only.

setup() {
  source "$BATS_TEST_DIRNAME/../../lib/config/layer-resolver.sh"
}

# resolve <core-json> <profile-json> — host fold, compact output.
resolve() { layer_resolve_host "$1" "$2" | jq -c .; }
uresolve() { layer_resolve_user "$1" "$2" | jq -c .; }

# ── additive keys concat + dedupe ───────────────────────────────────────────

@test "additive: packages.repo categories concat across layers" {
  run resolve '{"packages":{"repo":{"cli":["htop"]}}}' \
              '{"packages":{"repo":{"cli":["fzf"]}}}'
  echo "$output" | jq -e '.packages.repo.cli == ["htop","fzf"]'
}

@test "additive: packages.repo dedupes a package both layers declare" {
  run resolve '{"packages":{"repo":{"cli":["htop","fzf"]}}}' \
              '{"packages":{"repo":{"cli":["fzf","btop"]}}}'
  echo "$output" | jq -e '.packages.repo.cli == ["htop","fzf","btop"]'
}

@test "additive: a category only the upper layer declares is added" {
  run resolve '{"packages":{"repo":{"cli":["htop"]}}}' \
              '{"packages":{"repo":{"gaming":["steam"]}}}'
  echo "$output" | jq -e '.packages.repo.cli == ["htop"]'
  echo "$output" | jq -e '.packages.repo.gaming == ["steam"]'
}

@test "additive: packages.aur concats like repo" {
  run resolve '{"packages":{"aur":{"misc":["brave-bin"]}}}' \
              '{"packages":{"aur":{"misc":["zen-browser-bin"]}}}'
  echo "$output" | jq -e '.packages.aur.misc == ["brave-bin","zen-browser-bin"]'
}

@test "additive: host_programs concats" {
  run resolve '{"host_programs":["cups"]}' '{"host_programs":["grub"]}'
  echo "$output" | jq -e '.host_programs == ["cups","grub"]'
}

@test "additive: users concats, order preserved" {
  run resolve '{"users":["alice"]}' '{"users":["bob"]}'
  echo "$output" | jq -e '.users == ["alice","bob"]'
}

@test "additive: persist.directories and persist.files concat" {
  run resolve '{"persist":{"directories":["/home"],"files":["/etc/a"]}}' \
              '{"persist":{"directories":["/srv"],"files":["/etc/b"]}}'
  echo "$output" | jq -e '.persist.directories == ["/home","/srv"]'
  echo "$output" | jq -e '.persist.files == ["/etc/a","/etc/b"]'
}

@test "additive: sysctl deep-merges, upper wins per key" {
  run resolve '{"sysctl":{"vm.swappiness":10,"fs.file-max":100}}' \
              '{"sysctl":{"vm.swappiness":60}}'
  echo "$output" | jq -e '.sysctl["vm.swappiness"] == 60'
  echo "$output" | jq -e '.sysctl["fs.file-max"] == 100'
}

@test "additive (user): groups, programs, ssh_authorized_keys concat" {
  run uresolve '{"groups":["wheel"],"programs":["git"],
                 "ssh_authorized_keys":["k1"]}' \
               '{"groups":["docker"],"programs":["docker"],
                 "ssh_authorized_keys":["k2"]}'
  echo "$output" | jq -e '.groups == ["wheel","docker"]'
  echo "$output" | jq -e '.programs == ["git","docker"]'
  echo "$output" | jq -e '.ssh_authorized_keys == ["k1","k2"]'
}

# ── replace keys are overwritten wholesale ──────────────────────────────────
# This is the bug the blanket-concat merge would have produced once Host Core
# carried content: two kernels installed, each built against ZFS DKMS.

@test "replace: options.kernel is overwritten, not concatenated" {
  run resolve '{"options":{"kernel":["lts"]}}' '{"options":{"kernel":["zen"]}}'
  echo "$output" | jq -e '.options.kernel == ["zen"]'
}

@test "replace: a sibling scalar under options survives a kernel override" {
  run resolve '{"options":{"kernel":["lts"],"bootloader":"grub"}}' \
              '{"options":{"kernel":["zen"]}}'
  echo "$output" | jq -e '.options.kernel == ["zen"]'
  echo "$output" | jq -e '.options.bootloader == "grub"'
}

@test "replace: system.locale and system.keymap are overwritten" {
  run resolve '{"system":{"locale":["en_US.UTF-8"],"keymap":["us"]}}' \
              '{"system":{"locale":["de_DE.UTF-8"],"keymap":["de"]}}'
  echo "$output" | jq -e '.system.locale == ["de_DE.UTF-8"]'
  echo "$output" | jq -e '.system.keymap == ["de"]'
}

@test "replace: environment.desktop and environment.gpu are overwritten" {
  run resolve '{"environment":{"desktop":["kde"],"gpu":["amd"]}}' \
              '{"environment":{"desktop":[],"gpu":["nvidia"]}}'
  echo "$output" | jq -e '.environment.desktop == []'
  echo "$output" | jq -e '.environment.gpu == ["nvidia"]'
}

@test "replace: options.mirror_countries is an ordered preference" {
  run resolve '{"options":{"mirror_countries":["Germany","France"]}}' \
              '{"options":{"mirror_countries":["Romania"]}}'
  echo "$output" | jq -e '.options.mirror_countries == ["Romania"]'
}

@test "replace: storage_groups and data_pools are positional" {
  run resolve '{"storage_groups":[{"name":"a"}],"data_pools":[{"name":"p"}]}' \
              '{"storage_groups":[{"name":"b"}],"data_pools":[{"name":"q"}]}'
  echo "$output" | jq -e '.storage_groups == [{"name":"b"}]'
  echo "$output" | jq -e '.data_pools == [{"name":"q"}]'
}

@test "replace: every scalar is overwritten by the later layer" {
  run resolve '{"filesystem":"zfs","options":{"encryption":false}}' \
              '{"filesystem":"btrfs","options":{"encryption":true}}'
  echo "$output" | jq -e '.filesystem == "btrfs"'
  echo "$output" | jq -e '.options.encryption == true'
}

@test "replace (user): shell and sudo are overwritten" {
  run uresolve '{"shell":"/bin/bash","sudo":false}' \
               '{"shell":"/bin/zsh","sudo":true}'
  echo "$output" | jq -e '.shell == "/bin/zsh"'
  echo "$output" | jq -e '.sudo == true'
}

@test "replace (user): user_services is overwritten, git deep-merges" {
  run uresolve '{"user_services":["podman.socket"],
                 "git":{"name":"Core","email":"core@x"}}' \
               '{"user_services":["syncthing"],"git":{"name":"Me"}}'
  echo "$output" | jq -e '.user_services == ["syncthing"]'
  echo "$output" | jq -e '.git.name == "Me"'
  echo "$output" | jq -e '.git.email == "core@x"'
}

# Coverage guard: every key in the classification table must be exercised
# above. A new key added to either table without a test fails here.
@test "classification: every table key is covered by a test in this file" {
  local key probe
  for key in $(layer_additive_keys host) $(layer_replace_keys host) \
             $(layer_additive_keys user) $(layer_replace_keys user); do
    probe="${key%.\*}"                       # packages.repo.* → packages.repo
    grep -q -- "$probe" "$BATS_TEST_FILENAME" \
      || { echo "classification key not covered by a test: $key"; return 1; }
  done
}

# ── exclude subtracts ───────────────────────────────────────────────────────

@test "exclude: removes a package the lower layer contributed" {
  run resolve '{"packages":{"repo":{"cli":["htop","fzf"]}}}' \
              '{"packages":{"exclude":["htop"]}}'
  echo "$output" | jq -e '.packages.repo.cli == ["fzf"]'
}

@test "exclude: works across every repo category and aur" {
  run resolve '{"packages":{"repo":{"cli":["htop"],"dev":["htop","go"]},
                            "aur":{"misc":["htop"]}}}' \
              '{"packages":{"exclude":["htop"]}}'
  echo "$output" | jq -e '.packages.repo.cli == []'
  echo "$output" | jq -e '.packages.repo.dev == ["go"]'
  echo "$output" | jq -e '.packages.aur.misc == []'
}

@test "exclude: host_programs_exclude drops a core system program" {
  run resolve '{"host_programs":["cups","grub"]}' \
              '{"host_programs_exclude":["cups"]}'
  echo "$output" | jq -e '.host_programs == ["grub"]'
}

@test "exclude (user): programs_exclude drops a User Core program" {
  run uresolve '{"programs":["docker","virt-manager","git"]}' \
               '{"programs_exclude":["docker","virt-manager"]}'
  echo "$output" | jq -e '.programs == ["git"]'
}

@test "exclude: the control keys never reach the effective config" {
  run resolve '{"packages":{"repo":{"cli":["htop"]}}}' \
              '{"packages":{"exclude":["htop"]},
                "host_programs_exclude":["cups"]}'
  echo "$output" | jq -e 'has("host_programs_exclude") | not'
  echo "$output" | jq -e '(.packages // {}) | has("exclude") | not'
}

# ── the last layer wins: re-adding what a lower layer excluded ──────────────

@test "last layer wins: a later layer re-adds an excluded package" {
  local core='{"packages":{"repo":{"cli":["htop","fzf"]}}}'
  local mid='{"packages":{"exclude":["htop"]}}'
  local leaf='{"packages":{"repo":{"cli":["htop"]}}}'
  run bash -c "
    source '$BATS_TEST_DIRNAME/../../lib/config/layer-resolver.sh'
    layer_resolve host '$core' '$mid' '$leaf' | jq -c ."
  echo "$output" | jq -e '.packages.repo.cli == ["fzf","htop"]'
}

@test "last layer wins: a lower layer's exclude cannot veto an upper add" {
  # core excludes htop, but the host explicitly declares it — the host, being
  # the later layer, has the final say about its own machine.
  run resolve '{"packages":{"exclude":["htop"]}}' \
              '{"packages":{"repo":{"cli":["htop"]}}}'
  echo "$output" | jq -e '.packages.repo.cli == ["htop"]'
}

# ── packages.inherit: false — scoped to packages only ───────────────────────

@test "inherit false: yields no inherited packages" {
  run resolve '{"packages":{"repo":{"cli":["htop"]},"aur":{"m":["brave"]}}}' \
              '{"packages":{"inherit":false}}'
  echo "$output" | jq -e '(.packages.repo // {}) == {}'
  echo "$output" | jq -e '(.packages.aur // {}) == {}'
}

@test "inherit false: the profile's OWN packages still apply" {
  run resolve '{"packages":{"repo":{"cli":["htop"]}}}' \
              '{"packages":{"inherit":false,"repo":{"cli":["vim"]}}}'
  echo "$output" | jq -e '.packages.repo.cli == ["vim"]'
}

@test "inherit false: users and sysctl are STILL inherited" {
  run resolve '{"users":["alice"],"sysctl":{"vm.swappiness":10},
                "host_programs":["cups"],
                "packages":{"repo":{"cli":["htop"]}}}' \
              '{"packages":{"inherit":false}}'
  echo "$output" | jq -e '.users == ["alice"]'
  echo "$output" | jq -e '.sysctl["vm.swappiness"] == 10'
  echo "$output" | jq -e '.host_programs == ["cups"]'
  echo "$output" | jq -e '(.packages.repo // {}) == {}'
}

@test "inherit: the control key never reaches the effective config" {
  run resolve '{"packages":{"repo":{"cli":["htop"]}}}' \
              '{"packages":{"inherit":false,"repo":{"cli":["vim"]}}}'
  echo "$output" | jq -e '.packages | has("inherit") | not'
}

@test "inherit true (the default) inherits normally" {
  run resolve '{"packages":{"repo":{"cli":["htop"]}}}' \
              '{"packages":{"inherit":true,"repo":{"cli":["vim"]}}}'
  echo "$output" | jq -e '.packages.repo.cli == ["htop","vim"]'
}

# ── shape / edge cases ──────────────────────────────────────────────────────

@test "an empty upper layer returns the lower layer unchanged" {
  run resolve '{"users":["alice"],"options":{"kernel":["lts"]}}' '{}'
  echo "$output" | jq -e '.users == ["alice"]'
  echo "$output" | jq -e '.options.kernel == ["lts"]'
}

@test "an empty lower layer returns the upper layer unchanged" {
  run resolve '{}' '{"users":["bob"]}'
  echo "$output" | jq -e '.users == ["bob"]'
}

@test "the resolver is deterministic for the same inputs" {
  local a b
  a="$(resolve '{"packages":{"repo":{"cli":["htop"]}},"users":["x"]}' \
               '{"packages":{"repo":{"cli":["fzf"]}}}')"
  b="$(resolve '{"packages":{"repo":{"cli":["htop"]}},"users":["x"]}' \
               '{"packages":{"repo":{"cli":["fzf"]}}}')"
  [ "$a" = "$b" ]
}

@test "layer_resolve folds N layers left to right" {
  run bash -c "
    source '$BATS_TEST_DIRNAME/../../lib/config/layer-resolver.sh'
    layer_resolve host '{\"users\":[\"a\"]}' '{\"users\":[\"b\"]}' \
      '{\"users\":[\"c\"]}' | jq -c ."
  echo "$output" | jq -e '.users == ["a","b","c"]'
}
