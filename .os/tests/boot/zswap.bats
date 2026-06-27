#!/usr/bin/env bats
# Tests for lib/boot/zswap.sh — zswap_cmdline_params (deep, pure).
#
# Maps the Install State wire format to the zswap kernel cmdline fragment.
# Pure JSON-in / string-out, so behaviour is asserted on the emitted string.

setup() {
  # shellcheck source=../../lib/boot/zswap.sh
  source "$BATS_TEST_DIRNAME/../../lib/boot/zswap.sh"
}

@test "swap + zswap on → full fragment with defaults reflected" {
  run zswap_cmdline_params \
    '{"swap":true,"zswap":{"enabled":true,"compressor":"zstd","max_pool_percent":20}}'
  [ "$status" -eq 0 ]
  [ "$output" = "zswap.enabled=1 zswap.compressor=zstd zswap.max_pool_percent=20" ]
}

@test "custom compressor + percent are reflected" {
  run zswap_cmdline_params \
    '{"swap":true,"zswap":{"enabled":true,"compressor":"lz4","max_pool_percent":40}}'
  [ "$output" = "zswap.enabled=1 zswap.compressor=lz4 zswap.max_pool_percent=40" ]
}

@test "zswap off → empty (no fragment)" {
  run zswap_cmdline_params \
    '{"swap":true,"zswap":{"enabled":false,"compressor":"zstd","max_pool_percent":20}}'
  [ "$output" = "" ]
}

@test "swap off → empty even when zswap enabled (needs a backing device)" {
  run zswap_cmdline_params \
    '{"swap":false,"zswap":{"enabled":true,"compressor":"zstd","max_pool_percent":20}}'
  [ "$output" = "" ]
}

@test "never emits a zswap.zpool token" {
  run zswap_cmdline_params \
    '{"swap":true,"zswap":{"enabled":true,"compressor":"zstd","max_pool_percent":20}}'
  ! echo "$output" | grep -q "zpool"
}

@test "missing compressor / percent fall back to zstd / 20" {
  run zswap_cmdline_params '{"swap":true,"zswap":{"enabled":true}}'
  [ "$output" = "zswap.enabled=1 zswap.compressor=zstd zswap.max_pool_percent=20" ]
}
