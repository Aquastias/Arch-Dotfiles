#!/usr/bin/env bash
# =============================================================================
# vm/lib/vm-lease.sh — a VM's current IPv4 address
# =============================================================================
# A reinstalled guest asks DHCP with a new client id, so the live ISO's lease
# outlives the boot that took it: `virsh domifaddr` then lists the stale
# address first. The lease given last (the latest expiry) is the current one.
#
# Used by: vm/lib/core.sh (_core_vm_ip_now), vm/vm-agent.sh (_vm_ip).
# =============================================================================

# vm_lease_ip <domain> — the domain's current IPv4 address ("" when it has
# none yet): the newest DHCP lease of its first NIC on a libvirt network,
# else (a bridged NIC) the first address `virsh domifaddr` reports.
vm_lease_ip() {
  local _interface type network _model mac=""
  # The first NIC row of `virsh domiflist`: interface, type, source, model,
  # MAC (the header and rule lines are skipped by the type test).
  while read -r _interface type network _model mac; do
    [[ "$type" == network && -n "$mac" ]] && break
  done < <(virsh domiflist "$1" 2>/dev/null)
  if [[ "$type" != network || -z "$mac" ]]; then
    _vm_lease_first_address "$1"
    return 0
  fi
  local day time lease_mac protocol address _rest newest="" current=""
  # Lease rows: expiry day, expiry time, MAC, protocol, address/prefix, …
  while read -r day time lease_mac protocol address _rest; do
    [[ "$lease_mac" == "$mac" && "$protocol" == ipv4 ]] || continue
    # ISO dates and times compare as text.
    [[ "$day $time" > "$newest" ]] || continue
    newest="$day $time"
    current="$address"
  done < <(virsh net-dhcp-leases "$network" 2>/dev/null)
  [[ -n "$current" ]] || return 0
  # The address without its /prefix.
  printf '%s\n' "$current" | cut -d/ -f1
}

# _vm_lease_first_address <domain> — the first IPv4 address `virsh
# domifaddr` reports ("" when none).
_vm_lease_first_address() {
  local _name _mac protocol address
  # Rows: name, MAC, protocol, address/prefix.
  while read -r _name _mac protocol address; do
    [[ "$protocol" == ipv4 ]] || continue
    printf '%s\n' "$address" | cut -d/ -f1
    return 0
  done < <(virsh domifaddr "$1" 2>/dev/null)
  return 0
}
