#!/bin/bash
# End-to-end check against real processes in a throwaway config/state dir. No notifications are sent.
# shellcheck disable=SC2016,SC2034  # check() evals its condition later
set -u
cd "$(dirname "$0")" || exit 1
tmp=$(mktemp -d)
export PROC_WATCHDOG_CONFIG_DIR=$tmp/config PROC_WATCHDOG_STATE_DIR=$tmp/state
mkdir -p "$PROC_WATCHDOG_CONFIG_DIR"
fails=0

config() {
  cat > "$PROC_WATCHDOG_CONFIG_DIR/config" <<EOF
NOTIFY=false
CPU_PERCENT=50
CPU_MINUTES=0
MEM_GB=1000
ORPHAN_PATTERN="pw-test-orphan"
$*
EOF
  rm -rf "$PROC_WATCHDOG_STATE_DIR"
}
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi; }
log() { cat "$PROC_WATCHDOG_STATE_DIR/log" 2>/dev/null; }
orphan() { ( bash -c 'exec -a /tmp/pw-test-orphan/worker.js sleep 60' >/dev/null 2>&1 & ); sleep 0.5; pgrep -f pw-test-orphan; }

yes > /dev/null & hog=$!
trap 'kill $hog 2>/dev/null; pkill -f pw-test-orphan; rm -rf "$tmp"' EXIT
for _ in $(seq 30); do (( $(ps -o pcpu= -p $hog | cut -d. -f1) >= 50 )) && break; sleep 0.5; done

config
./proc-watchdog run
check "alerts on CPU hog" '[ "$(log | grep -c "PID $hog)")" = 1 ]'
./proc-watchdog run
check "does not repeat an alert" '[ "$(log | grep -c "PID $hog)")" = 1 ]'

config 'CPU_MINUTES=60'
./proc-watchdog run
check "waits for CPU_MINUTES" '! log | grep -q "PID $hog)"'

config 'IGNORE="^yes$"'
./proc-watchdog run
check "IGNORE suppresses alert" '! log | grep -q "PID $hog)"'

config 'MEM_GB=0'
./proc-watchdog run
check "alerts on memory" 'log | grep "PID $hog)" | grep -q "GB memory"'

pid=$(orphan)
config
./proc-watchdog run
check "kills orphan" '! kill -0 $pid 2>/dev/null && log | grep -q "Killed orphaned.*PID $pid"'

pid=$(orphan)
config 'ORPHAN_ACTION=notify'
./proc-watchdog run; ./proc-watchdog run
check "notify-only orphan stays alive, alerts once" 'kill -0 $pid && [ "$(log | grep -c "Orphaned.*PID $pid")" = 1 ]'
pkill -f pw-test-orphan

config
./proc-watchdog run
kill $hog; wait $hog 2>/dev/null
./proc-watchdog run
check "forgets processes that exited" '! cut -f1 "$PROC_WATCHDOG_STATE_DIR/notified.tsv" | grep -qx "$hog"'

config 'CPU_PERCENT=lots'
check "rejects bad config" '! ./proc-watchdog run 2>/dev/null'

if [ $fails != 0 ]; then echo "$fails failed"; exit 1; fi
echo "all passed"
