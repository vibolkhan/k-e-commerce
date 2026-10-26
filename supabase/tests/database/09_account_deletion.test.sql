-- F06: account deletion (AUTH-07) anonymises the person and keeps invoices.
begin;
select plan(20);

-- Only the service role (account-delete) reaches the deletion functions.
select ok(
  not has_function_privilege('anon', 'public.account_deletion_check(uuid)', 'execute')
    and not has_function_privilege('authenticated', 'public.account_deletion_check(uuid)', 'execute'),
  'the API roles cannot run the deletion check'
);
select ok(
  has_function_privilege('service_role', 'public.account_deletion_check(uuid)', 'execute'),
  'the Edge Function (service role) can'
);
select ok(
  not has_function_privilege('authenticated', 'private.anonymise_account(uuid, text)', 'execute'),
  'signed-in users cannot anonymise anyone'
);

-- Users can no longer type a phone or mark themselves deleted.
select tests.login_as('lina@kstore.example');
select throws_ok(
  $$ update public.profiles set phone = '+85512999999' where id = auth.uid() $$,
  '42501', null, 'a user cannot change their own phone'
);
select throws_ok(
  $$ update public.profiles set deleted_at = now() where id = auth.uid() $$,
  '42501', null, 'a user cannot set deleted_at'
);
select lives_ok(
  $$ update public.profiles set full_name = 'Lina S.' where id = auth.uid() $$,
  'a user can still edit their name'
);
select tests.as_owner();

-- Dara has an order out for delivery and an open return in the seed.
select is(
  (public.account_deletion_check(tests.uid('dara@kstore.example')) ->> 'active_orders')::int,
  1,
  'an order out for delivery counts as active'
);
select is(
  public.account_deletion_check(tests.uid('dara@kstore.example')) ->> 'role',
  'customer',
  'the check reports the role'
);

-- Once it's delivered, deleting the auth user scrubs the profile.
update public.orders set status = 'delivered'
 where profile_id = tests.uid('dara@kstore.example');
update public.returns set status = 'refunded'
 where profile_id = tests.uid('dara@kstore.example');
select is(
  (public.account_deletion_check(tests.uid('dara@kstore.example')) ->> 'active_orders')::int
    + (public.account_deletion_check(tests.uid('dara@kstore.example')) ->> 'open_returns')::int,
  0,
  'nothing active once orders and returns are finished'
);

create temp table dara as select tests.uid('dara@kstore.example') as id;
update auth.users set raw_app_meta_data = raw_app_meta_data || '{"deletion_reason": "Too many notifications"}'
 where id = (select id from dara);
select lives_ok(
  $$ delete from auth.users where id = (select id from dara) $$,
  'deleting the auth user succeeds even though orders reference the profile'
);

select is(
  (select row(full_name, phone, email, avatar_url)::text from public.profiles where id = (select id from dara)),
  row(null::text, null::text, null::text, null::text)::text,
  'name, phone, email and photo are removed'
);
select isnt(
  (select deleted_at from public.profiles where id = (select id from dara)), null,
  'the profile is marked deleted'
);
select is(
  (select count(*)::int from public.orders where profile_id = (select id from dara)), 2,
  'orders (the invoice record) are kept'
);
select ok(
  exists (
    select 1 from public.payments p join public.orders o on o.id = p.order_id
     where o.profile_id = (select id from dara)
  ),
  'payments are kept'
);
select is(
  (select count(*)::int from public.addresses where profile_id = (select id from dara))
    + (select count(*)::int from public.wishlists where profile_id = (select id from dara))
    + (select count(*)::int from public.carts where profile_id = (select id from dara))
    + (select count(*)::int from public.notifications where profile_id = (select id from dara))
    + (select count(*)::int from public.device_tokens where profile_id = (select id from dara)),
  0,
  'addresses, wishlist, cart, notifications and device tokens are deleted'
);
select is(
  (select count(*)::int from public.conversations where customer_id = (select id from dara)), 0,
  'chat history is deleted'
);
select is(
  (select diff ->> 'reason' from public.audit_logs
    where entity = 'profiles' and entity_id = (select id::text from dara) and action = 'delete'),
  'Too many notifications',
  'the reason is logged without personal data'
);

-- Business buyers keep the company details printed on invoices.
delete from auth.users where id = tests.uid('sokha@kstore.example');
select is(
  (select company_name || ' / ' || vat_tin from public.business_profiles
    where profile_id = 'a0000000-0000-4000-8000-000000000031'),
  'Mekong Desk Co., Ltd. / K001-100234567',
  'company name and TIN stay for invoices'
);
select is(
  (select row(contact_name, contact_phone, licence_path)::text from public.business_profiles
    where profile_id = 'a0000000-0000-4000-8000-000000000031'),
  row(null::text, null::text, null::text)::text,
  'the business contact person is removed'
);

-- The same phone can sign up again as a new person.
insert into auth.users (instance_id, id, aud, role, phone, raw_app_meta_data, raw_user_meta_data)
values ('00000000-0000-0000-0000-000000000000', gen_random_uuid(), 'authenticated',
        'authenticated', '85512345678', '{}', '{}');
select is(
  (select count(*)::int from public.profiles where phone = '+85512345678' and deleted_at is null),
  1,
  'a new sign-up with the old phone gets a fresh profile'
);

select * from finish();
rollback;
