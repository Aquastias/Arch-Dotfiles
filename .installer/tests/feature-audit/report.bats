#!/usr/bin/env bats
# Tests for `feature-audit.sh report <run-dir>` (ADR 0152, feature-audit/01):
# raw collected artifacts → Findings. Pure: a synthetic Audit Run folder is
# built per test (variant/phase/source files) and the tool is run on it.
#
# Source-file kinds (by extension, written by the collectors):
#   *.log     free-form log: error/warn/fail-shaped lines are Findings
#   *.lines   pre-filtered signal: every non-empty line is a Finding
#   *.probe   probe output: FAIL lines are Findings (PASS/SKIP are not)

setup() {
  INSTALLER_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  TOOL="$INSTALLER_DIR/tools/feature-audit.sh"
  RUN="$BATS_TEST_TMPDIR/run"
  NOISE="$BATS_TEST_TMPDIR/known-noise.jsonc"
  echo '[]' > "$NOISE"
  export FEATURE_AUDIT_KNOWN_NOISE="$NOISE"
  mkdir -p "$RUN"
}

# art <variant> <phase> <file> <content...> — write one collected artifact.
art() {
  local v="$1" p="$2" f="$3"; shift 3
  mkdir -p "$RUN/$v/$p"
  printf '%s\n' "$@" > "$RUN/$v/$p/$f"
}

report() { run bash "$TOOL" report "$RUN"; }
jsonl() { cat "$RUN/findings.jsonl"; }

@test "clean run folder: exit 0, no findings" {
  art base install installer.log "[INFO]  Installing base" "[INFO]  Done"
  art base boot1 failed-units-system.lines ""
  report
  [ "$status" -eq 0 ]
  [ ! -s "$RUN/findings.jsonl" ]
  grep -q 'No findings' "$RUN/findings.md"
}

@test "installer log: WARN/ERROR/pacman warning lines are findings" {
  art base install installer.log \
    "[INFO]  ok" \
    $'\e[1;33m[WARN]\e[0m  mirror slow' \
    "[ERROR] zpool create failed" \
    "warning: directory permissions differ on /etc/x" \
    "[INFO]  0 packages to remove"
  report
  [ "$status" -ne 0 ]
  [ "$(jsonl | wc -l)" -eq 3 ]
  jsonl | jq -e 'select(.excerpt == "[WARN]  mirror slow")' >/dev/null
  jsonl | jq -e 'select(.excerpt == "[ERROR] zpool create failed")' >/dev/null
  jsonl | jq -e 'select(.phase == "install" and .source == "installer")' \
    >/dev/null
}

@test ".lines source: every non-empty line is a finding" {
  art base boot1 failed-units-system.lines "tuned.service loaded failed" ""
  art base boot1 coredumps.lines "Mon 2026-09-28 10:00 1234 SIGSEGV /usr/bin/f"
  report
  [ "$status" -ne 0 ]
  [ "$(jsonl | wc -l)" -eq 2 ]
}

@test ".probe source: only FAIL lines are findings, with program" {
  art base probes-offline probe-zsh@aquastias.probe \
    "PASS zsh-starts ok" "SKIP zsh-x n/a" "FAIL zsh-plugins autosuggest missing"
  report
  [ "$(jsonl | wc -l)" -eq 1 ]
  jsonl | jq -e '.program == "zsh" and .check == "zsh-plugins"
    and .source == "probe"' >/dev/null
}

@test "probe stderr is a finding; hyphenated program; users merge" {
  art base probes-offline probe-power-profiles-daemon@root.err.lines "boom"
  art base probes-offline probe-power-profiles-daemon@aquastias.err.lines \
    "boom"
  report
  [ "$(jsonl | wc -l)" -eq 1 ]
  jsonl | jq -e '.program == "power-profiles-daemon"
    and .source == "probe-stderr" and (.logs | length) == 2' >/dev/null
}

@test "finding carries id, variants, phase, source, excerpt, logs, repro" {
  art base boot1 journal-system.lines \
    "Sep 29 10:00:01 arch-audit foo[812]: bad thing"
  report
  jsonl | jq -e '
    (.id | test("^F[0-9]{3}$")) and .variants == ["base"]
    and .phase == "boot1" and .source == "journal-system"
    and (.excerpt | contains("bad thing"))
    and (.logs[0] | endswith("base/boot1/journal-system.lines"))
    and (.repro | contains("--variant base"))
    and has("program") and has("adrs") and .count == 1 and .total == 1
  ' >/dev/null
}

@test "same finding in two variants → one entry listing both" {
  art base boot1 journal-system.lines \
    "Sep 29 10:00:01 arch-audit foo[812]: bad thing"
  art grub boot1 journal-system.lines \
    "Sep 29 11:22:33 arch-audit foo[977]: bad thing"
  report
  [ "$(jsonl | wc -l)" -eq 1 ]
  jsonl | jq -e '.variants == ["base","grub"] and (.logs | length) == 2' \
    >/dev/null
}

@test "intermittent finding shows frequency across boots" {
  art base boot1 journal-system.lines "Sep 29 10:00:01 h foo[1]: race"
  art base boot2 journal-system.lines "Sep 29 10:10:01 h foo[2]: race"
  art base upgrade journal-system.lines "Sep 29 10:20:01 h bar[3]: other"
  report
  jsonl | jq -e 'select(.excerpt | contains("race"))
    | .count == 2 and .total == 3 and .phases == ["boot1","boot2"]' >/dev/null
  grep -q '2/3' "$RUN/findings.md"
}

@test "known noise drops matching lines; scope limits by source/phase" {
  cat > "$NOISE" <<'EOF'
// test allowlist
[
  { "regex": "harmless thing", "reason": "ADR 0000: expected" },
  { "regex": "scoped", "source": "journal-system", "phase": "boot1",
    "reason": "only first boot" }
]
EOF
  art base boot1 journal-system.lines \
    "Sep 29 10:00:01 h a[1]: harmless thing" \
    "Sep 29 10:00:01 h a[1]: scoped"
  art base boot2 journal-system.lines "Sep 29 10:00:01 h a[1]: scoped"
  report
  [ "$(jsonl | wc -l)" -eq 1 ]
  jsonl | jq -e '.phase == "boot2"' >/dev/null
}

@test "findings.md is grouped by phase in phase order, then source" {
  art base upgrade journal-system.lines "Sep 29 10:00:01 h a[1]: late"
  art base install installer.log "[ERROR] early"
  report
  local i u
  i="$(grep -n '^## install' "$RUN/findings.md" | cut -d: -f1)"
  u="$(grep -n '^## upgrade' "$RUN/findings.md" | cut -d: -f1)"
  [ -n "$i" ] && [ -n "$u" ] && [ "$i" -lt "$u" ]
  grep -q '^### installer' "$RUN/findings.md"
  grep -q 'F001' "$RUN/findings.md"
}

@test "report is re-runnable: stale outputs are replaced, not appended" {
  art base install installer.log "[ERROR] early"
  report; report
  [ "$(jsonl | wc -l)" -eq 1 ]
}

@test "missing run folder is a usage error" {
  run bash "$TOOL" report "$BATS_TEST_TMPDIR/nope"
  [ "$status" -eq 2 ]
}

@test "log kind: bracketed [ERR]/[CRITICAL] compositor lines are findings" {
  art base sessions-hyprland hyprland.log "[LOG] ok" "[ERR] shader compile" \
    "[CRITICAL] oops" "[INFO] all good"
  report
  [ "$(jsonl | wc -l)" -eq 2 ]
}

@test "per-desktop session phases group under sessions order" {
  art base upgrade journal.lines "Sep 29 10:00:01 h a[1]: late"
  art base sessions-kde journal.lines "Sep 29 10:00:01 h b[1]: kde"
  art base boot1 journal.lines "Sep 29 10:00:01 h c[1]: early"
  report
  jsonl | jq -r .phase | tr '\n' ' ' | grep -q '^boot1 sessions-kde upgrade $'
}

@test "screenshots are listed in a visual-review section" {
  mkdir -p "$RUN/base/sessions-kde/screens"
  : > "$RUN/base/sessions-kde/screens/session-kde.png"
  art base boot1 journal.lines ""
  report
  grep -q '^## Visual review' "$RUN/findings.md"
  grep -q 'base/sessions-kde/screens/session-kde.png' "$RUN/findings.md"
}

@test "visual review also follows a non-empty findings list" {
  mkdir -p "$RUN/base/sessions-kde/screens"
  : > "$RUN/base/sessions-kde/screens/session-kde.png"
  art base install installer.log "[ERROR] x"
  report
  grep -q '^## Visual review' "$RUN/findings.md"
}

@test "offline FAIL + online PASS of one check → a runtime-fetch finding" {
  art base probes-offline probe-nvim@aquastias.probe \
    "FAIL nvim-treesitter parser download failed" "FAIL nvim-lsp broken"
  art base probes-online probe-nvim@aquastias.probe \
    "PASS nvim-treesitter ok" "FAIL nvim-lsp broken"
  report
  [ "$(jsonl | wc -l)" -eq 2 ]
  jsonl | jq -e 'select(.source == "runtime-fetch")
    | .program == "nvim" and .check == "nvim-treesitter"
      and (.excerpt | contains("parser download failed"))' >/dev/null
  # the genuinely broken check stays a plain probe finding
  jsonl | jq -e 'select(.source == "probe") | .check == "nvim-lsp"' >/dev/null
}

@test "log kind: package names containing error/warn are not findings" {
  art base install installer.log \
    "multilib/lib32-libgpg-error   1.61-1   0.16 MiB" \
    " perl-error-0.17030-3-any downloading..." \
    "installing libgpg-error..." \
    "error: failed to prepare transaction"
  report
  [ "$(jsonl | wc -l)" -eq 1 ]
  jsonl | jq -e '.excerpt == "error: failed to prepare transaction"' >/dev/null
}

@test "runtime fetch is judged per account, not across users" {
  art base probes-offline probe-nvim@alice.probe "FAIL nvim-x broke offline"
  art base probes-online probe-nvim@alice.probe "FAIL nvim-x broke offline"
  art base probes-online probe-nvim@bob.probe "PASS nvim-x ok"
  report
  jsonl | jq -e 'select(.check == "nvim-x") | .source == "probe"' >/dev/null
  ! jsonl | jq -e 'select(.source == "runtime-fetch")' >/dev/null
}

@test "findings carry the ADRs their variants cover (variant.json)" {
  mkdir -p "$RUN/grub"
  echo '{"variant":"grub","adrs":["0038","0078"]}' > "$RUN/grub/variant.json"
  art grub install installer.log "[ERROR] esp too small"
  report
  jsonl | jq -e '.adrs == ["0038","0078"]' >/dev/null
}

# ── one journal entry, one Finding (Audit Run 20260929 inflation) ───────────

@test ".lines: whitespace-led continuation lines fold into their entry" {
  art base boot2 journal-user-aquastias.lines \
    'Sep 29 17:42:45 h spectacle[2538]: Detected locale "C", not UTF-8.' \
    '                                    Qt depends on a UTF-8 locale.' \
    '                                    See the locale(1) manual'
  report
  [ "$(jsonl | wc -l)" -eq 1 ]
  jsonl | jq -e '.excerpt | startswith("spectacle")' >/dev/null
}

@test "dedup normalises hex ids: busy unmounts differing by hash merge" {
  art base boot1 serial.lines \
    '[  1.2] (sd-umoun: Failed to unmount /run/shutdown/mounts/a3f9c01e: busy' \
    '[  3.4] (sd-umoun: Failed to unmount /run/shutdown/mounts/9bd4e2ff7a: busy'
  report
  [ "$(jsonl | wc -l)" -eq 1 ]
}

@test "dedup keeps hex-free words distinct (no false merge)" {
  art base boot1 journal.lines 'x: failed to load facade' \
    'x: failed to load decade'
  report
  [ "$(jsonl | wc -l)" -eq 2 ]
}

@test "installer log: pacman 'is up to date -- skipping' is not a finding" {
  art base install installer.log \
    "warning: zoxide-0.9.8-1 is up to date -- skipping"
  report
  [ "$status" -eq 0 ]
  [ ! -s "$RUN/findings.jsonl" ]
}

@test "ids stay unique past 999 and match between md and jsonl" {
  local -a l=(); local i w
  # distinct names that survive normalisation: digits spelled as g..p
  for ((i = 0; i < 1001; i++)); do
    w="$(tr 0-9 g-p <<<"$i")"; l+=("unit-$w failed")
  done
  art base boot1 journal.lines "${l[@]}"
  report
  local n; n="$(jsonl | wc -l)"
  [ "$n" -gt 999 ]
  [ "$(jsonl | jq -r .id | sort -u | wc -l)" -eq "$n" ]
  jsonl | jq -e 'select(.id == "F0001")' >/dev/null
  [ "$(grep -o '^- \*\*F[0-9]*\*\*' "$RUN/findings.md" | sort -u | wc -l)" \
    -eq "$n" ]
}

@test "known noise scoped to variants mutes only there" {
  cat > "$NOISE" <<'EOF2'
[ { "regex": "No config file found", "variants": ["hyprland-pure"],
    "reason": "stock Hyprland generates its config (ADR 0112)" } ]
EOF2
  art hyprland-pure sessions-hyprland hyprland.lines "No config file found"
  art base sessions-hyprland hyprland.lines "No config file found"
  report
  [ "$(jsonl | wc -l)" -eq 1 ]
  jsonl | jq -e '.variants == ["base"]' >/dev/null
}

@test "skipped checks are listed in findings.md, never findings" {
  art base probes-offline probe-apparmor@gate.probe \
    "SKIP apparmor-selected not selected in this variant (Probe Gate)"
  art base probes-offline probe-zsh@aquastias.probe "FAIL zsh-x broken"
  report
  [ "$(jsonl | wc -l)" -eq 1 ]
  grep -q '^## Skipped checks' "$RUN/findings.md"
  grep -q 'apparmor-selected.*not selected in this variant.*base' \
    "$RUN/findings.md"
}

@test "known noise regex with backslash escapes matches literally" {
  # @tsv doubled every backslash, so \( reached awk as \\( (Audit Run 20261002)
  cat > "$NOISE" <<'EOF2'
[ { "regex": "^\\(sd-umoun\\[[0-9]+\\]: Failed to unmount", "reason": "r" } ]
EOF2
  art base boot1 serial.lines '(sd-umoun[42]: Failed to unmount /run/x: busy'
  report
  [ "$status" -eq 0 ]
  [ ! -s "$RUN/findings.jsonl" ]
}

@test "a broken judge fails loudly, never a silent zero" {
  cat > "$NOISE" <<'EOF2'
[ { "regex": "(unbalanced", "reason": "r" } ]
EOF2
  art base boot1 journal.lines "x: failed"
  report
  [ "$status" -eq 2 ]
}

@test "known noise regex may be an array of concatenated pieces (80 cols)" {
  cat > "$NOISE" <<'EOF2'
[ { "regex": ["^(alpha\\[[0-9]+\\]: one|", "beta: two)"], "reason": "r" } ]
EOF2
  art base boot1 journal.lines "alpha[1]: one thing" "beta: two things" \
    "gamma: failed"
  report
  [ "$(jsonl | wc -l)" -eq 1 ]
  jsonl | jq -e '.excerpt | startswith("gamma")' >/dev/null
}
