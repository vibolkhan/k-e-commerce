-- F05: sign-in throttling and profile bootstrap.
begin;
select plan(18);

-- Only the service role reaches the attempt counters.
select has_table('private', 'auth_attempts', 'attempts live in the private schema');
select ok(
  not has_schema_privilege('anon', 'private', 'usage')
    and not has_schema_privilege('authenticated', 'private', 'usage'),
  'the API roles cannot see the private schema'
);
select ok(
  not has_function_privilege('anon', 'public.auth_attempt_fail(text, text)', 'execute')
    and not has_function_privilege('authenticated', 'public.auth_attempt_fail(text, text)', 'execute')
    and not has_function_privilege('authenticated', 'public.auth_attempt_reset(text, text)', 'execute')
    and not has_function_privilege('authenticated', 'public.auth_attempt_status(text, text)', 'execute')
    and not has_function_privilege('authenticated', 'public.auth_attempt_mark_sent(text, text)', 'execute'),
  'signed-in users cannot reset or read their own counters'
);
select ok(
  has_function_privilege('service_role', 'public.auth_attempt_fail(text, text)', 'execute'),
  'the Edge Functions (service role) can'
);

select tests.login_as('dara@kstore.example');
select throws_ok(
  $$ select public.auth_attempt_reset('otp', '+85512345678') $$,
  '42501', null, 'calling reset as a user is refused'
);
select tests.as_owner();

-- Five wrong codes lock the number for 15 minutes.
select is((public.auth_attempt_status('otp', '+85512000099') ->> 'tries_left')::int, 5, 'fresh number has 5 tries');
select is((public.auth_attempt_fail('otp', '+85512000099') ->> 'tries_left')::int, 4, 'first wrong code leaves 4');
select public.auth_attempt_fail('otp', '+85512000099') from generate_series(1, 3);
select is(public.auth_attempt_status('otp', '+85512000099') ->> 'locked_until', null, 'not locked after 4 wrong codes');
select isnt(public.auth_attempt_fail('otp', '+85512000099') ->> 'locked_until', null, 'the 5th wrong code locks');
select ok(
  (public.auth_attempt_status('otp', '+85512000099') ->> 'locked_until')::timestamptz
    between now() + interval '14 minutes' and now() + interval '16 minutes',
  'the lock lasts 15 minutes'
);
select is(
  (public.auth_attempt_status('otp', ' +85512000099 ') ->> 'tries_left')::int, 0,
  'identifiers are trimmed before matching'
);
select is(
  (public.auth_attempt_status('password', '+85512000099') ->> 'tries_left')::int, 5,
  'OTP and password counters are separate'
);
select is(
  (select count(*)::int from private.auth_attempts where identifier_hash like '%85512000099%'),
  0,
  'raw phone numbers are never stored'
);

-- An expired lock clears itself.
update private.auth_attempts
   set locked_until = now() - interval '1 second'
 where kind = 'otp' and identifier_hash = private.auth_attempt_key('+85512000099');
select is((public.auth_attempt_status('otp', '+85512000099') ->> 'tries_left')::int, 5, 'tries come back after the lock');

-- Success clears failures; emails match case-insensitively.
select public.auth_attempt_fail('password', 'Dara@KStore.example');
select public.auth_attempt_reset('password', 'dara@kstore.example');
select is((public.auth_attempt_status('password', 'dara@kstore.example') ->> 'tries_left')::int, 5, 'a good password resets the count');

-- Resend clock.
select public.auth_attempt_mark_sent('otp', '+85512000098');
select ok(
  (public.auth_attempt_status('otp', '+85512000098') ->> 'resend_in')::int between 59 and 60,
  'a new code can be sent after 60 s'
);

-- New users get a customer profile, whatever the sign-in method.
insert into auth.users (id, instance_id, aud, role, phone, raw_user_meta_data)
values ('f5000000-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000',
        'authenticated', 'authenticated', '85512000777', '{"locale": "km"}');
select results_eq(
  $$ select role::text, phone, full_name, locale from public.profiles
      where id = 'f5000000-0000-4000-8000-000000000001' $$,
  $$ values ('customer', '+85512000777', null::text, 'km') $$,
  'phone sign-up: customer, +855 phone, no name yet (S-06 asks for it)'
);
insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data)
values ('f5000000-0000-4000-8000-000000000002', '00000000-0000-0000-0000-000000000000',
        'authenticated', 'authenticated', 'g@example.com', '{"name": "Srey Neang"}');
select is(
  (select full_name from public.profiles where id = 'f5000000-0000-4000-8000-000000000002'),
  'Srey Neang',
  'Google sign-up keeps the account name'
);

select * from finish();
rollback;
