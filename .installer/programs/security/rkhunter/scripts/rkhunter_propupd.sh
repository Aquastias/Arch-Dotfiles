#!/usr/bin/env bash
# Run by /etc/pacman.d/hooks/rkhunter-propupd.hook after each package
# transaction: refresh the file properties baseline. rkhunter's own scripts
# trip GNU grep's stray-backslash and egrep warnings; drop those (as
# rkhunter_scan.sh does) so every upgrade's output stays clean.

set -uo pipefail

rkhunter --propupd -q 2>&1 \
  | grep -v -e 'egrep: warning' -e 'grep: warning' || true
