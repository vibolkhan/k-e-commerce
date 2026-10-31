# F14 · Home content: banners & collections

## Built

- A-12 is now a real guarded admin route at `/admin/content`, with tabs for banners, curated collections, and static pages.
- A-12a creates and edits bilingual banners, audience, link target, start/end schedule, visibility, and Storage-backed background images. The editor includes the phone preview from the design.
- Collections can be activated or hidden. Terms, privacy, FAQ, returns, and delivery pages can be edited and published from the Pages tab.
- Public banner reads remain protected by Postgres RLS: only active rows whose start/end window contains database `now()` are visible. The app still applies the retail/business audience filter.
- Home requeries banners every 30 seconds, so a scheduled banner appears shortly after its server-side start time without an app release or restart.
- Banner changes are published through Supabase Realtime, and the schedule query has a partial index.

## Verification

- `flutter analyze` — clean.
- `flutter test test/features/content/content_domain_test.dart` — passed (schedule states, UTC persistence, audience and bilingual data).
- Full `flutter test` — 451 functional tests passed; 10 pre-existing golden comparisons failed because this machine renders the shared UI baselines differently. F14 does not change the shared design-system widgets or those golden files.
- `supabase/tests/database/18_content_admin.test.sql` covers future/ended banner visibility and catalog/support write permissions. It was not run because the local Supabase stack is not fully running and project rules prohibit Codex from restarting it automatically.

## Manual acceptance

1. Open `/admin/content` as catalog staff or a super admin.
2. Create a banner starting one minute in the future, choose its audience and link, and save it.
3. Open the matching retail or business Home. The banner must remain absent before its start and appear within 30 seconds after it.
4. Verify the other audience does not see it, and that ending or hiding it removes it on the next refresh.
