-- F08: staff lifecycle, A-14d directory, sidebar badges and the matrix reads.
begin;
select plan(34);

-- Staff are managed only through the staff-manage Edge Function.
select tests.login_as('chenda@kstore.example');
select throws_ok(
  $$ update public.staff_members set staff_role = 'catalog'
      where profile_id = tests.uid('dalin@kstore.example') $$,
  '42501', null, 'even a super admin cannot change staff directly'
);
select throws_ok(
  $$ insert into public.staff_members (profile_id, staff_role, status)
     values (tests.uid('bopha@kstore.example'), 'sales', 'active') $$,
  '42501', null, 'even a super admin cannot add staff directly'
);
select throws_ok(
  $$ delete from public.staff_members where profile_id = tests.uid('rachana@kstore.example') $$,
  '42501', null, 'even a super admin cannot remove staff directly'
);

-- A-14d directory: super admin only.
select is((select count(*)::int from public.staff_directory()), 5, 'super admin lists all five staff');
select is(
  (select full_name from public.staff_directory() where is_me),
  'Chenda Lim',
  'the directory marks the caller as "you"'
);
select is(
  (select status from public.staff_directory() where email = 'rachana@kstore.example'),
  'invited',
  'pending invites are listed with their status'
);
select is(
  (select invite_expires_at from public.staff_directory() where email = 'rachana@kstore.example'),
  '2026-10-28 10:00+07'::timestamptz,
  'the invite expiry is listed for Resend'
);
select tests.login_as('dalin@kstore.example');
select throws_ok($$ select * from public.staff_directory() $$, '42501', null, 'sales cannot list staff');
select tests.login_as('dara@kstore.example');
select throws_ok($$ select * from public.staff_directory() $$, '42501', null, 'customers cannot list staff');

-- Sidebar badges are counted under the caller's RLS.
select tests.as_owner();
insert into public.conversations (kind, customer_id, status, subject)
values ('support', tests.uid('bopha@kstore.example'), 'open', 'Badge test');
update public.rfqs set status = 'submitted'
 where id = (select id from public.rfqs order by number limit 1);
select tests.login_as('chenda@kstore.example');
select is((public.admin_badge_counts() ->> 'rfqs')::int, 1, 'super admin counts open RFQs');
select is((public.admin_badge_counts() ->> 'chat')::int, 1, 'super admin counts waiting chats');
select is((public.admin_badge_counts() ->> 'customers')::int, 1, 'super admin counts pending verifications');
select tests.login_as('dalin@kstore.example');
select is((public.admin_badge_counts() ->> 'rfqs')::int, 1, 'sales count RFQs');
select is((public.admin_badge_counts() ->> 'returns')::int, 0, 'sales cannot count returns');
select is((public.admin_badge_counts() ->> 'chat')::int, 0, 'sales cannot count support chats');
select tests.login_as('sophea@kstore.example');
select is((public.admin_badge_counts() ->> 'returns')::int, 1, 'support count requested returns');
select is((public.admin_badge_counts() ->> 'rfqs')::int, 0, 'support cannot count RFQs');
select tests.login_as('visal@kstore.example');
select is((public.admin_badge_counts() ->> 'customers')::int, 0, 'catalog cannot count verifications');
select tests.login_as('dara@kstore.example');
select is(public.admin_badge_counts(), '{}'::jsonb, 'customers get no badges');

-- Matrix reads tightened from F04.
select tests.login_as('visal@kstore.example');
select is(
  (select count(*)::int from public.profiles where id = tests.uid('dara@kstore.example')),
  0,
  'catalog staff cannot see customers'
);
select is(
  (select count(*)::int from public.profiles where id = tests.uid('dalin@kstore.example')),
  1,
  'catalog staff can see colleagues'
);
select is((select count(*)::int from public.addresses), 0, 'catalog staff cannot see addresses');
select is((select count(*)::int from public.riders), 0, 'catalog staff cannot see riders');
select tests.login_as('sophea@kstore.example');
select ok((select count(*) from public.profiles where id = tests.uid('dara@kstore.example')) = 1,
  'support can view customers');
select ok((select count(*) from public.riders) > 0, 'support see riders on orders');
select is((select count(*)::int from public.rider_zones), 0, 'support cannot see rider zones');
select tests.login_as('chenda@kstore.example');
select ok((select count(*) from public.rider_zones) > 0, 'super admin manages rider zones');

-- Invite lifecycle: active on first sign-in unless expired.
select tests.as_owner();
update public.staff_members set invite_expires_at = now() - interval '1 hour'
 where profile_id = tests.uid('rachana@kstore.example');
update auth.users set last_sign_in_at = now() where id = tests.uid('rachana@kstore.example');
select is(
  (select status from public.staff_members where profile_id = tests.uid('rachana@kstore.example')),
  'invited',
  'an expired invite stays inactive on sign-in'
);
update public.staff_members set invite_expires_at = now() + interval '7 days'
 where profile_id = tests.uid('rachana@kstore.example');
update auth.users set last_sign_in_at = now() + interval '1 minute'
 where id = tests.uid('rachana@kstore.example');
select is(
  (select status from public.staff_members where profile_id = tests.uid('rachana@kstore.example')),
  'active',
  'a valid invite turns active on the first sign-in'
);
select tests.login_as('rachana@kstore.example');
select ok((select count(*) from public.returns) > 0, 'the new support member now has support rights');

-- Removed staff keep their row but lose every right.
select tests.as_owner();
update public.staff_members set status = 'removed'
 where profile_id = tests.uid('sophea@kstore.example');
select tests.login_as('sophea@kstore.example');
select is((select count(*)::int from public.returns), 0, 'removed staff lose their rights');
select tests.login_as('chenda@kstore.example');
select is(
  (select count(*)::int from public.staff_directory() where email = 'sophea@kstore.example'),
  0,
  'removed staff leave the directory'
);

-- There is always an active super admin.
select tests.as_owner();
select throws_ok(
  $$ update public.staff_members set staff_role = 'sales'
      where profile_id = tests.uid('chenda@kstore.example') $$,
  'P0001', 'at least one active super admin is required', 'the last super admin cannot be demoted'
);
select throws_ok(
  $$ update public.staff_members set status = 'removed'
      where profile_id = tests.uid('chenda@kstore.example') $$,
  'P0001', 'at least one active super admin is required', 'the last super admin cannot be removed'
);

select * from finish();
rollback;
