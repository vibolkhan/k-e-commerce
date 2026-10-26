-- Retail customers see and change only their own rows, and never money,
-- stock, status or their own role.
begin;
select plan(37);

select tests.login_as('dara@kstore.example');

-- Own rows only.
select is((select count(*)::int from public.orders), 2, 'Dara sees her 2 orders');
select is(
  (select count(*)::int from public.orders where number = 'K-10251'),
  0,
  'Dara cannot see Bopha''s order'
);
select is((select count(*)::int from public.order_items), 4, 'Dara sees the items of her orders');
select is((select count(*)::int from public.payments), 2, 'Dara sees her payments');
select is((select count(*)::int from public.deliveries), 2, 'Dara sees her deliveries');
select is((select count(*)::int from public.addresses), 2, 'Dara sees only her addresses');
select is((select count(*)::int from public.carts), 1, 'Dara sees only her cart');
select is((select count(*)::int from public.cart_items), 1, 'Dara sees only her cart items');
select is((select count(*)::int from public.returns), 1, 'Dara sees her return');
select is((select count(*)::int from public.staff_members), 0, 'customers cannot list staff');
select is((select count(*)::int from public.audit_logs), 0, 'customers cannot read the audit log');
select is(
  (select count(*)::int from public.profiles where id = tests.uid('bopha@kstore.example')),
  0,
  'Dara cannot see other customers'
);

-- Money, stock and status are server-only.
select throws_ok(
  $$ update public.orders set status = 'delivered' $$,
  '42501', null, 'customers cannot change order status'
);
select throws_ok(
  $$ insert into public.payments (order_id, provider, method, status, amount_cents)
     values ('d0000000-0000-4000-8000-000000010250', 'cod', 'cod', 'paid', 2550) $$,
  '42501', null, 'customers cannot record payments'
);
select throws_ok(
  $$ update public.stock set qty = qty + 100 $$,
  '42501', null, 'customers cannot change stock'
);
select throws_ok(
  $$ update public.deliveries set status = 'delivered' $$,
  '42501', null, 'customers cannot change deliveries'
);

-- Profile: own safe columns only.
select is(
  tests.rows($$ update public.profiles set full_name = 'Dara S.' where id = auth.uid() $$),
  1,
  'Dara can edit her name'
);
select throws_ok(
  $$ update public.profiles set role = 'staff' where id = auth.uid() $$,
  '42501', null, 'Dara cannot change her own role'
);
select throws_ok(
  $$ update public.profiles set is_blocked = true where id = auth.uid() $$,
  '42501', null, 'Dara cannot change her blocked flag'
);
select is(
  tests.rows($$ update public.profiles set full_name = 'x' where id = tests.uid('bopha@kstore.example') $$),
  0,
  'Dara cannot edit another profile'
);

-- Addresses: zone comes from the pin.
select lives_ok(
  $$ insert into public.addresses (profile_id, label, line, lat, lng)
     values (auth.uid(), 'Gym', 'St. 51, BKK1', 11.547, 104.920) $$,
  'Dara can add an address'
);
select is(
  (select z.name from public.addresses a join public.delivery_zones z on z.id = a.zone_id
    where a.label = 'Gym'),
  'BKK1',
  'the address zone is resolved from the pin'
);
select throws_ok(
  $$ insert into public.addresses (profile_id, label, line)
     values (tests.uid('bopha@kstore.example'), 'Hack', 'x') $$,
  '42501', null, 'Dara cannot add an address for someone else'
);

-- Cart and wishlist.
select lives_ok(
  $$ insert into public.cart_items (cart_id, variant_id, qty)
     select 'c0000000-0000-4000-8000-000000000021', id, 1
       from public.product_variants where sku = 'MUG-4-WHT' $$,
  'Dara can add to her cart'
);
select throws_ok(
  $$ insert into public.cart_items (cart_id, variant_id, qty)
     select 'c0000000-0000-4000-8000-000000000022', id, 1
       from public.product_variants where sku = 'MUG-4-WHT' $$,
  '42501', null, 'Dara cannot add to Bopha''s cart'
);
select lives_ok(
  $$ insert into public.wishlists (profile_id, product_id)
     select auth.uid(), id from public.products where slug = 'led-desk-lamp' $$,
  'Dara can save to her wishlist'
);

-- Reviews: only after a delivered order containing the product.
select lives_ok(
  $$ insert into public.reviews (product_id, profile_id, order_id, rating, body)
     select id, auth.uid(), 'd0000000-0000-4000-8000-000000010248', 4, 'Nice mugs'
       from public.products where slug = 'ceramic-coffee-mug-set' $$,
  'Dara can review a product she received'
);
select throws_ok(
  $$ insert into public.reviews (product_id, profile_id, order_id, rating)
     select id, auth.uid(), 'd0000000-0000-4000-8000-000000010248', 5
       from public.products where slug = 'smart-watch-active-2' $$,
  '42501', null, 'Dara cannot review a product she did not receive'
);
select throws_ok(
  $$ insert into public.reviews (product_id, profile_id, order_id, rating)
     select id, auth.uid(), 'd0000000-0000-4000-8000-000000010250', 5
       from public.products where slug = 'led-desk-lamp' $$,
  '42501', null, 'Dara cannot review an order that is not delivered yet'
);
select throws_ok(
  $$ insert into public.reviews (product_id, profile_id, order_id, rating)
     select id, auth.uid(), 'd0000000-0000-4000-8000-000000010248', 5
       from public.products where slug = 'wireless-headphones-pro' $$,
  '23505', null, 'one review per product per order'
);

-- Live tracking and the rider's contact for her active delivery.
select is(
  (select count(*)::int from public.rider_locations),
  1,
  'Dara sees her rider''s location while out for delivery'
);
select is(
  (select count(*)::int from public.profiles where id = tests.uid('vuthy@kstore.example')),
  1,
  'Dara can see her rider''s profile'
);

-- Notifications: read flag only.
select is(
  tests.rows($$ update public.notifications set read_at = now() $$),
  2,
  'Dara can mark her notifications read'
);
select throws_ok(
  $$ update public.notifications set title = '{"en": "x"}' $$,
  '42501', null, 'Dara cannot rewrite a notification'
);

-- Chat: own support thread.
select is((select count(*)::int from public.conversations), 1, 'Dara sees her support chat only');
select lives_ok(
  $$ insert into public.messages (conversation_id, sender_id, body)
     values ('91000000-0000-4000-8000-000000000001', auth.uid(), 'Thanks!') $$,
  'Dara can reply in her chat'
);

-- Blocked customers lose role-based rights.
select tests.login_as('vannak@kstore.example');
select throws_ok(
  $$ insert into public.carts (profile_id) values (auth.uid()) $$,
  '42501', null, 'a blocked customer cannot create a cart'
);

select * from finish();
rollback;
