-- Riders see only the deliveries assigned to them.
begin;
select plan(16);

select tests.login_as('vuthy@kstore.example');

select is((select count(*)::int from public.deliveries), 2, 'Vuthy sees his 2 deliveries');
select is((select count(*)::int from public.orders), 2, 'Vuthy sees the orders he delivers');
select is((select count(*)::int from public.order_items), 4, 'Vuthy sees what to deliver');
select is(
  (select count(*)::int from public.profiles where id = tests.uid('dara@kstore.example')),
  1,
  'Vuthy sees his customer''s contact'
);
select is(
  (select count(*)::int from public.profiles where id = tests.uid('bopha@kstore.example')),
  0,
  'Vuthy cannot see other customers'
);
select lives_ok(
  $$ insert into public.rider_locations (delivery_id, rider_id, lat, lng)
     values ('e0000000-0000-4000-8000-000000010250', auth.uid(), 11.58, 104.89) $$,
  'Vuthy shares his location on an active delivery'
);
select throws_ok(
  $$ insert into public.rider_locations (delivery_id, rider_id, lat, lng)
     values ('e0000000-0000-4000-8000-000000010248', auth.uid(), 11.58, 104.89) $$,
  '42501', null, 'no location sharing on a finished delivery'
);
select throws_ok(
  $$ update public.deliveries set status = 'delivered' $$,
  '42501', null, 'delivery status goes through the server'
);
select is(
  tests.rows($$ update public.riders set on_duty = false where profile_id = auth.uid() $$),
  1,
  'Vuthy can go off duty'
);
select throws_ok(
  $$ update public.riders set plate = 'X' where profile_id = auth.uid() $$,
  '42501', null, 'riders cannot change their plate'
);

select tests.login_as('sokun@kstore.example');

select is((select count(*)::int from public.deliveries), 1, 'Sokun sees only his delivery');
select is(
  (select count(*)::int from public.orders where number = 'K-10250'),
  0,
  'Sokun cannot see Vuthy''s order'
);
select is((select count(*)::int from public.rider_locations), 0, 'Sokun cannot see Vuthy''s locations');
select throws_ok(
  $$ insert into public.rider_locations (delivery_id, rider_id, lat, lng)
     values ('e0000000-0000-4000-8000-000000010250', auth.uid(), 11.58, 104.89) $$,
  '42501', null, 'Sokun cannot post a location on Vuthy''s delivery'
);
select throws_ok(
  $$ insert into public.rider_locations (delivery_id, rider_id, lat, lng)
     values ('e0000000-0000-4000-8000-000000010251', auth.uid(), 11.55, 104.92) $$,
  '42501', null, 'no location sharing before pickup'
);

-- Bopha's order is assigned but not picked up: no live map yet.
select tests.login_as('bopha@kstore.example');
select is((select count(*)::int from public.rider_locations), 0, 'no tracking before pickup');

select * from finish();
rollback;
