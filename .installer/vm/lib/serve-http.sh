#!/usr/bin/env bash
# =============================================================================
# vm/lib/serve-http.sh — minimal static-file HTTP/1.0 server (no python)
# =============================================================================
# Serves files from <dir> on <bind>:<port> so the guest can `curl … | bash` the
# installer payload + fetch fixtures. Replaces `python3 -m http.server` (repo
# no-Python policy, docs/agents/no-python.md). socat forks one handler per
# connection; the script re-invokes itself (`--handle`) as that handler.
#
#   serve-http.sh <dir> <bind> <port>        # foreground; background it in the flow
# =============================================================================
set -euo pipefail
SELF="$(readlink -f "$0")"

if [[ "${1:-}" == "--handle" ]]; then
  # Per-connection handler (stdin = request, stdout = response). Read the
  # request line, drain headers, map the path to a file under $SERVE_DIR.
  read -r _method reqpath _proto || exit 0
  while IFS= read -r h; do [[ "$h" == $'\r' || -z "$h" ]] && break; done
  reqpath="${reqpath%%\?*}"; reqpath="${reqpath#/}"     # strip query + leading /
  file="${SERVE_DIR:-.}/${reqpath}"
  if [[ -n "$reqpath" && "$reqpath" != *..* && -f "$file" ]]; then
    size="$(stat -c%s "$file" 2>/dev/null || echo 0)"
    printf 'HTTP/1.0 200 OK\r\nContent-Length: %s\r\nContent-Type: application/octet-stream\r\nConnection: close\r\n\r\n' "$size"
    cat "$file"
  else
    printf 'HTTP/1.0 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n'
  fi
  exit 0
fi

dir="${1:?serve-http.sh <dir> <bind> <port>}"; bind="${2:?}"; port="${3:?}"
command -v socat >/dev/null 2>&1 || { echo "serve-http.sh: socat not found" >&2; exit 1; }
export SERVE_DIR="$dir"
exec socat "TCP-LISTEN:${port},bind=${bind},reuseaddr,fork" "EXEC:${SELF} --handle"
