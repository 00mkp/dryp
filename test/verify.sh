#!/usr/bin/env bash
# End-to-end checks on a real machine with dryp installed (./install.sh --nosleep).
# Takes about 4 minutes: two checks wait for a 1-minute session to expire.
set -uo pipefail

PASS=0; FAIL=0
ok()   { printf '  ok    %s\n' "$1"; PASS=$((PASS + 1)); }
bad()  { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL + 1)); }
sleep_disabled() { pmset -g live | awk '/SleepDisabled/{print $2}'; }
held() { pmset -g assertions | grep -c "dryp caf" || true; }
TARGET="gui/$(id -u)/io.github.00mkp.dryp"
agent_pid() { launchctl print "$TARGET" 2>/dev/null | awk '/^\tpid = /{print $3}'; }

command -v dryp >/dev/null || { echo "dryp isn't on PATH; install it first"; exit 2; }

BACKUP=""        # set while the sudoers rule is moved aside
CLEANED=0
cleanup() {
  (( CLEANED )) && return 0
  CLEANED=1
  if [[ -n "$BACKUP" && -e "$BACKUP" ]]; then
    if sudo mv "$BACKUP" /etc/sudoers.d/dryp; then
      rmdir "$(dirname "$BACKUP")" 2>/dev/null || true
    else
      echo "WARNING: couldn't restore the sudoers rule; it is saved at $BACKUP (copy it to /etc/sudoers.d/dryp)"
    fi
  fi
  dryp off >/dev/null 2>&1 || true
  if [[ "$(sleep_disabled)" == 1 ]]; then
    sudo -k -n /usr/bin/pmset -a disablesleep 0 >/dev/null 2>&1 || true
    if [[ "$(sleep_disabled)" == 1 ]]; then
      echo "WARNING: sleep is still disabled — run: sudo pmset -a disablesleep 0"
    fi
  fi
}
trap cleanup EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

dryp off >/dev/null 2>&1 || true

echo "caf"
dryp caf 1 >/dev/null && [[ "$(held)" -ge 4 ]] && ok "caf 1 holds four assertions" || bad "caf 1 holds four assertions"
sleep 70
[[ "$(held)" -eq 0 ]] && ok "caf assertions released after a minute" || bad "caf assertions released after a minute"

echo "nosleep"
dryp nosleep 1 >/dev/null && [[ "$(sleep_disabled)" == 1 ]] && ok "nosleep 1 sets SleepDisabled 1" || bad "nosleep 1 sets SleepDisabled 1"
sleep 70
[[ "$(sleep_disabled)" == 0 ]] && ok "SleepDisabled back to 0 after a minute" || bad "SleepDisabled back to 0 after a minute"

echo "crash during nosleep"
dryp nosleep 1 >/dev/null
PID="$(agent_pid)"
if [[ -z "$PID" ]]; then
  bad "agent wasn't running before the crash test"
else
  kill -9 "$PID"
  NEW=""
  for _ in $(seq 1 15); do
    NEW="$(agent_pid)"
    [[ -n "$NEW" && "$NEW" != "$PID" ]] && break
    sleep 1
  done
  [[ -n "$NEW" && "$NEW" != "$PID" ]] && ok "launchd restarted the agent" || bad "launchd restarted the agent"
  [[ "$(sleep_disabled)" == 1 ]] && ok "nosleep survived the crash" || bad "nosleep survived the crash"
  sleep 70
  [[ "$(sleep_disabled)" == 0 ]] && ok "restarted agent still restored sleep on time" || bad "restarted agent still restored sleep on time"
fi

echo "app stop during nosleep"
dryp nosleep 2 >/dev/null
dryp app stop >/dev/null && [[ "$(sleep_disabled)" == 0 && -z "$(agent_pid)" ]] \
  && ok "app stop restored sleep and exited" || bad "app stop restored sleep and exited"
dryp app start >/dev/null && [[ -n "$(agent_pid)" ]] && ok "app start brought it back" || bad "app start brought it back"

echo "nosleep without the sudoers rule"
if sudo -n true 2>/dev/null || [[ -t 0 ]]; then
  if ! sudo test -f /etc/sudoers.d/dryp; then
    echo "  skip  (no sudoers rule installed)"
  else
    BACKUP="$(mktemp -d)/dryp.sudoers.bak"
    if sudo cp -p /etc/sudoers.d/dryp "$BACKUP" && sudo rm /etc/sudoers.d/dryp; then
      OUT="$(dryp nosleep 5 2>&1)"; CODE=$?
      [[ $CODE -eq 1 && "$OUT" == *"isn't set up"* ]] && ok "clean rejection, exit 1" || bad "clean rejection, exit 1 (got $CODE: $OUT)"
      [[ "$(sleep_disabled)" == 0 ]] && ok "sleep untouched" || bad "sleep untouched"
    else
      bad "couldn't move the sudoers rule aside"
    fi
    sudo mv "$BACKUP" /etc/sudoers.d/dryp 2>/dev/null
    if sudo test -f /etc/sudoers.d/dryp; then
      rmdir "$(dirname "$BACKUP")" 2>/dev/null || true
      BACKUP=""
    else
      bad "SUDOERS RULE NOT RESTORED: copy $BACKUP to /etc/sudoers.d/dryp"
    fi
  fi
else
  echo "  skip  (needs sudo to move the rule aside)"
fi

dryp off >/dev/null 2>&1 || true
echo
echo "$PASS passed, $FAIL failed"
(( FAIL == 0 ))
