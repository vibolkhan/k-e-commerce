-- F12 search timing (US-02: results in under 1 s). Adds 5,000 extra active
-- products with variants, prices and stock inside a transaction, times the
-- typical searches as a guest, and rolls everything back.
--
--   docker exec -i supabase_db_k-e-commerce psql -U postgres -d postgres < tool/search_benchmark.sql

\set ON_ERROR_STOP on
set client_min_messages = warning;
begin;

with words (w) as (
  select unnest(array['wireless', 'headphones', 'speaker', 'portable', 'smart', 'watch',
                      'backpack', 'travel', 'kitchen', 'ceramic', 'lamp', 'desk', 'bottle',
                      'steel', 'cotton', 'shirt', 'running', 'shoes', 'phone', 'case', 'charger',
                      'cable', 'mouse', 'keyboard', 'monitor', 'stand', 'pillow', 'blanket'])
),
cats as (select array_agg(id) as ids from public.categories)
insert into public.products (slug, category_id, brand, name, status)
select 'bench-' || g,
       cats.ids[1 + g % cardinality(cats.ids)],
       (array['Sonora', 'Nimbus', 'Aurel', 'K Basics', 'Volta'])[1 + g % 5],
       jsonb_build_object(
         'en', initcap((select string_agg(w, ' ') from (select w from words order by md5(w || g) limit 3) x)) || ' ' || g,
         'km', (array['កាស', 'ឧបករណ៍បំពងសំឡេង', 'នាឡិកា', 'កាបូប', 'ចង្កៀង'])[1 + g % 5] || ' ' || g),
       'active'
  from generate_series(1, 5000) g, cats;

insert into public.product_variants (product_id, sku)
select id, 'BENCH-' || slug from public.products where slug like 'bench-%';
insert into public.prices (variant_id, amount_cents)
select v.id, 500 + (abs(hashtext(v.sku)) % 20000)
  from public.product_variants v where v.sku like 'BENCH-%';
insert into public.stock (variant_id, warehouse_id, qty)
select v.id, (select id from public.warehouses limit 1), abs(hashtext(v.sku)) % 30
  from public.product_variants v where v.sku like 'BENCH-%';

analyze public.products;
analyze public.product_search;

select count(*) as products from public.products;

set role anon;
\timing on
-- Search results (C-04a), first page.
select (public.catalog_browse(p_q => 'headphones')) ->> 'total' as headphones;
select (public.catalog_browse(p_q => 'wireless head')) ->> 'total' as wireless_head;
select (public.catalog_browse(p_q => 'headphnes')) ->> 'total' as typo;
select (public.catalog_browse(p_q => 'កាស')) ->> 'total' as khmer;
select (public.catalog_browse(p_q => 'speaker', p_in_stock => true, p_max_cents => 5000)) ->> 'total' as filtered;
-- Suggestions while typing (C-04).
select jsonb_array_length(public.catalog_suggest('he') -> 'terms') as suggest_he;
select jsonb_array_length(public.catalog_suggest('headph') -> 'terms') as suggest_headph;
-- No results (C-04b).
select (public.catalog_browse(p_q => 'hedfones')) ->> 'total' as hedfones;
select public.search_did_you_mean('hedfones') as did_you_mean;
\timing off

rollback;
