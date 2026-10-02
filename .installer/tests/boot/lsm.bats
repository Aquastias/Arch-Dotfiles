#!/usr/bin/env bats
# lsm_cmdline_params (lib/boot/lsm.sh): the kernel LSM fragment every
# Bootloader Adapter appends. Installer-owned (not the apparmor program's
# loader patching), so all five loaders get it — efistub/limine/refind were
# skipped before (Audit Run 20260929). Value per the Arch Wiki AppArmor page.

setup() {
  source "$BATS_TEST_DIRNAME/../../lib/boot/lsm.sh"
}

@test "apparmor selected: the wiki's lsm= order" {
  [ "$(lsm_cmdline_params '{"apparmor":true}')" = \
    "lsm=landlock,lockdown,yama,integrity,apparmor,bpf" ]
}

@test "apparmor off or absent: empty fragment" {
  [ -z "$(lsm_cmdline_params '{"apparmor":false}')" ]
  [ -z "$(lsm_cmdline_params '{}')" ]
}
