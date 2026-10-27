-- F05 · Local SMS outbox for phone sign-in.
--
-- There is no SMS provider locally, so any number outside [auth.sms.test_otp]
-- failed with `send_failed`. Local config.toml points Auth's Send SMS hook at
-- private.dev_send_sms, which keeps the code here instead of sending it:
--
--   select phone, otp, created_at from private.dev_sms_outbox order by id desc limit 5;
--
-- DEV ONLY. Codes are stored in plain text, so never enable this hook on the
-- hosted project; it uses the real SMS provider. Without the hook the
-- function is never called.

create table private.dev_sms_outbox (
  id bigserial primary key,
  phone text not null,
  otp text not null,
  created_at timestamptz not null default now()
);
alter table private.dev_sms_outbox enable row level security;

create function private.dev_send_sms(event jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_phone text := event -> 'user' ->> 'phone';
  v_otp text := event -> 'sms' ->> 'otp';
begin
  insert into private.dev_sms_outbox (phone, otp) values (v_phone, v_otp);
  raise log 'dev_send_sms: code % for +%', v_otp, v_phone;
  return '{}'::jsonb;
end;
$$;

revoke execute on function private.dev_send_sms(jsonb) from public, anon, authenticated;
grant usage on schema private to supabase_auth_admin;
grant execute on function private.dev_send_sms(jsonb) to supabase_auth_admin;
