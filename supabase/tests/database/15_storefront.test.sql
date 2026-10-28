-- F11 storefront reads: catalog_browse and storefront_clock, as guests,
-- business buyers and staff.
begin;
select plan(20);

select tests.logout();

select is(
  (public.catalog_browse() ->> 'total')::int,
  (select count(*)::int from public.products where status = 'active'),
  'guests browse every active product'
);
select ok(
  (select bool_and(r ->> 'min_price_cents' is not null)
     from jsonb_array_elements(public.catalog_browse(p_limit => 60) -> 'rows') r),
  'guests see a price on every card'
);
select is(
  (public.catalog_browse(p_category => (select id from public.categories where slug = 'electronics')) ->> 'total')::int,
  (select count(*)::int from public.products p join public.categories c on c.id = p.category_id
    where p.status = 'active' and (c.slug = 'electronics' or c.parent_id = (select id from public.categories where slug = 'electronics'))),
  'a top category includes its subcategories'
);
select ok(
  not exists (
    select 1 from jsonb_array_elements(
      public.catalog_browse(p_category => (select id from public.categories where slug = 'audio'), p_limit => 60) -> 'rows') r
     where r ->> 'id' not in (select p.id::text from public.products p join public.categories c on c.id = p.category_id where c.slug = 'audio')),
  'a subcategory lists only its own products'
);
select ok(
  not exists (
    select 1 from jsonb_array_elements(public.catalog_browse(p_in_stock => true, p_limit => 60) -> 'rows') r
     where r ->> 'slug' = 'bluetooth-speaker-mini'),
  'in stock only hides products with nothing available'
);
select ok(
  (select bool_and(r ->> 'brand' = 'Sonora')
     from jsonb_array_elements(public.catalog_browse(p_brands => array['Sonora'], p_limit => 60) -> 'rows') r),
  'the brand filter keeps only that brand'
);
select ok(
  jsonb_array_length(public.catalog_browse(p_brands => array['Sonora']) -> 'brands') > 1,
  'brand facets ignore the brand filter itself'
);
select ok(
  (select bool_and((r ->> 'rating_avg')::numeric >= 4.5)
     from jsonb_array_elements(public.catalog_browse(p_min_rating => 4.5, p_limit => 60) -> 'rows') r),
  'the rating filter keeps 4.5 and up'
);
select ok(
  (select bool_and((r ->> 'min_price_cents')::int <= 5000)
     from jsonb_array_elements(public.catalog_browse(p_max_cents => 5000, p_limit => 60) -> 'rows') r),
  'the price filter keeps products under $50'
);
select ok(
  (with r as (
     select (x ->> 'min_price_cents')::int as price, ord
       from jsonb_array_elements(public.catalog_browse(p_sort => 'price_asc', p_limit => 60) -> 'rows')
            with ordinality as t (x, ord))
   select bool_and(a.price <= b.price) from r a join r b on b.ord = a.ord + 1),
  'price low to high is ascending'
);
select is(
  jsonb_array_length(public.catalog_browse(p_limit => 5, p_offset => 5) -> 'rows'),
  5,
  'pages hold the requested number of rows'
);
select is(
  public.catalog_browse(p_collection => 'best-sellers', p_sort => 'curated') #>> '{rows,0,slug}',
  'wireless-headphones-pro',
  'curated order follows the collection'
);
select is(
  (public.catalog_browse(p_collection => 'popular-for-offices') ->> 'total')::int,
  0,
  'business-only collections are empty for guests'
);
select is(
  public.storefront_clock() ->> 'cutoff',
  '15:00',
  'the clock carries the cut-off'
);
select ok(
  public.storefront_clock() -> 'holidays' ? '2026-11-09',
  'the clock carries the holidays'
);

-- Business buyers: no prices, and price filters and sorts do nothing.
select tests.login_as('sokha@kstore.example');

select ok(
  (select bool_and(r ->> 'min_price_cents' is null)
     from jsonb_array_elements(public.catalog_browse(p_limit => 60) -> 'rows') r),
  'business buyers get no prices'
);
select is(
  (public.catalog_browse(p_max_cents => 1) ->> 'total')::int,
  (public.catalog_browse() ->> 'total')::int,
  'business buyers cannot filter by price'
);
select is(
  public.catalog_browse() -> 'price_bounds',
  'null'::jsonb,
  'business buyers get no price bounds'
);
select ok(
  (public.catalog_browse(p_collection => 'popular-for-offices') ->> 'total')::int > 0,
  'business buyers see their collections'
);

-- Staff browsing the shop still see only what customers see.
select tests.login_as('visal@kstore.example');

select is(
  (public.catalog_browse() ->> 'total')::int,
  (select count(*)::int from public.products where status = 'active'),
  'drafts never reach the storefront, even for staff'
);

select * from finish();
rollback;
