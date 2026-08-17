#!/usr/bin/env bats
# Tests for .os/lib/config/display.sh — the Display Label formatter (PRD
# guided-installer-legion-fixes). Pure: token in, display string out. No fzf,
# no state. Covers curated acronyms, sentence-case + acronym words, the
# first-letter fallback, technical/free-text passthrough, and reverse lookup.

setup() {
  source "$BATS_TEST_DIRNAME/../../lib/config/display.sh"
}

# ── curated acronyms / proper names ──────────────────────────────────────────

@test "curated: single-token acronyms map to their proper casing" {
  [ "$(display_label kde)" = "KDE" ]
  [ "$(display_label gpu)" = "GPU" ]
  [ "$(display_label ssh)" = "SSH" ]
  [ "$(display_label zfs)" = "ZFS" ]
  [ "$(display_label ufw)" = "UFW" ]
  [ "$(display_label lts)" = "LTS" ]
  [ "$(display_label amd)" = "AMD" ]
  [ "$(display_label nvidia)" = "NVIDIA" ]
  [ "$(display_label hyprland)" = "Hyprland" ]
  [ "$(display_label sddm)" = "SDDM" ]
  [ "$(display_label greetd)" = "greetd" ]
}

@test "curated: systemd-boot keeps its literal lower-case proper name" {
  [ "$(display_label systemd-boot)" = "systemd-boot" ]
}

@test "curated: efistub / refind use their canonical stylings (ADR 0077)" {
  [ "$(display_label efistub)" = "EFISTUB" ]
  [ "$(display_label refind)" = "rEFInd" ]
  # grub / limine keep the sentence-case convention
  [ "$(display_label grub)" = "Grub" ]
  [ "$(display_label limine)" = "Limine" ]
}

@test "reverse: curated loader labels resolve back to their tokens" {
  [ "$(display_reverse EFISTUB efistub grub)" = "efistub" ]
  [ "$(display_reverse rEFInd refind grub)" = "refind" ]
}

@test "curated: filesystems (curated wins over the digit passthrough)" {
  [ "$(display_label ext4)" = "Ext4" ]
  [ "$(display_label xfs)" = "Xfs" ]
  [ "$(display_label btrfs)" = "Btrfs" ]
  [ "$(display_label zfs)" = "ZFS" ]
}

@test "curated is case-insensitive on input" {
  [ "$(display_label KDE)" = "KDE" ]
  [ "$(display_label Nvidia)" = "NVIDIA" ]
}

# ── sentence-case + acronym words ────────────────────────────────────────────

@test "multi-word: first letter upper, acronym words upper, rest lower" {
  [ "$(display_label "esp size")" = "ESP size" ]
  [ "$(display_label "age key url")" = "Age key URL" ]
  [ "$(display_label "zfs snapshots")" = "ZFS snapshots" ]
  [ "$(display_label "mirror countries")" = "Mirror countries" ]
  [ "$(display_label "host programs")" = "Host programs" ]
  [ "$(display_label "extra packages")" = "Extra packages" ]
}

# ── first-letter fallback ────────────────────────────────────────────────────

@test "fallback: unknown single word gets first-letter-uppercase" {
  [ "$(display_label hostname)" = "Hostname" ]
  [ "$(display_label zen)" = "Zen" ]
  [ "$(display_label grub)" = "Grub" ]
  [ "$(display_label firewalld)" = "Firewalld" ]
  [ "$(display_label none)" = "None" ]
  [ "$(display_label intel)" = "Intel" ]
}

# ── technical / free-text passthrough ────────────────────────────────────────

@test "passthrough: technical tokens are shown verbatim" {
  [ "$(display_label /dev/sda)" = "/dev/sda" ]
  [ "$(display_label en_US.UTF-8)" = "en_US.UTF-8" ]
  [ "$(display_label Europe/Bucharest)" = "Europe/Bucharest" ]
  [ "$(display_label key=value)" = "key=value" ]
  [ "$(display_label legion5)" = "legion5" ]
  [ "$(display_label 2G)" = "2G" ]
}

@test "empty token stays empty" {
  [ "$(display_label "")" = "" ]
}

# ── reverse lookup ───────────────────────────────────────────────────────────

@test "reverse: display string maps back to the raw candidate" {
  [ "$(display_reverse GPU amd nvidia intel auto gpu)" = "gpu" ]
  [ "$(display_reverse ZFS zfs ext4 xfs btrfs)" = "zfs" ]
  [ "$(display_reverse AMD amd nvidia intel auto)" = "amd" ]
  [ "$(display_reverse Grub systemd-boot grub)" = "grub" ]
}

@test "reverse: no match returns non-zero and empty" {
  run display_reverse Nope amd nvidia
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}
