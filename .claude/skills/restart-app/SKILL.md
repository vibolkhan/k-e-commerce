---
name: restart-app
description: Restart the K app locally so the user can test right away. Brings the Supabase stack up, rebuilds the database when migrations or seed.sql changed, checks the Edge Functions, relaunches the Flutter app (Chrome by default) against the local stack, and reports when it is ready with the logins to use. Use when the user asks to restart, run, relaunch or "let me test" the app, and at the end of every build task (F01–F42) before the summary.
---

# Restart the app for testing

Goal: the user opens nothing and runs nothing. When you finish, the app is
running against an up-to-date local backend and you have told them so.

Run every step yourself. Don't ask for confirmation, except before `--reset`
when the user has said they have test data they want to keep.

## 1. Backend

Run in the foreground (allow up to 10 minutes on a cold start):

```
bash .claude/skills/restart-app/scripts/stack.sh
```

- Add `--reset` when the user asks for a fresh database or clean seed data.
- Every `STATUS` line goes into your report.
- Exit codes:
  - **2:** Docker isn't running. Tell the user to start Docker Desktop and stop here.
  - **3:** the stack failed to start. Show the error and stop.
  - **4:** a migration or the seed failed. Show the SQL error, fix it if it is from the current task, then run the step again.
- `functions: NOT ANSWERING`: restart the runtime with `docker restart supabase_edge_runtime_k-e-commerce`, then run the script once more. If a function still fails, report it; don't block on it.

## 2. App

1. Start the relaunch with the Bash tool, `run_in_background: true`:

   ```
   bash .claude/skills/restart-app/scripts/app.sh
   ```

   The argument is the device: `chrome` (default), `windows`, or a device id. Use another device only when the user asks for it.

   The script stops the previous run first (including its Chrome window) and writes the log to `.dart_tool/k_dev/app.log`.
2. Wait until the log shows the app is up or has failed. Start this with Bash, also `run_in_background: true`; you are notified once it ends:

   ```
   until grep -qE "Flutter run key commands|is being served at|Error:|Failed to|Exception" .dart_tool/k_dev/app.log 2>/dev/null; do sleep 1; done; tail -15 .dart_tool/k_dev/app.log
   ```

   The first build takes about a minute; later ones are faster.
3. Then read the log's last 40 lines.
   - **Compile error:** if it is in code from the current task, fix it and repeat step 2. Otherwise report it.
   - **Up:** go on to the report.

## 3. Report

Keep the report short:

```
App is ready: Chrome window opened (http://localhost:8686).
- Database: <STATUS database line, in plain words>
- Edge Functions: <ok / which failed>
- Log in with (password password123):
  - customer dara@kstore.example
  - business sokha@kstore.example
  - rider vuthy@kstore.example
  - staff:
    - super admin chenda@kstore.example
    - sales dalin@kstore.example
    - support sophea@kstore.example
    - catalog visal@kstore.example
- Studio (to look at data): http://127.0.0.1:54323
```

- Only list the logins that matter for what was just built.
- When the task has a "local-stack check" table in its README, point at it.
- If the database was rebuilt, say that manual test data was cleared.

## Notes

- **Push notifications:** Firebase is skipped (CLAUDE.md), so push is off locally. The inbox and in-app banner still work.
- **Why a restart, not a hot reload:** a code change only needs a restart of the app, but changes to defines, ARB files or migrations need this full run.
- **To stop the app:** `bash .claude/skills/restart-app/scripts/app.sh stop`.
- **Saved state:** the database fingerprint is in `.dart_tool/k_dev/db.sha`. Delete it to force a reset on the next run.
