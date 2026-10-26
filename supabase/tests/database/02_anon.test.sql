-- Signed-out visitors: browse the live catalog, nothing personal.
begin;
select plan(13);

select tests.logout();

select ok((select count(*) from public.products) > 0, 'guests see products');
select is(
  (select count(*)::int from public.products where status <> 'active'),
  0,
  'guests never see draft or archived products'
);
select ok((select count(*) from public.prices) > 0, 'guests see retail prices');
select is(
  (select value from public.app_settings where key = 'khr_per_usd'),
  '4100'::jsonb,
  'guests read the KHR rate (F03 contract)'
);
select is((select count(*)::int from public.reviews), 1, 'guests see published reviews only');
select is(
  (select count(*)::int from public.banners where title ->> 'en' = 'Rainy season essentials'),
  0,
  'ended banners are hidden'
);
select is(
  (select count(*)::int from public.delivery_zones where name = 'Chbar Ampov'),
  0,
  'paused zones are hidden'
);

select is((select count(*)::int from public.profiles), 0, 'guests see no profiles');
select is((select count(*)::int from public.orders), 0, 'guests see no orders');
select is((select count(*)::int from public.addresses), 0, 'guests see no addresses');
select is((select count(*)::int from public.carts), 0, 'guests see no carts');
select is((select count(*)::int from public.audit_logs), 0, 'guests see no audit log');

select throws_ok(
  $$ insert into public.categories (slug, name) values ('x', '{"en": "X"}') $$,
  '42501',
  null,
  'guests cannot write the catalog'
);

select * from finish();
rollback;
