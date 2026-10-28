-- F11 · Home, categories & product list (CAT-02, CAT-04, CAT-06; C-01 – C-03b).
--
-- * catalog_browse is the one read behind the product list (C-03), the
--   category pane (C-02) and the home rails (C-01). It runs as the caller
--   (security invoker), so RLS still decides what is visible: only active
--   products and variants, and no prices for business buyers. On top of
--   that it ignores price filters and price sorts for business buyers, so a
--   crafted request cannot probe retail prices through filtering either.
-- * Collections carry an audience. RLS does not filter on it, so a
--   collection that is not for the caller's audience (retail for guests and
--   customers, business for business buyers) browses as empty here, and the
--   app filters banners the same way.
-- * The facets (brands with counts, price bounds) are computed on the
--   filtered set minus their own filter, so picking a brand keeps the other
--   brands listed and the price slider keeps its range.
-- * storefront_clock gives the app the server's time, the cut-off and the
--   holidays in one call, so the C-01 countdown follows the server clock
--   (UTC+7), not the device's.

-- ---------------------------------------------------------------------------
-- Indexes for the list sorts
-- ---------------------------------------------------------------------------

create index products_active_sold_idx on public.products (sold_count desc)
  where status = 'active';
create index products_active_created_idx on public.products (created_at desc)
  where status = 'active';
create index collection_items_collection_idx on public.collection_items (collection_id, sort);

-- ---------------------------------------------------------------------------
-- catalog_browse
-- ---------------------------------------------------------------------------

-- p_sort: popular (default) | newest | price_asc | price_desc | rating |
-- curated (the collection's own order, for home rails).
create function public.catalog_browse(
  p_category uuid default null,
  p_collection text default null,
  p_brands text[] default null,
  p_min_cents integer default null,
  p_max_cents integer default null,
  p_min_rating numeric default null,
  p_in_stock boolean default false,
  p_same_day boolean default false,
  p_sort text default 'popular',
  p_limit integer default 20,
  p_offset integer default 0
)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  v_business boolean := public.is_business();
  v_audience text := case when public.is_business() then 'business' else 'retail' end;
  v_min integer := case when public.is_business() then null else p_min_cents end;
  v_max integer := case when public.is_business() then null else p_max_cents end;
  v_brands text[] := case when cardinality(p_brands) > 0 then p_brands end;
  v_sort text := coalesce(p_sort, 'popular');
  v_collection uuid;
  v_rows jsonb;
  v_total int;
  v_brand_facets jsonb;
  v_bounds jsonb;
  v_all_same_day boolean;
begin
  if v_sort not in ('popular', 'newest', 'price_asc', 'price_desc', 'rating', 'curated') then
    v_sort := 'popular';
  end if;
  if v_business and v_sort in ('price_asc', 'price_desc') then
    v_sort := 'popular';
  end if;

  if p_collection is not null then
    select c.id into v_collection
      from public.collections c
     where c.slug = p_collection
       and c.active
       and c.audience::text in ('all', v_audience);
    if v_collection is null then
      return jsonb_build_object(
        'rows', '[]'::jsonb, 'total', 0, 'brands', '[]'::jsonb,
        'price_bounds', null, 'all_same_day', false);
    end if;
  end if;

  with recursive tree as (
    select c.id from public.categories c where c.id = p_category and c.active
    union all
    select c.id from public.categories c join tree t on c.parent_id = t.id where c.active
  ),
  base as (
    select p.id, p.slug, p.name, p.brand, p.rating_avg, p.rating_count, p.sold_count,
           p.same_day, p.tags, p.rfq_enabled, p.rfq_min_qty, p.created_at,
           ci.sort as curated_sort,
           price.amount_cents as min_price,
           price.compare_at_cents as compare_at,
           (select coalesce(sum(greatest(a.available, 0)), 0)
              from public.variant_availability a
              join public.product_variants v on v.id = a.variant_id
             where a.product_id = p.id and v.active) as available
      from public.products p
      left join public.collection_items ci
        on ci.collection_id = v_collection and ci.product_id = p.id
      left join lateral (
        select pr.amount_cents, pr.compare_at_cents
          from public.product_variants v
          join public.prices pr on pr.variant_id = v.id
         where v.product_id = p.id and v.active
         order by pr.amount_cents
         limit 1
      ) price on true
     where p.status = 'active'
       and (p_category is null or p.category_id in (select id from tree))
       and (v_collection is null or ci.product_id is not null)
  ),
  scoped as (
    select * from base b
     where (not coalesce(p_in_stock, false) or b.available > 0)
       and (not coalesce(p_same_day, false) or b.same_day)
       and (p_min_rating is null or b.rating_avg >= p_min_rating)
  ),
  priced as (
    select * from scoped s
     where (v_min is null or s.min_price >= v_min)
       and (v_max is null or s.min_price <= v_max)
  ),
  filtered as (
    select * from priced p
     where v_brands is null or p.brand = any (v_brands)
  )
  select
    (select count(*) from filtered),
    (select coalesce(bool_and(f.same_day), false) from filtered f),
    (select coalesce(jsonb_agg(jsonb_build_object('brand', b.brand, 'count', b.n)
                               order by b.n desc, b.brand), '[]')
       from (select p.brand, count(*) as n from priced p
              where p.brand is not null and btrim(p.brand) <> ''
              group by p.brand) b),
    (select case when v_business or count(s.min_price) = 0 then null
                 else jsonb_build_object('min', min(s.min_price), 'max', max(s.min_price)) end
       from scoped s),
    (select coalesce(jsonb_agg(page.row_data order by page.rn), '[]')
       from (
         select row_number() over (
                  order by
                    case when v_sort = 'curated' then f.curated_sort end asc nulls last,
                    case when v_sort = 'newest' then f.created_at end desc,
                    case when v_sort = 'price_asc' then f.min_price end asc nulls last,
                    case when v_sort = 'price_desc' then f.min_price end desc nulls last,
                    case when v_sort = 'rating' then f.rating_avg end desc,
                    case when v_sort = 'rating' then f.rating_count end desc,
                    f.sold_count desc, f.rating_count desc, f.id
                ) as rn,
                jsonb_build_object(
                  'id', f.id,
                  'slug', f.slug,
                  'name', f.name,
                  'brand', f.brand,
                  'rating_avg', f.rating_avg,
                  'rating_count', f.rating_count,
                  'sold_count', f.sold_count,
                  'same_day', f.same_day,
                  'tags', to_jsonb(f.tags),
                  'rfq_enabled', f.rfq_enabled,
                  'rfq_min_qty', f.rfq_min_qty,
                  'min_price_cents', f.min_price,
                  'compare_at_cents', f.compare_at,
                  'available', f.available,
                  'main_image', (select i.path from public.product_images i
                                  where i.product_id = f.id order by i.sort limit 1)
                ) as row_data
           from filtered f
       ) page
      where page.rn > greatest(p_offset, 0)
        and page.rn <= greatest(p_offset, 0) + least(greatest(p_limit, 1), 60))
    into v_total, v_all_same_day, v_brand_facets, v_bounds, v_rows;

  return jsonb_build_object(
    'rows', v_rows,
    'total', v_total,
    'brands', v_brand_facets,
    'price_bounds', v_bounds,
    'all_same_day', v_all_same_day and v_total > 0
  );
end;
$$;
revoke execute on function public.catalog_browse(uuid, text, text[], integer, integer, numeric, boolean, boolean, text, integer, integer) from public;
grant execute on function public.catalog_browse(uuid, text, text[], integer, integer, numeric, boolean, boolean, text, integer, integer) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- storefront_clock
-- ---------------------------------------------------------------------------

-- {now, cutoff: "15:00", holidays: ["2026-11-09", ...]} for the C-01
-- countdown. Display only: checkout decides the delivery day on the server.
create function public.storefront_clock()
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'now', now(),
    'cutoff', coalesce((select s.value #>> '{}' from public.app_settings s
                         where s.key = 'same_day_cutoff'), '15:00'),
    'holidays', coalesce((select jsonb_agg(h ->> 'date')
                            from public.app_settings s,
                                 jsonb_array_elements(case when jsonb_typeof(s.value) = 'array'
                                                           then s.value else '[]'::jsonb end) h
                           where s.key = 'holidays'), '[]'::jsonb)
  );
$$;
revoke execute on function public.storefront_clock() from public;
grant execute on function public.storefront_clock() to anon, authenticated;
