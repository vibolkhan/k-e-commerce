# K E-Commerce — project guide for Claude Code

## Workflow
- Work on the `dev` branch. Docs you produce go in `delivery/<feature-name>/`.
- For every task: read the docs and screens it lists, post a short plan and your assumptions, then build, then finish with a summary — what was built, how to test it, anything left or blocked.
- When a task is built, run the `restart-app` skill before the summary. It rebuilds the database if migrations or seed changed, relaunches the app against the local stack, and tells the user it is ready to test.
- Build plan: tasks F01–F42 come from the "K Build Plan" tracker. Only build what the current task asks.

## Source of truth
- PRD: `delivery/prd/K_E-Commerce_PRD_v1.0.docx` (requirement IDs like CHK-04)
- App flow: `delivery/app-flow/K_E-Commerce_App_Flow_v1.0.docx` (flows F0–F14, screen IDs, business rules)
- UI design: "K E-Commerce UX/UI Design" canvas + `K_UX-UI_Screens` export (screen IDs match the tasks). Design tokens: `k-ui.css`.
- Read docs with: `pandoc -t markdown <file>.docx`

## Stack
- Flutter (Dart ^3.11), one codebase with role-based entry: customer app (iOS/Android/web), admin back-office (web + mobile), rider app.
- Riverpod for state; go_router for routing with role guards.
- Supabase: Postgres with Row-Level Security on every table; Auth (phone OTP, email, Google, Apple); Storage; Realtime; Edge Functions (TypeScript) for anything involving money, stock or status changes.
- Firebase Cloud Messaging for push. **Skipped for now (decided 2026-10-27):** no Firebase project, keys or FCM secrets yet. The app runs without push (inbox and in-app banner still work). Don't block tasks on Firebase or ask for its setup; owner steps are in `delivery/f07-push-inbox/README.md`.

## Market rules
- Cambodia only. Prices in USD incl. 10% VAT; KHR shown at the rate in settings (default 4,100).
- Same-day delivery cut-off 3:00 PM (UTC+7, server time); deliveries 9 AM–8 PM.
- Payments: Bakong KHQR and cash on delivery (COD limit $200/order, per-zone override). Bank transfer for business buyers only. ABA PayWay is next phase — keep payment providers behind an interface.
- Stock is held 15 minutes for unpaid KHQR orders.
- Returns within 3 days; $2.00 return fee paid by the customer.
- Business buyers never see retail prices — they buy through quote requests (RFQ).

## Design
- Clean and airy. Primary #0272B6 (buttons/links), brand sky #0EA5E9 (logo only), ink #0F172A, background #F8FAFC, lines #E2E8F0.
- Radius 12 inputs/buttons, 16 cards, 24 sheets. Font Plus Jakarta Sans (Khmer: Kantumruy Pro).
- Touch targets ≥ 44 px, text contrast ≥ 4.5:1. Every destructive or money action asks for confirmation.

## Engineering rules
- Feature-first folders: `lib/features/<feature>/{data,domain,presentation}`; shared UI in `lib/core/ui`.
- All user-facing strings in ARB files (English + Khmer); no hard-coded copy.
- The client never decides money, stock or order status — call an Edge Function and validate on the server.
- Add/extend SQL migrations in `supabase/migrations` with RLS policies and tests for them.
- Write unit + widget tests for what you build; run `flutter analyze` and `flutter test` until clean.
- Keep commits small with clear messages. Don't touch features outside the current task except to fix what you break.
