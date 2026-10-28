-- F12 search: matching in English and Khmer, typos, "Did you mean",
-- suggestions, popular categories, recent searches and the search log, as
-- guests, customers, business buyers and staff.
begin;
select plan(44);

-- ---------------------------------------------------------------------------
-- Matching (guest)
-- ---------------------------------------------------------------------------
select tests.logout();

select is(
  (select r -> 'name' ->> 'en'
     from jsonb_array_elements(public.catalog_browse(p_q => 'headphones') -> 'rows') r limit 1),
  'Wireless Headphones Pro',
  'the best match comes first'
);
select ok(
  (select bool_and(r -> 'name' ->> 'en' ilike '%headphone%')
     from jsonb_array_elements(public.catalog_browse(p_q => 'headphones', p_limit => 60) -> 'rows') r),
  'a whole word finds only products named with it'
);
select ok(
  (public.catalog_browse(p_q => 'head') ->> 'total')::int >= 4,
  'a word start finds the whole word'
);
select ok(
  (public.catalog_browse(p_q => 'he') ->> 'total')::int > 0,
  'two letters are enough, even an English stopword'
);
select ok(
  exists (select 1 from jsonb_array_elements(public.catalog_browse(p_q => 'headphnes') -> 'rows') r
           where r ->> 'slug' = 'wireless-headphones-pro'),
  'a small typo still finds the product'
);
select is(
  (public.catalog_browse(p_q => 'hedfones') ->> 'total')::int, 0,
  'a heavy typo finds nothing'
);
select is(
  public.search_did_you_mean('hedfones'), 'headphones',
  '"hedfones" suggests "headphones"'
);
select is(
  public.search_did_you_mean('wireless hedfones'), 'wireless headphones',
  'only the unknown word is corrected'
);
select is(public.search_did_you_mean('headphones'), null, 'nothing to correct');
select is(public.search_did_you_mean('zzzzqq'), null, 'no suggestion when nothing is close');
select ok(
  exists (select 1 from jsonb_array_elements(public.catalog_browse(p_q => 'កាស') -> 'rows') r
           where r ->> 'slug' = 'wireless-headphones-pro'),
  'a Khmer word inside a Khmer name is found'
);
select ok(
  not exists (select 1 from jsonb_array_elements(public.catalog_browse(p_q => 'កាស', p_limit => 60) -> 'rows') r
               where r ->> 'slug' in ('everyday-backpack-22l', 'a4-copy-paper-80gsm')),
  'a short Khmer word does not match names that only share letters'
);
select is(
  (public.catalog_browse(p_q => 'សំឡេង') ->> 'total')::int,
  (select count(*)::int from public.products p join public.categories c on c.id = p.category_id
    where p.status = 'active' and c.slug = 'audio'),
  'a Khmer category name finds its products'
);
select ok(
  (select bool_and(r ->> 'brand' = 'Sonora')
     from jsonb_array_elements(public.catalog_browse(p_q => 'sonora', p_limit => 60) -> 'rows') r),
  'a brand finds its products'
);
select ok(
  exists (select 1 from jsonb_array_elements(public.catalog_browse(p_q => 'kitchen') -> 'rows') r
           where r ->> 'slug' = 'ceramic-coffee-mug-set'),
  'an English category name finds its products'
);
select is(
  (public.catalog_browse(p_q => 'rice cooker') ->> 'total')::int, 0,
  'drafts are never found'
);
select is(
  (public.catalog_browse(p_q => '%') ->> 'total')::int, 0,
  'LIKE wildcards are matched literally'
);
select is(
  (public.catalog_browse(p_q => '   ') ->> 'total')::int, 0,
  'a blank query finds nothing'
);
select ok(
  not exists (select 1 from jsonb_array_elements(
                public.catalog_browse(p_q => 'speaker', p_in_stock => true, p_limit => 60) -> 'rows') r
               where r ->> 'slug' = 'bluetooth-speaker-mini'),
  'search results take the list filters'
);
select is(
  (select array_agg(r ->> 'slug' order by ord)
     from jsonb_array_elements(public.catalog_browse(p_q => 'speaker', p_sort => 'price_asc', p_limit => 60) -> 'rows')
          with ordinality t (r, ord)),
  (select array_agg(r ->> 'slug' order by (r ->> 'min_price_cents')::int, ord)
     from jsonb_array_elements(public.catalog_browse(p_q => 'speaker', p_sort => 'price_asc', p_limit => 60) -> 'rows')
          with ordinality t (r, ord)),
  'search results take the list sorts'
);
select is(
  (public.catalog_browse(p_sort => 'relevance') ->> 'total')::int,
  (select count(*)::int from public.products where status = 'active'),
  'Best match without a query lists everything (as popular)'
);

-- ---------------------------------------------------------------------------
-- Suggestions and popular categories
-- ---------------------------------------------------------------------------
select is(
  public.catalog_suggest('h') -> 'terms', '[]'::jsonb,
  'no suggestions before 2 characters'
);
select ok(
  (select bool_and(t ->> 'term' like 'head%')
     from jsonb_array_elements(public.catalog_suggest('head') -> 'terms') t)
  and jsonb_array_length(public.catalog_suggest('head') -> 'terms') > 0,
  'suggestions complete the word being typed'
);
select is(
  public.catalog_suggest('head') #>> '{scope,category,slug}', 'audio',
  '"headphones in Audio"'
);
select ok(
  jsonb_array_length(public.catalog_suggest('head') -> 'products') between 1 and 3,
  'up to three products are suggested'
);
select is(
  public.catalog_suggest('hedfones') -> 'terms' -> 0,
  '{"term": "headphones", "fuzzy": true}'::jsonb,
  'a misspelling suggests the right word while typing'
);
select ok(
  (select bool_and(t ->> 'term' like 'កាស%')
     from jsonb_array_elements(public.catalog_suggest('កាស') -> 'terms') t)
  and jsonb_array_length(public.catalog_suggest('កាស') -> 'terms') > 0,
  'Khmer suggestions'
);
select ok(
  jsonb_array_length(public.popular_categories()) between 1 and 6
  and not exists (select 1 from jsonb_array_elements(public.popular_categories()) c
                   join public.categories x on x.id = (c ->> 'id')::uuid where not x.active),
  'up to six active popular categories'
);

-- ---------------------------------------------------------------------------
-- Search documents follow the catalog
-- ---------------------------------------------------------------------------
select tests.as_owner();
update public.products set name = name || '{"en": "Noise Cancelling Earmuffs"}'
 where slug = 'wireless-headphones-pro';
update public.categories set name = name || '{"en": "Sound"}' where slug = 'audio';
select tests.logout();

select ok(
  exists (select 1 from jsonb_array_elements(public.catalog_browse(p_q => 'earmuffs') -> 'rows') r
           where r ->> 'slug' = 'wireless-headphones-pro'),
  'a renamed product is found by its new name'
);
select is(
  public.catalog_suggest('earmu') -> 'terms' -> 0 ->> 'term', 'earmuffs',
  'the new name is suggested'
);
select ok(
  (public.catalog_browse(p_q => 'sound') ->> 'total')::int >= 13,
  'a renamed category is found by its new name'
);

-- ---------------------------------------------------------------------------
-- Access
-- ---------------------------------------------------------------------------
select throws_ok(
  'select * from public.product_search',
  '42501', null,
  'guests cannot read the search documents'
);
select throws_ok(
  'select * from public.search_vocabulary',
  '42501', null,
  'guests cannot read the vocabulary'
);

-- Business buyers: no prices in results or suggestions.
select tests.login_as('sokha@kstore.example');
select ok(
  (select bool_and(r ->> 'min_price_cents' is null)
     from jsonb_array_elements(public.catalog_browse(p_q => 'speaker', p_limit => 60) -> 'rows') r),
  'business buyers get no prices in results'
);
select ok(
  (select bool_and(p ->> 'min_price_cents' is null)
     from jsonb_array_elements(public.catalog_suggest('speaker') -> 'products') p),
  'business buyers get no prices in suggestions'
);

-- ---------------------------------------------------------------------------
-- Recent searches and the log
-- ---------------------------------------------------------------------------
select tests.logout();
select public.record_search('Guest Lamp', 1, 120);
select tests.as_owner();
select is(
  (select results || '/' || took_ms from public.search_log where query = 'guest lamp'),
  '1/120',
  'guest searches are logged, normalised, with the time they took'
);

select tests.login_as('dara@kstore.example');
select public.record_search('Rice cooker', 0, 300);
select public.record_search('rice  cooker', 0, 280);
select public.record_search('backpack', 1, 90);
select is(
  (select array_agg(query order by searched_at desc, query) from public.search_history),
  array['backpack', 'rice cooker'],
  'recent searches: own, normalised, once each'
);
select throws_ok(
  $$insert into public.search_history (profile_id, query)
    values (tests.uid('dara@kstore.example'), 'x')$$,
  '42501', null,
  'shoppers cannot write history directly'
);
select ok(not exists (select 1 from public.search_log), 'shoppers cannot read the log');

select tests.login_as('bopha@kstore.example');
select is((select count(*)::int from public.search_history), 0, 'nobody sees another shopper''s searches');
select public.record_search('item ' || g, 1, 10) from generate_series(1, 25) g;
select tests.as_owner();
select is(
  (select count(*)::int from public.search_history where profile_id = tests.uid('bopha@kstore.example')),
  20,
  'only the last 20 are kept'
);
select private.anonymise_account(tests.uid('bopha@kstore.example'));
select is(
  (select count(*)::int from public.search_history where profile_id = tests.uid('bopha@kstore.example')),
  0,
  'a deleted account''s searches are forgotten'
);

select tests.login_as('dara@kstore.example');
select is(
  tests.rows('delete from public.search_history'), 2,
  'shoppers clear their own recent searches'
);

select tests.login_as('visal@kstore.example');
select ok((select count(*) from public.search_log) > 0, 'staff read the search log');

select * from finish();
rollback;
