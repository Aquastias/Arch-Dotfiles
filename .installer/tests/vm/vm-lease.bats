#!/usr/bin/env bats
# Tests for vm/lib/vm-lease.sh — the domain's current IPv4 address. A
# reinstalled guest asks DHCP with a new client id, so the live ISO's lease
# outlives the boot that took it: the newest lease is the current one.

setup() {
  # shellcheck source=../../vm/lib/vm-lease.sh
  source "$BATS_TEST_DIRNAME/../../vm/lib/vm-lease.sh"
  DOMIFLIST=' Interface   Type      Source    Model    MAC
-------------------------------------------------------------
 -           network   default   virtio   52:54:00:98:93:04'
  LEASES=' Expiry Time           MAC address         Protocol   IP address           Hostname   Client ID or DUID
-------------------------------------------------------------------------------------------
 2026-11-12 11:58:24   52:54:00:98:93:04   ipv4       192.168.122.199/24   archiso    ff:00
 2026-11-12 12:58:24   52:54:00:98:93:04   ipv4       192.168.122.200/24   arch       01:52
 2026-11-12 13:30:00   52:54:00:aa:bb:cc   ipv4       192.168.122.50/24    other      01:aa'
  virsh() {
    case "$1" in
      domiflist) printf '%s\n' "$DOMIFLIST" ;;
      net-dhcp-leases) [[ "$2" == default ]] && printf '%s\n' "$LEASES" ;;
      domifaddr) printf '%s\n' "${DOMIFADDR:-}" ;;
    esac
  }
}

@test "vm_lease_ip: the newest lease of the domain's MAC wins" {
  run vm_lease_ip vm
  [ "$status" -eq 0 ]
  [ "$output" = "192.168.122.200" ]
}

@test "vm_lease_ip: one lease is that lease" {
  LEASES="$(printf '%s\n' "$LEASES" | head -n 3)"
  run vm_lease_ip vm
  [ "$output" = "192.168.122.199" ]
}

@test "vm_lease_ip: no lease yet prints nothing" {
  LEASES=''
  run vm_lease_ip vm
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "vm_lease_ip: a NIC not on a libvirt network falls back to domifaddr" {
  DOMIFLIST=' Interface   Type      Source    Model    MAC
-------------------------------------------------------------
 vnet0       bridge    br0       virtio   52:54:00:98:93:04'
  DOMIFADDR=' Name       MAC address          Protocol     Address
-------------------------------------------------------------------------------
 vnet0      52:54:00:98:93:04    ipv4         10.0.0.7/24'
  run vm_lease_ip vm
  [ "$output" = "10.0.0.7" ]
}
