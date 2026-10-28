-- F13 product detail: product_detail as guests, business buyers and staff.
begin;
select plan(14);

create temp table pd_ids as
  select slug, id from public.products;
grant select on pd_ids to anon, authenticated;

select tests.logout();

select is(
  public.product_detail((select id from pd_ids where slug = 'wireless-headphones-pro')) ->> 'slug',
  'wireless-headphones-pro',
  'guests read an active product'
);
select ok(
  public.product_detail((select id from pd_ids where slug = 'rice-cooker-1-8l')) is null,
  'drafts are not readable'
);
select ok(
  public.product_detail(gen_random_uuid()) is null,
  'an unknown product reads as null'
);
select is(
  jsonb_array_length(public.product_detail((select id from pd_ids where slug = 'wireless-headphones-pro')) -> 'variants'),
  3,
  'every active variant is listed'
);
select is(
  (select (v ->> 'price_cents')::int
     from jsonb_array_elements(public.product_detail((select id from pd_ids where slug = 'wireless-headphones-pro')) -> 'variants') v
    where v ->> 'sku' = 'HP-PRO-BLK'),
  4900,
  'guests see the variant price'
);
select is(
  (select jsonb_build_object('available', v -> 'available', 'low', v -> 'low_stock')
     from jsonb_array_elements(public.product_detail((select id from pd_ids where slug = 'wireless-headphones-pro')) -> 'variants') v
    where v ->> 'sku' = 'HP-PRO-BLK'),
  (select jsonb_build_object('available', a.available, 'low', a.low_stock)
     from public.variant_availability a
     join public.product_variants v on v.id = a.variant_id
    where v.sku = 'HP-PRO-BLK'),
  'stock per variant follows availability, including the low-stock flag'
);
select is(
  (select (v ->> 'available')::int
     from jsonb_array_elements(public.product_detail((select id from pd_ids where slug = 'wireless-headphones-pro')) -> 'variants') v
    where v ->> 'sku' = 'HP-PRO-SKY'),
  0,
  'an out-of-stock variant reads as 0 available'
);
select is(
  (public.product_detail((select id from pd_ids where slug = 'wireless-headphones-pro')) ->> 'max_per_order')::int,
  5,
  'the per-order limit is included'
);
select is(
  public.product_detail((select id from pd_ids where slug = 'wireless-headphones-pro')) -> 'specs',
  (select specs from public.products where slug = 'wireless-headphones-pro'),
  'specs come back as stored'
);
select ok(
  not exists (
    select 1 from jsonb_array_elements(
      public.product_detail((select id from pd_ids where slug = 'wireless-headphones-pro')) -> 'related') r
     where r ->> 'slug' in ('wireless-headphones-pro', 'rice-cooker-1-8l')),
  'related products exclude the product itself and drafts'
);
select ok(
  jsonb_array_length(public.product_detail((select id from pd_ids where slug = 'wireless-headphones-pro')) -> 'related')
    between 1 and 8,
  'the related row holds up to 8 products'
);

-- Inactive variants are not listed.
select tests.as_owner();
update public.product_variants set active = false where sku = 'HP-PRO-WHT';
select tests.logout();
select ok(
  not exists (
    select 1 from jsonb_array_elements(
      public.product_detail((select id from pd_ids where slug = 'wireless-headphones-pro')) -> 'variants') v
     where v ->> 'sku' = 'HP-PRO-WHT'),
  'inactive variants are not listed'
);

-- Business buyers: no retail prices anywhere on the page.
select tests.login_as('sokha@kstore.example');
select ok(
  (select bool_and(v ->> 'price_cents' is null)
     from jsonb_array_elements(public.product_detail((select id from pd_ids where slug = 'wireless-headphones-pro')) -> 'variants') v)
  and (select coalesce(bool_and(r ->> 'min_price_cents' is null), true)
     from jsonb_array_elements(public.product_detail((select id from pd_ids where slug = 'wireless-headphones-pro')) -> 'related') r),
  'business buyers get no prices'
);

-- Staff reading the shop still see only active products.
select tests.login_as('visal@kstore.example');
select ok(
  public.product_detail((select id from pd_ids where slug = 'rice-cooker-1-8l')) is null,
  'drafts never reach the product page, even for staff'
);

select * from finish();
rollback;
