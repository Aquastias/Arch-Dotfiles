# shellcheck shell=bash
# Feature Audit probe for cups (ADR 0152; contract: PROGRAM_SPEC.md). A real
# job goes end to end: the guest's own `ippeveprinter` (shipped with cups)
# plays an IPP Everywhere printer on localhost, cups drives it driverless.
fa_require_pkg cups cups || return 0
fa_as_root || return 0
fa_check cups-scheduler "cups scheduler running" \
  sh -c 'lpstat -r | grep -q "is running"'
_fa_cups_print() {
  local pid id rc=1
  # -r off: no DNS-SD (the guest runs no avahi; ippeveprinter asserts)
  ippeveprinter -r off -p 8631 -f text/plain,application/pdf fa-audit \
    >/tmp/fa-ippeve.log 2>&1 &
  pid=$!; sleep 3
  if lpadmin -p fa-audit -E -v ipp://localhost:8631/ipp/print -m everywhere
  then
    id="$(echo "Feature Audit test page" | lp -d fa-audit | awk '{print $4}')"
    for _ in $(seq 60); do
      if lpstat -W completed -o fa-audit 2>/dev/null | grep -q "$id"; then
        rc=0; break
      fi
      sleep 1
    done
    ((rc == 0)) || lpstat -l -o fa-audit
    lpadmin -x fa-audit
  fi
  kill "$pid" 2>/dev/null
  return "$rc"
}
fa_check cups-print "test job completes on an IPP Everywhere printer" \
  _fa_cups_print
