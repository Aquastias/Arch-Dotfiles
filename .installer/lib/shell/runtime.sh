#!/usr/bin/env bash
# lib/shell/runtime.sh — post-boot runtime staging helpers

# stage_shell_stdlib [dest] — install the whole Shell Stdlib (the facade AND
# its shell/ modules) under <dest> (default /usr/local/lib), root-owned, so a
# script a unit runs after boot can `source <dest>/shell-stdlib.sh` without
# $SHELL_COMMONS. The facade alone is not enough: it sources its modules.
stage_shell_stdlib() {
  local dest="${1:-/usr/local/lib}" m
  sudo install -d -o root -g root -m 755 "$dest/shell"
  sudo install -o root -g root -m 644 \
    "$SHELL_COMMONS/shell-stdlib.sh" "$dest/shell-stdlib.sh"
  for m in "$SHELL_COMMONS"/shell/*.sh; do
    sudo install -o root -g root -m 644 "$m" "$dest/shell/"
  done
}
