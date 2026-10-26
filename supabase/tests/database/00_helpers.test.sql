-- Test helpers, installed once per database (files run in name order).
-- They live in the `tests` schema, which the app never exposes.

create extension if not exists pgtap with schema extensions;
create schema if not exists tests;
grant usage on schema tests to anon, authenticated;

-- Id of a seeded user by email (readable from any role).
create or replace function tests.uid(p_email text)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select id from auth.users where email = p_email;
$$;

-- Act as a signed-in user for the rest of the transaction, the way
-- PostgREST does: role `authenticated` plus JWT claims.
create or replace function tests.login_as(p_email text)
returns void
language plpgsql
as $$
declare
  v_uid uuid := tests.uid(p_email);
begin
  if v_uid is null then
    raise exception 'No seeded user %', p_email;
  end if;
  reset role;
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', v_uid, 'role', 'authenticated', 'email', p_email)::text,
    true
  );
  set local role authenticated;
end;
$$;

-- Act as a signed-out visitor.
create or replace function tests.logout()
returns void
language plpgsql
as $$
begin
  reset role;
  perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  set local role anon;
end;
$$;

-- Back to the test runner's own role (bypasses RLS) for setup and checks.
create or replace function tests.as_owner()
returns void
language plpgsql
as $$
begin
  reset role;
  perform set_config('request.jwt.claims', '', true);
end;
$$;

-- Rows affected by a statement, as the current role. RLS-filtered updates
-- and deletes affect 0 rows instead of failing.
create or replace function tests.rows(p_sql text)
returns integer
language plpgsql
as $$
declare
  n integer;
begin
  execute p_sql;
  get diagnostics n = row_count;
  return n;
end;
$$;

grant execute on all functions in schema tests to anon, authenticated;

begin;
select plan(1);
select ok(tests.uid('dara@kstore.example') is not null, 'helpers installed and seed present');
select * from finish();
rollback;
