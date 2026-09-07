#!/usr/bin/env bats
# Tests for lib/boot/vm-video.sh — vm_video_cmdline_params (deep, pure): the
# Full-HD `video=` kernel-cmdline fragment emitted only inside a VM (ADR 0119),
# never on bare metal (resolution stays autodetected — ADR 0110). The virt type
# is an argument, so the decision is exercised with no VM. Prior art:
# tests/boot/zswap.bats.

setup() {
  source "$BATS_TEST_DIRNAME/../../lib/boot/vm-video.sh"
}

@test "a VM (kvm) gets the Full-HD video floor" {
  run vm_video_cmdline_params kvm
  [ "$status" -eq 0 ]
  [ "$output" = "video=Virtual-1:1920x1080" ]
}

@test "any non-none virt type gets the floor (qemu)" {
  run vm_video_cmdline_params qemu
  [ "$output" = "video=Virtual-1:1920x1080" ]
}

@test "bare metal (none) emits nothing" {
  run vm_video_cmdline_params none
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "absent/empty detection emits nothing (safe default)" {
  run vm_video_cmdline_params
  [ -z "$output" ]
  run vm_video_cmdline_params ""
  [ -z "$output" ]
}
