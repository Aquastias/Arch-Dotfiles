#!/usr/bin/env zsh

network_info() {
  echo "--------------- Network Information ---------------"
  ip addr show | awk '/inet / {print "IP Address:",$2} /inet /{print "Netmask:",$4} /ether /{print "MAC Address:",$2}'
  echo "---------------------------------------------------"
}

whatsmyip() {
  local internal_ip external_ip
  internal_ip=$(ip addr show | awk '/inet / {print $2}' | cut -d '/' -f 1)
  echo "Internal IP: ${internal_ip}"
  external_ip=$(curl -s http://ifconfig.me/ip)
  if [ -z "${external_ip}" ]; then
    echo "Failed to retrieve external IP address"
  else
    echo "External IP: ${external_ip}"
  fi
}

alias netinfo='network_info'
alias whatismyip='whatsmyip'
