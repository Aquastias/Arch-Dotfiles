#!/usr/bin/env bats
# rkhunter_scan.sh under set -e (Audit Run 20261003): `rkhunter --update`
# exits 2 after installing updates and 1 on a download error (rkhunter(8)),
# which killed the daily scan before it ran.

setup() {
  T="$(mktemp -d)"
  mkdir -p "$T/bin"
  # Stub stdlib + rkhunter; --update exits $UPDATE_RC, --check records a run.
  printf '%s\n' 'check_root() { :; }' 'print_status() { :; }' \
    'send_user_notification() { :; }' > "$T/stdlib.sh"
  cat > "$T/bin/rkhunter" <<STUB
#!/usr/bin/env bash
case "\$1" in
  --update) exit "\$UPDATE_RC" ;;
  --check) echo checked >> "$T/ran" ;;
esac
STUB
  chmod +x "$T/bin/rkhunter"
  local S=rkhunter_scan.sh
  sed -e "s|/usr/local/lib/shell-stdlib.sh|$T/stdlib.sh|" \
    -e "s|SYSTEM_LOG=\"/var/log/rkhunter.log\"|SYSTEM_LOG=\"$T/log\"|" \
    "$BATS_TEST_DIRNAME/../../programs/security/rkhunter/scripts/${S}" \
    > "$T/scan.sh"
}

teardown() { rm -rf "$T"; }

@test "updates installed (--update exit 2): the scan still runs" {
  UPDATE_RC=2 PATH="$T/bin:$PATH" run bash "$T/scan.sh"
  [ "$status" -eq 0 ]
  [ -f "$T/ran" ]
}

@test "download error (--update exit 1): the scan runs on existing data" {
  UPDATE_RC=1 PATH="$T/bin:$PATH" run bash "$T/scan.sh"
  [ "$status" -eq 0 ]
  [ -f "$T/ran" ]
}
