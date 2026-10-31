# K E-Commerce — project guide for Codex

## Workflow

- Work on the `dev` branch. Put documentation you produce in `delivery/<feature-name>/`.
- For every task, read the referenced docs and screens, share a short plan and assumptions, implement the task, verify it, and finish with a summary covering what was built, how to test it, and anything left or blocked.
- At the end of every build task (F01–F42), read and follow `.claude/skills/restart-app/SKILL.md` before the final summary. Despite its Claude-oriented name, it is the project's source of truth for the exact test commands. Do not run its restart, reset, or launch commands; give the user the appropriate commands as instructed by the skill.
- Tasks F01–F42 come from the "K Build Plan" tracker. Build only what the current task asks for.

## Source of truth

- PRD: `delivery/prd/K_E-Commerce_PRD_v1.0.docx` (requirement IDs such as CHK-04).
- App flow: `delivery/app-flow/K_E-Commerce_App_Flow_v1.0.docx` (flows F0–F14, screen IDs, and business rules).
- UI design: "K E-Commerce UX/UI Design" canvas plus the `K_UX-UI_Screens` export. Screen IDs match the tasks. Design tokens live in `k-ui.css`.
- Read DOCX files with `pandoc -t markdown <file>.docx`.

## Stack

- Flutter (Dart ^3.11), with one codebase and role-based entry points for the customer app (iOS, Android, web), admin back office (web and mobile), and rider app.
- Riverpod for state and `go_router` for routing with role guards.
- Supabase: Postgres with Row-Level Security on every table; Auth (phone OTP, email, Google, Apple); Storage; Realtime; and Edge Functions (TypeScript) for anything involving money, stock, or status changes.
- Firebase Cloud Messaging for push. **Skipped for now (decided 2026-10-27):** there is no Firebase project, key, or FCM secret yet. The app runs without push; inbox and in-app banners still work. Do not block tasks on Firebase or ask for its setup. Owner steps are in `delivery/f07-push-inbox/README.md`.

## Supabase connection

- This project uses the local Supabase CLI stack defined by `supabase/config.toml`; it does not require a Supabase MCP server.
- Local endpoints are API `http://127.0.0.1:54321`, Postgres port `54322`, and Studio `http://127.0.0.1:54323`.
- Application connection values belong in the gitignored `config/env.local.json`. Use `config/env.example.json` as the template and never place keys, access tokens, service-role credentials, or passwords in `AGENTS.md` or committed configuration.
- `.claude/skills/restart-app/scripts/stack.sh` starts the stack, applies migrations and seed data when needed, and refreshes `config/env.local.json` with the current local API URL and anonymous key. Follow the workflow rule above: provide this command to the user at the end of build tasks; do not run it automatically.
- Use migrations, seed files, Edge Functions, and RLS policies in the repository as the source of truth. Do not make untracked schema changes through Studio.

## GitHub connection

- The repository remote is `origin` at `https://github.com/vibolkhan/k-e-commerce.git`; normal fetch, pull, push, and branch operations use the developer's existing Git credentials.
- Work on the `dev` branch unless the user explicitly requests another branch or workflow.
- Never store GitHub tokens, credentials, or personal access tokens in this repository or in `AGENTS.md`.
- Do not push commits, create branches, open pull requests, merge, or modify GitHub issues unless the user explicitly asks for that external action.
- GitHub CLI and a GitHub MCP/plugin connection are optional. If a task requires pull requests, issues, checks, or other GitHub API operations and no connector is available, explain what connection is missing and ask the user before installing or connecting one.

## Market rules

- Cambodia only. Prices are in USD including 10% VAT; KHR is shown using the rate in settings (default 4,100).
- Same-day delivery cut-off is 3:00 PM (UTC+7, server time); delivery hours are 9:00 AM–8:00 PM.
- Payments: Bakong KHQR and cash on delivery (COD limit $200 per order, with per-zone override). Bank transfer is for business buyers only. ABA PayWay is next phase; keep payment providers behind an interface.
- Hold stock for 15 minutes for unpaid KHQR orders.
- Returns are allowed within 3 days; the customer pays a $2.00 return fee.
- Business buyers never see retail prices; they buy through quote requests (RFQ).

## Design

- Keep the UI clean and airy. Primary `#0272B6` (buttons and links), brand sky `#0EA5E9` (logo only), ink `#0F172A`, background `#F8FAFC`, and lines `#E2E8F0`.
- Use radius 12 for inputs and buttons, 16 for cards, and 24 for sheets. Use Plus Jakarta Sans, with Kantumruy Pro for Khmer.
- Touch targets must be at least 44 px and text contrast at least 4.5:1. Every destructive or money-related action requires confirmation.

## Engineering rules

- Use feature-first folders: `lib/features/<feature>/{data,domain,presentation}`. Put shared UI in `lib/core/ui`.
- Put every user-facing string in the English and Khmer ARB files; do not hard-code UI copy.
- The client must never decide money, stock, or order status. Call an Edge Function and validate on the server.
- Add or extend SQL migrations in `supabase/migrations`, including RLS policies and tests.
- Write unit and widget tests for new work. Run `flutter analyze` and `flutter test` until clean.
- Keep commits small with clear messages. Do not touch features outside the current task except to fix regressions caused by the task.
