-- F05 · Sign-in throttling (AUTH-01) and profile bootstrap for social sign-in.
--
-- Supabase Auth expires codes but does not lock a number after wrong codes.
-- The auth-* Edge Functions count failures here: 5 wrong codes (or passwords)
-- lock the phone (or email) for 15 minutes, and a new code can be sent only
-- every 60 s. Limits come from app_settings 'otp'.
--
-- The table lives in a private schema that the API never exposes; the
-- functions below are its only door and only the service role may call them.

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create table private.auth_attempts (
  kind text not null check (kind in ('otp', 'password')),
  identifier_hash text not null,  -- sha256 of the normalised phone/email, never the raw value
  failed_count integer not null default 0 check (failed_count >= 0),
  locked_until timestamptz,
  last_sent_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key (kind, identifier_hash)
);

create function private.auth_attempt_key(p_identifier text)
returns text
language sql
immutable
set search_path = ''
as $$
  select encode(pg_catalog.sha256(convert_to(lower(trim(p_identifier)), 'UTF8')), 'hex');
$$;

create function private.auth_attempt_limits()
returns table (max_attempts integer, lockout_minutes integer, resend_seconds integer)
language sql
stable
set search_path = ''
as $$
  select coalesce((s.value ->> 'max_attempts')::int, 5),
         coalesce((s.value ->> 'lockout_minutes')::int, 15),
         coalesce((s.value ->> 'resend_seconds')::int, 60)
    from (select 1) d
    left join public.app_settings s on s.key = 'otp';
$$;

-- Current state for one phone/email. An expired lock is cleared on read.
-- Returns {locked_until, tries_left, resend_in} (resend_in in whole seconds).
create function public.auth_attempt_status(p_kind text, p_identifier text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_key text := private.auth_attempt_key(p_identifier);
  v_limits record;
  v_row private.auth_attempts;
begin
  select * into v_limits from private.auth_attempt_limits();

  update private.auth_attempts
     set failed_count = 0, locked_until = null, updated_at = now()
   where kind = p_kind and identifier_hash = v_key
     and locked_until is not null and locked_until <= now();

  select * into v_row
    from private.auth_attempts
   where kind = p_kind and identifier_hash = v_key;

  return jsonb_build_object(
    'locked_until', v_row.locked_until,
    'tries_left', greatest(v_limits.max_attempts - coalesce(v_row.failed_count, 0), 0),
    'resend_in', greatest(
      0,
      ceil(extract(epoch from (v_row.last_sent_at + make_interval(secs => v_limits.resend_seconds) - now())))
    )::int
  );
end;
$$;

-- Records one wrong code/password. The last allowed failure starts the lock.
-- Returns the same shape as auth_attempt_status.
create function public.auth_attempt_fail(p_kind text, p_identifier text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_key text := private.auth_attempt_key(p_identifier);
  v_limits record;
begin
  select * into v_limits from private.auth_attempt_limits();

  insert into private.auth_attempts as a (kind, identifier_hash, failed_count)
  values (p_kind, v_key, 1)
  on conflict (kind, identifier_hash) do update
     set failed_count = a.failed_count + 1,
         updated_at = now();

  update private.auth_attempts
     set locked_until = now() + make_interval(mins => v_limits.lockout_minutes)
   where kind = p_kind and identifier_hash = v_key
     and failed_count >= v_limits.max_attempts
     and locked_until is null;

  return public.auth_attempt_status(p_kind, p_identifier);
end;
$$;

-- A successful sign-in clears the failures (the resend clock is kept).
create function public.auth_attempt_reset(p_kind text, p_identifier text)
returns void
language sql
security definer
set search_path = ''
as $$
  update private.auth_attempts
     set failed_count = 0, locked_until = null, updated_at = now()
   where kind = p_kind and identifier_hash = private.auth_attempt_key(p_identifier);
$$;

-- Marks that a code was just sent (starts the resend clock).
create function public.auth_attempt_mark_sent(p_kind text, p_identifier text)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into private.auth_attempts as a (kind, identifier_hash, last_sent_at)
  values (p_kind, private.auth_attempt_key(p_identifier), now())
  on conflict (kind, identifier_hash) do update
     set last_sent_at = now(), updated_at = now();
$$;

revoke execute on function
  public.auth_attempt_status(text, text),
  public.auth_attempt_fail(text, text),
  public.auth_attempt_reset(text, text),
  public.auth_attempt_mark_sent(text, text)
from public, anon, authenticated;
grant execute on function
  public.auth_attempt_status(text, text),
  public.auth_attempt_fail(text, text),
  public.auth_attempt_reset(text, text),
  public.auth_attempt_mark_sent(text, text)
to service_role;
grant usage on schema private to service_role;

-- ---------------------------------------------------------------------------
-- Profiles for every sign-in method. Google sends `name`/`full_name`, Apple
-- only `full_name` (first sign-in only); phone sign-ups have neither and
-- complete their name on S-06. Phones are stored as +855… for display.
-- ---------------------------------------------------------------------------

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, email, phone, full_name, avatar_url, locale)
  values (
    new.id,
    new.email,
    case when coalesce(new.phone, '') = '' then null
         when new.phone like '+%' then new.phone
         else '+' || new.phone
    end,
    nullif(trim(coalesce(
      new.raw_user_meta_data ->> 'full_name',
      new.raw_user_meta_data ->> 'name'
    )), ''),
    new.raw_user_meta_data ->> 'avatar_url',
    case
      when new.raw_user_meta_data ->> 'locale' in ('en', 'km')
        then new.raw_user_meta_data ->> 'locale'
      else 'en'
    end
  );
  return new;
end;
$$;
revoke execute on function public.handle_new_user() from public, anon, authenticated;
