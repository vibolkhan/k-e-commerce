---
name: restart-app
description: Give the user the exact commands to bring the local stack up to date and launch the K app, so they can test. Claude does not run them. Use when the user asks to restart, run, relaunch or "let me test" the app, and at the end of every build task (F01–F42) before the summary.
---

# Commands to test the app

Goal: the user gets a short, copy-paste list of commands that brings the
local backend up to date and starts the app. **Do not run these commands
yourself** (not `stack.sh`, not `app.sh`, not `flutter run`, not
`supabase db reset`). Only print them.

## 1. Decide what to list

- **Backend:** always list `stack.sh`. It starts Docker's Supabase stack if
  needed and rebuilds the database only when `supabase/migrations` or
  `seed.sql` changed since its last run.
- **`--reset`:** add it only if the user asked for a clean database or seed
  data. If the current task changed migrations or the seed, say that the
  database will be rebuilt and manual test data cleared. `stack.sh` does
  that on its own, with no flag.
- **Edge Functions:** if the task changed `supabase/functions`, add
  `docker restart supabase_edge_runtime_k-e-commerce` before the app
  command.
- **Device:** Chrome by default. Use `-d windows` or a device id only when
  the user asks for it.

## 2. Report

Keep it short. Use this shape:

````
Run these from the repo root in Git Bash (or type each with `!` in front here in Claude Code):

```
bash .claude/skills/restart-app/scripts/stack.sh
flutter run -d chrome --dart-define-from-file=config/env.local.json --web-port 8686
```

1. Brings the Supabase stack up and rebuilds the database if migrations or seed changed. Needs Docker Desktop running; each step prints a `STATUS` line.
2. Starts the app at http://localhost:8686 (`r` hot reload, `R` restart, `q` quit).

Log in with (password password123):
- customer dara@kstore.example
- business sokha@kstore.example

Then follow the local-stack checks in delivery/<feature>/README.md.
````

- Only list the logins that matter for what was just built. All seeded
  logins (password `password123`):
  - customer dara@kstore.example
  - business sokha@kstore.example
  - rider vuthy@kstore.example
  - staff:
    - super admin chenda@kstore.example
    - sales dalin@kstore.example
    - support sophea@kstore.example
    - catalog visal@kstore.example
- When the task has a "local-stack check" table in its README, point at it.
- Studio, to look at data: http://127.0.0.1:54323

## If the user reports a problem

Explain what the output means and what to run next; still don't run it.

- `STATUS docker: NOT RUNNING`: start Docker Desktop, then run `stack.sh`
  again.
- Exit 3 (stack failed to start): show the error they pasted and suggest
  `npx supabase stop` then `stack.sh`.
- Exit 4 (migration or seed failed): if the SQL error comes from the
  current task, fix the migration or seed (editing files is fine), then
  give the command again.
- `functions: NOT ANSWERING`: `docker restart supabase_edge_runtime_k-e-commerce`,
  then `stack.sh` once more.
- A compile error in `flutter run` from the current task's code: fix the
  code, then tell them to press `R` or run the command again.

## Notes

- **Push notifications:** Firebase is skipped (CLAUDE.md), so push is off
  locally. The inbox and in-app banner still work.
- **Hot reload isn't enough** after changes to defines, ARB files or
  migrations: quit with `q` and run both commands again.
- **Saved state:** the database fingerprint is in `.dart_tool/k_dev/db.sha`.
  Deleting it forces a rebuild on the next `stack.sh`.
- `scripts/app.sh` (background run with a log in `.dart_tool/k_dev/app.log`)
  is kept for unattended use, but the list above uses `flutter run` so the
  user sees the output and keeps hot reload.
