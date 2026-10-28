#!/usr/bin/env bash
# Stops the Flutter app this skill started before, then runs it again
# against the local stack. Meant to be started in the background; the log
# goes to .dart_tool/k_dev/app.log.
#
#   app.sh [device]   device: chrome (default), windows, or a device id
#   app.sh stop       only stop the previous run
set -uo pipefail

cd "$(git rev-parse --show-toplevel)"
STATE=.dart_tool/k_dev
LOG=$STATE/app.log
PORT=8686
mkdir -p "$STATE"

stop_previous() {
  # The web run listens on $PORT; its process tree includes the debug Chrome.
  for pid in $(netstat -ano 2>/dev/null | grep -E "[:.]$PORT[[:space:]].*LISTENING" | awk '{print $NF}' | sort -u); do
    taskkill //PID "$pid" //T //F >/dev/null 2>&1 || true
  done
  if [ -f "$STATE/app.pid" ]; then
    taskkill //PID "$(cat "$STATE/app.pid")" //T //F >/dev/null 2>&1 || true
    rm -f "$STATE/app.pid"
  fi
}

stop_previous
[ "${1:-}" = "stop" ] && { echo "stopped"; exit 0; }

device=${1:-chrome}
args=(run -d "$device" --dart-define-from-file=config/env.local.json)
[ "$device" = "chrome" ] && args+=(--web-port "$PORT")

flutter pub get >"$LOG" 2>&1
echo "== flutter ${args[*]}" >>"$LOG"
flutter "${args[@]}" >>"$LOG" 2>&1 &
echo $! >"$STATE/app.pid"
wait
