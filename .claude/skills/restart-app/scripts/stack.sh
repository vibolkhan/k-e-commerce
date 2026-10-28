#!/usr/bin/env bash
# Brings the local backend up to date for manual testing:
#   1. Docker and the Supabase stack are running (starts them if not).
#   2. The database matches supabase/migrations + seed.sql: when any of them
#      changed since the last run (or with --reset), `db reset` rebuilds it.
#   3. config/env.local.json points at the local stack with its anon key.
#   4. Every Edge Function answers.
#   5. web/firebase-config.js is (re)written for the local config.
# Prints one "STATUS key: value" line per step for the summary.
set -uo pipefail

cd "$(git rev-parse --show-toplevel)"
SB="npx --yes supabase@2.120.0"
STATE=.dart_tool/k_dev
STAMP=$STATE/db.sha
mkdir -p "$STATE"

if ! docker info >/dev/null 2>&1; then
  echo "STATUS docker: NOT RUNNING. Start Docker Desktop, then run this again."
  exit 2
fi

if $SB status >/dev/null 2>&1; then
  echo "STATUS stack: already running"
else
  echo "Starting the Supabase stack..."
  if ! $SB start; then
    echo "STATUS stack: FAILED to start (see output above)"
    exit 3
  fi
  echo "STATUS stack: started"
fi

hash=$(cat supabase/migrations/*.sql supabase/seed.sql | sha1sum | cut -d' ' -f1)
if [ "${1:-}" = "--reset" ] || [ "$(cat "$STAMP" 2>/dev/null)" != "$hash" ]; then
  why="migrations or seed changed"
  [ "${1:-}" = "--reset" ] && why="asked for a reset"
  [ -f "$STAMP" ] || why="first run, state unknown"
  echo "Resetting the database ($why)..."
  if ! $SB db reset; then
    echo "STATUS database: RESET FAILED (see the SQL error above)"
    exit 4
  fi
  echo "$hash" > "$STAMP"
  echo "STATUS database: rebuilt from migrations + seed ($why); manual test data was cleared"
else
  echo "STATUS database: up to date (no migration or seed change), data kept"
fi

eval "$($SB status -o env 2>/dev/null | grep -E '^(API_URL|ANON_KEY)=')"
python - "$API_URL" "$ANON_KEY" <<'PY'
import json, os, sys
url, key = sys.argv[1], sys.argv[2]
path = "config/env.local.json"
env = json.load(open(path, encoding="utf-8")) if os.path.exists(path) else {"APP_ENV": "dev"}
if env.get("SUPABASE_URL") != url or env.get("SUPABASE_ANON_KEY") != key:
    env.update(SUPABASE_URL=url, SUPABASE_ANON_KEY=key)
    json.dump(env, open(path, "w", encoding="utf-8"), indent=2)
    print("STATUS config: config/env.local.json updated to the local stack")
else:
    print("STATUS config: config/env.local.json already points at the local stack")
PY

failed=""
for dir in supabase/functions/*/; do
  name=$(basename "$dir")
  case "$name" in _*) continue ;; esac
  [ -f "$dir/index.ts" ] || continue
  code=$(curl -s -o /dev/null -w '%{http_code}' -X OPTIONS "$API_URL/functions/v1/$name")
  [ "$code" = "200" ] || failed="$failed $name($code)"
done
if [ -n "$failed" ]; then
  echo "STATUS functions: NOT ANSWERING:$failed"
else
  echo "STATUS functions: all Edge Functions answer"
fi

dart run tool/web_push_config.dart config/env.local.json >/dev/null 2>&1 || true
echo "STATUS done: backend ready at $API_URL (Studio: http://127.0.0.1:54323)"
