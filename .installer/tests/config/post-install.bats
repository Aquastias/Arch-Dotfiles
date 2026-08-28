#!/usr/bin/env bats
# Tests for .os/lib/config/post-install.sh — the Security & Backup Extras
# resolver (M2, ADR 0041): a pure core mapping a post_install.{security,backup}
# object to the ordered Program-name list, the secure-baseline default object,
# and shape validation. Pure: JSON-in / list-out, no TTY, no disk writes.
#
# Behaviour under test is external only — the resolved program list, the
# default object, and accept/reject of a candidate object — never internals.

setup() {
  error() { echo "[error] $*" >&2; return 1; }
  export -f error

  # shellcheck source=../../lib/config/post-install.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/post-install.sh"
}

# ── tracer: the secure-baseline default object ──────────────────────────────

@test "post_install_default: secure baseline = firewalld + all tools on" {
  run post_install_default
  [ "$status" -eq 0 ]
  [ "$(jq -S . <<<"$output")" = "$(jq -S . <<<'{
    "security": {
      "firewall": "firewalld",
      "antivirus": true,
      "rootkit": true,
      "apparmor": true
    },
    "backup": { "zfs_auto_snapshot": true, "borg": true }
  }')" ]
}

# ── programs: the resolved Program-name list ────────────────────────────────

@test "post_install_programs: default → firewalld+clamav+rkhunter+apparmor+snap+borg" {
  run post_install_programs "$(post_install_default)"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '%s\n' firewalld clamav rkhunter apparmor \
    zfs-auto-snapshot borg)" ]
}

@test "post_install_programs: firewall ufw resolves to ufw, not firewalld" {
  run post_install_programs '{"security":{"firewall":"ufw"}}'
  [ "$status" -eq 0 ]
  [ "$output" = "ufw" ]
}

@test "post_install_programs: firewall none emits no firewall program" {
  run post_install_programs '{"security":{"firewall":"none","antivirus":true}}'
  [ "$status" -eq 0 ]
  [ "$output" = "clamav" ]
}

@test "post_install_programs: empty object → empty list (absent = off)" {
  run post_install_programs '{}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "post_install_programs: a single backup toggle resolves alone" {
  run post_install_programs '{"backup":{"borg":true}}'
  [ "$status" -eq 0 ]
  [ "$output" = "borg" ]
}

@test "post_install_programs: a legacy bool form resolves to off, not a crash" {
  # A non-object security/backup (legacy `true`) must coerce to off, never
  # index a boolean (`true.antivirus` would abort the whole runner).
  run post_install_programs '{"security":true,"backup":true}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ── validation: object shape, firewall enum, bool fields ────────────────────

@test "post_install_validate: accepts the secure-baseline default object" {
  run post_install_validate "$(post_install_default)"
  [ "$status" -eq 0 ]
}

@test "post_install_validate: rejects the old bool form" {
  run post_install_validate '{"security":false,"backup":false}'
  [ "$status" -ne 0 ]
}

@test "post_install_validate: rejects a bad firewall enum" {
  run post_install_validate '{"security":{"firewall":"iptables"}}'
  [ "$status" -ne 0 ]
}

@test "post_install_validate: rejects a non-bool toggle" {
  run post_install_validate '{"security":{"antivirus":"yes"}}'
  [ "$status" -ne 0 ]
}

@test "post_install_validate: accepts an empty object (absent = off)" {
  run post_install_validate '{}'
  [ "$status" -eq 0 ]
}

# ── no-user guard (M5): a non-empty selection needs a Primary User ──────────

@test "post_install_guard_users: passes with a selection and a user" {
  run post_install_guard_users "$(post_install_default)" 1
  [ "$status" -eq 0 ]
}

@test "post_install_guard_users: aborts with a selection but zero users" {
  run post_install_guard_users "$(post_install_default)" 0
  [ "$status" -ne 0 ]
  [[ "$output" == *"user"* ]]
}

@test "post_install_guard_users: passes with zero users when nothing is selected" {
  run post_install_guard_users '{}' 0
  [ "$status" -eq 0 ]
}
