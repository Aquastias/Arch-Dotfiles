#!/usr/bin/env bats
# Every /usr/local path a program's systemd unit executes is a path that
# program's install.sh actually installs. Regression (Audit Run 20260929):
# rkhunter-scan.service exec'd /usr/local/bin/rkhunter_scan.sh, but the
# script was installed under /usr/local/lib/rkhunter/, so the timer failed.

@test "program units exec only /usr/local paths their install.sh installs" {
  local root="$BATS_TEST_DIRNAME/../../programs" unit program path bad=""
  for unit in "$root"/*/*/services/*.service; do
    [[ -f "$unit" ]] || continue
    program="${unit%/services/*}"
    while IFS= read -r path; do
      grep -qF -- "$path" "$program/install.sh" \
        || bad+="${unit#"$root"/}: $path"$'\n'
    done < <(awk 'match($0, /^Exec[A-Za-z]*=[-@+!:]*\/usr\/local\/[^ ]+/) {
               $0 = substr($0, RSTART, RLENGTH)
               sub(/^Exec[A-Za-z]*=[-@+!:]*/, ""); print
             }' \
               "$unit")
  done
  [[ -z "$bad" ]] || { printf '%s' "$bad"; false; }
}
