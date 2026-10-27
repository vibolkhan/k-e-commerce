# F08 — Admin back-office shell & staff roles

This is the frame every back-office screen sits in, with permissions enforced. Each staff role sees only its sections, and the server refuses everything else.
- Requirements: ADM-09 (staff roles in settings), AUTH-06 (role-based access, enforced by RLS).
- Screens: CmpAdminSidebar, CmpAdminTopbar, CmpAdminNav, A-14d, A-14e, M-05.

## Who can open what (A-14d)

| Section | Super admin | Sales | Support | Catalog |
|---|---|---|---|---|
| Dashboard | ✓ | ✓ | ✓ | ✓ |
| Orders | Full | Full | View | — |
| RFQs & quotes | Full | Full | — | — |
| Returns & refunds | Full | — | Full | — |
| Products, Inventory | Full | View | View | Full |
| Customers & verification | Full | Full | View | — |
| Riders & cash | Full | — | — | — |
| Reviews / Content | Full | — | Reviews | Content |
| Support chat | Full | — | Full | — |
| Reports | Full | Sales & RFQ | — | Stock |
| Settings (incl. Staff & roles) | Full | — | — | — |

The client copy of this table is `staffMatrix` in `lib/features/admin/domain/staff_permissions.dart`. The sidebar, the bottom nav, M-05, the router and the A-14d matrix all read it. The server enforces the same split with RLS and Edge Functions:
- `supabase/tests/database/06_staff.test.sql` and `12_staff_admin.test.sql` check every role.
- "View" means read-only: those roles have no write policy on that area.

## Shell

| Width | Layout |
|---|---|
| ≥ 1024 px | Sidebar (248 px) and top bar. The sidebar has K Admin, the store, and the permitted sections grouped Sales / Catalog / People / Insights, with count badges. The top bar has search ("/" focuses it), the same-day cut-off countdown, help, notifications, and an account menu with Language and Sign out. |
| < 1024 px | An app bar with the bell, and a bottom nav with Dashboard, Orders, RFQs, Chat and More. Tabs the role can't open are left out, so catalog staff get Dashboard and More. M-05 More lists the remaining sections, then Language and Sign out. The dashboard shows the cut-off pill, because phones have no top bar. |

- **Badges** come from `admin_badge_counts()`, which runs as the caller, so RLS scopes every count. They refresh on every navigation and every 60 s:
  - red: orders `confirmed` or `awaiting_bank_transfer`; low or out-of-stock active variants; open unassigned support chats;
  - blue: RFQs `submitted` or `revision_requested`; returns `requested`; pending business verifications; pending reviews.
- **Cut-off countdown:** "Same-day cut-off in 4h 35m" counts down in Phnom Penh time to `app_settings.same_day_cutoff` (default 15:00). After the cut-off it reads "Cut-off passed · next-day delivery". It is display only; the server decides the delivery day.
- **Routes:**
  - `/admin` is the dashboard;
  - `/admin/{orders,rfqs,returns,catalog,inventory,content,customers,riders,reviews,chat,reports}`;
  - `/admin/settings` (Store setup list) and `/admin/settings/staff` (A-14d);
  - `/admin/more`, `/admin/inbox` (F07 inbox) and `/admin/pending`.
  - Sections from later tasks show a placeholder with their screen id.
- **Redirects** (`adminRedirect` in `lib/core/router/app_router.dart`, which is pure):
  - A section the role can't open shows No access, the same page as another role's shell.
  - Staff without an active membership (expired invite or removed) only get `/admin/pending`.
  - Email invitees who haven't set a password go to `/sign-in/set-password` first (`accountRedirect`).

## Staff lifecycle

```
supabase/
  migrations/20261031000100_staff_admin.sql
    staff_members.invited_at / invite_expires_at; status active | invited | removed
    no direct writes to staff_members (even super admins); audit trigger stays
    on_auth_user_signed_in       invited + not expired → active on first sign-in
    keep_a_super_admin           refuses leaving no active super admin
    staff_directory()            A-14d list, super admin only (42501 otherwise)
    admin_badge_counts()         security invoker
    staff_member_info / staff_account_for   service-role lookups for staff-manage
    private.dev_sms_messages + dev_record_sms   local invite-SMS outbox
    reads tightened to the matrix: profiles (catalog: staff only), addresses,
      riders, rider_locations (sales/support), rider_zones (super admin)
  functions/
    _shared/staff_flows.ts       the rules (pure, unit-tested)
    _shared/staff_deps.ts        service-role wiring
    _shared/sms.ts               SmsSender: TwilioSmsSender | DevOutboxSmsSender
    staff-manage/                gateway JWT on
  tests/database/12_staff_admin.test.sql
```

### `staff-manage`

The caller must be an active super admin; anyone else gets `forbidden`. With no session the answer is 401, and a malformed body is 400.

| Action | Body | Results |
|---|---|---|
| `invite` | `full_name`, `contact` (email or Cambodian phone), `role` | `invited` (+ `profile_id`, `expires_at`), `invalid` (+ `field`), `account_exists`, `already_staff`, `send_failed` |
| `resend` | `profile_id` | `resent` (+ `expires_at`), `not_invited`, `not_found`, `send_failed` |
| `update_role` | `profile_id`, `role` | `updated`, `invalid`, `self`, `last_super_admin`, `not_found` |
| `remove` | `profile_id` | `removed`, `self`, `last_super_admin`, `not_found` |

- **Invite by email:** the function creates the auth user with `needs_password` in the user metadata and sends Auth's invite email, which redirects to `APP_WEB_URL/sign-in/set-password`. Someone who has signed in before, such as a re-invited member, gets a sign-in link instead. After the link signs them in, they choose a password once (`/sign-in/set-password`) and use S-04b from then on.
- **Invite by phone:** the function creates the auth user with the phone confirmed and sends an SMS through `SmsSender`: "K Admin: Chenda Lim invited you to the K back-office as Support. Open … /sign-in and sign in with this number. The invite expires on 3 Nov 2026." They sign in with a code as usual.
- **Both:** `profiles.role` becomes `staff`, and `staff_members` is set to `invited` with a 7-day expiry. The first sign-in before it expires makes them `active`.
- **Existing accounts:** a customer, business or rider account is refused with `account_exists`; it is never converted. Current staff get `already_staff`. Removed staff can be invited again.
- **Remove** sets `removed` and bans the auth user, so their sessions end and they can't sign in. A new invite lifts the ban.
- **Nobody edits or removes themselves**, and the last active super admin can't be demoted or removed. The database trigger refuses that too.

### App (A-14d, A-14e, edit)

- **A-14d** shows the store-setup sub-nav, then the staff table (cards on phones) and the read-only matrix with the "enforced on the server" note.
  - Each row has initials, name, contact (with "you"), role, last active, and a status pill (Active / Pending / Expired).
  - Pending rows get Resend; the others get Edit. Your own row's Edit is disabled.
- **A-14e** has the name, email or phone (checked like the server does), and the four role cards with what each covers. Server refusals show in the modal.
- **Edit** lets you change the role (after a "Change role?" confirmation) or Remove from staff (after a red "Remove …?" confirmation).

## Testing it

```
flutter analyze && flutter test --exclude-tags golden   # 262 tests
supabase test db                                         # 266 pgTAP tests incl. 12_staff_admin
cd supabase/functions && deno test _shared/              # 57 tests incl. staff_flows_test, sms_test
```

- `test/features/admin/admin_domain_test.dart` covers:
  - each role's sections;
  - `adminRedirect` for every role × section, More and the inbox, and inactive staff;
  - the cut-off (before, at and after, across midnight UTC);
  - labels, contact normalising, and the staff-manage answers.
- `admin_shell_test.dart`:
  - **for each role, the sidebar shows only its sections, and every other section's deep link is No access**;
  - badges, groups, the countdown and after 3 PM, "/" to search, sign out;
  - the phone bottom nav (catalog gets Dashboard + More), M-05;
  - a lapsed invite sees only the pending page.
- `staff_roles_test.dart` covers:
  - the A-14d list and matrix, on desktop and phone;
  - Resend, and sales getting No access;
  - A-14e validation, a phone invite and a server refusal;
  - role change and removal with their confirmations, and the last-super-admin message;
  - the set-password step.

Checked on the local stack (`supabase start`, `supabase functions serve`, seed password `password123`):

| Call | Result |
|---|---|
| As dalin (sales) | `forbidden` |
| As chenda: invite `sokim@kstore.example` (catalog) | `invited`, invite email in Mailpit |
| As chenda: invite `097 111 2233` (support) | `invited`, SMS in `private.dev_sms_messages` |
| Invite `dara@kstore.example` | `account_exists` |
| Resend Rachana (signed in before) | `resent`, sign-in link email |
| Remove chenda (herself) | `self` |
| Dalin → support | `updated` |
| Remove visal | `removed`, and his password sign-in now returns `user_banned` |
| Rachana signs in within the invite window | `active` |

Run `supabase db reset` afterwards to get the seed back. To read invite SMS locally:

```sql
select phone, body, created_at from private.dev_sms_messages order by id desc limit 5;
```

## Owner setup (hosted)

1. **Invite SMS (Twilio).** Use the same Twilio account as Auth's SMS provider (F05). Add these to `supabase/functions/.env`, then run `supabase secrets set --env-file supabase/functions/.env`:
   - `SMS_PROVIDER=twilio`
   - `TWILIO_ACCOUNT_SID`
   - `TWILIO_AUTH_TOKEN`
   - `TWILIO_MESSAGING_SERVICE_SID` (an MG… SID or a sender number)

   Leave `SMS_PROVIDER` unset or `dev_outbox` only on local stacks.
2. **Invite email.** Configure custom SMTP in Auth settings; the built-in sender is rate-limited. You can match the "Invite user" and "Magic link" templates to N-04/N-05.
3. **Redirect URL.** Set `APP_WEB_URL` (already used by F07) to the web app's address, and add `<APP_WEB_URL>/sign-in/set-password` to Auth's redirect allow list.
4. The first super admin is seeded locally. On a new hosted project, create them once by hand: a `staff` profile plus an active `super_admin` row in `staff_members`, with the service role in the SQL editor.

## Decisions and assumptions

- **SMS through an interface** (agreed): Twilio in hosted projects, a dev outbox locally. Auth's own SMS only sends sign-in codes.
- **Edit = change role or remove** (agreed). Both go through `staff-manage`, which refuses self-edits and leaving no active super admin.
- Staff changes are server-only. A super admin can no longer write `staff_members` directly, because the "last super admin" rule needs one path.
- Removed staff keep their row for the audit log, and the auth user is banned. They can be invited again.
- An existing customer, business or rider account can't be turned into staff by invite (`account_exists`); staff use a separate number or email.
- "Last active" is the last sign-in time. Finer activity tracking can come with the audit log.
- Invite SMS and email copy is English (staff-facing).
- Sections from later tasks are placeholders: dashboard content (F37), the A-01a notification panel, global search, and the other A-14 settings pages. Search shows "Coming in a later update." on Enter, and Help does the same.
- The bell opens the F07 inbox at `/admin/inbox`.
- **Design deviations:**
  - The top bar shows the role ("Super admin") under the name; the design shows a job title ("Operations admin"), which has no field yet.
  - Pending invites have no Edit action, as in the design. To withdraw one, let it expire.
  - The bell shows a dot instead of a count, which is the F07 component.
- Fixed on the way: a nested navigator's route blocks the semantics of whatever is painted before it. The page area now has its own semantics container, so screen readers can reach the sidebar and top bar.
