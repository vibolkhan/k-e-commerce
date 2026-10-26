-- F07 · Push notifications and inbox (NOT-01, NOT-02; S-07, S-08d).
--
-- The tables came with F04 (notifications, device_tokens, profiles
-- .notification_prefs). This adds what the pipeline needs:
--   * a category per notification, so the inbox tabs filter in the database;
--   * a door for registering FCM tokens, since a token follows the device
--     and must move to whoever signs in on it next;
--   * "Mark all read" in one statement;
--   * one shape for notification_prefs (S-08d).
--
-- Rows are still written only by the notify Edge Function (service role).

-- ---------------------------------------------------------------------------
-- Inbox
-- ---------------------------------------------------------------------------

-- S-07 tabs: Orders, Quotes, Chat. `account` (business verification, tests)
-- shows under All only.
alter table public.notifications
  add column category text not null default 'orders'
    check (category in ('orders', 'quotes', 'chat', 'account'));
update public.notifications
   set category = case
     when type in ('rfq', 'quote_ready', 'quote_revised', 'quote_expiring') then 'quotes'
     when type in ('chat', 'chat_message') then 'chat'
     else 'orders'
   end;

create index notifications_unread_idx
  on public.notifications (profile_id, category)
  where read_at is null;

-- Users may only set read_at; the id and category are the server's too.
drop trigger guard_columns_service on public.notifications;
create trigger guard_columns_service
  before update on public.notifications
  for each row execute function public.guard_columns(
    '', 'id', 'profile_id', 'type', 'category', 'title', 'body', 'payload', 'created_at'
  );

-- S-07 "Mark all read" (all tabs, or one with p_category). Runs as the
-- caller, so RLS keeps it to their own rows. Returns how many changed.
create function public.mark_all_notifications_read(p_category text default null)
returns integer
language sql
security invoker
set search_path = ''
as $$
  with changed as (
    update public.notifications
       set read_at = now()
     where profile_id = (select auth.uid())
       and read_at is null
       and (p_category is null or category = p_category)
    returning 1
  )
  select count(*)::int from changed;
$$;
revoke execute on function public.mark_all_notifications_read(text) from public, anon;
grant execute on function public.mark_all_notifications_read(text) to authenticated;

-- ---------------------------------------------------------------------------
-- Device tokens
-- ---------------------------------------------------------------------------

-- FCM issues one token per app install. When someone else signs in on the
-- same device the token must move to them, but RLS hides the previous
-- owner's row, so the client registers through this function instead.
create function public.register_device_token(p_token text, p_platform text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
begin
  if v_uid is null then
    raise exception 'not signed in' using errcode = '42501';
  end if;
  if p_token is null or length(trim(p_token)) = 0 or length(p_token) > 4096 then
    raise exception 'invalid token' using errcode = '22023';
  end if;
  if p_platform not in ('ios', 'android', 'web') then
    raise exception 'invalid platform' using errcode = '22023';
  end if;

  insert into public.device_tokens (profile_id, token, platform, last_seen_at)
  values (v_uid, p_token, p_platform, now())
  on conflict (token) do update
     set profile_id = excluded.profile_id,
         platform = excluded.platform,
         last_seen_at = now();
end;
$$;
revoke execute on function public.register_device_token(text, text) from public, anon;
grant execute on function public.register_device_token(text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Preferences (S-08d)
-- ---------------------------------------------------------------------------

-- notification_prefs: {"orders": {"push", "email"}, "quotes": {"push",
-- "email"}, "chat": {"push"}, "reviews": {"push"}}; a missing key means the
-- default (everything on except review reminders). Payment, refund and
-- account-security messages ignore these switches. F05 stored the S-06
-- "email me receipts" tick as `email_receipts`; it is the orders email switch.
update public.profiles
   set notification_prefs = (notification_prefs - 'email_receipts')
       || jsonb_build_object(
            'orders',
            coalesce(notification_prefs -> 'orders', '{}'::jsonb)
              || jsonb_build_object('email', (notification_prefs ->> 'email_receipts')::boolean)
          )
 where notification_prefs ? 'email_receipts';

alter table public.profiles
  add constraint profiles_notification_prefs_object
    check (jsonb_typeof(notification_prefs) = 'object');
