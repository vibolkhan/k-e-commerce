-- F13 · Product detail (CAT-01, CAT-05; C-05 – C-05e).
--
-- * product_detail is the one read behind the product page: the product,
--   its gallery, its active variants with price and stock, and a "You may
--   also like" row. It runs as the caller (security invoker), so RLS still
--   decides what is visible: null for a draft or archived product, no
--   inactive variants, and no prices for business buyers.
-- * Stock is per variant (CAT-05): `available` is on hand minus held, summed
--   over warehouses, and `low_stock` is F10's per-variant alert level, so the
--   page can say "Only 3 left" for the variant that is selected.
-- * The related row is the same category first, then the same brand, most
--   sold first. Its rows have the catalog_browse row shape, so the app reads
--   them with the same parser as the product list.

create function public.product_detail(p_id uuid)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  v_product public.products;
  v_variants jsonb;
  v_images jsonb;
  v_related jsonb;
  v_free jsonb;
begin
  select * into v_product
    from public.products p
   where p.id = p_id and p.status = 'active';
  if v_product.id is null then
    return null;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', v.id,
           'sku', v.sku,
           'attributes', v.attributes,
           'sort', v.sort,
           'price_cents', pr.amount_cents,
           'compare_at_cents', pr.compare_at_cents,
           'available', greatest(coalesce(a.available, 0), 0),
           'low_stock', coalesce(a.low_stock, false)
         ) order by v.sort, v.sku), '[]')
    into v_variants
    from public.product_variants v
    left join public.prices pr on pr.variant_id = v.id
    left join public.variant_availability a on a.variant_id = v.id
   where v.product_id = p_id and v.active;

  select coalesce(jsonb_agg(jsonb_build_object(
           'path', i.path,
           'alt', i.alt,
           'sort', i.sort,
           'variant_id', i.variant_id
         ) order by i.sort, i.id), '[]')
    into v_images
    from public.product_images i
   where i.product_id = p_id;

  with candidates as (
    select p.*,
           case when p.category_id = v_product.category_id then 0 else 1 end as rank
      from public.products p
     where p.status = 'active'
       and p.id <> p_id
       and (p.category_id = v_product.category_id
            or (v_product.brand is not null and p.brand = v_product.brand))
     order by rank, p.sold_count desc, p.rating_count desc, p.id
     limit 8
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', c.id,
           'slug', c.slug,
           'name', c.name,
           'brand', c.brand,
           'rating_avg', c.rating_avg,
           'rating_count', c.rating_count,
           'sold_count', c.sold_count,
           'same_day', c.same_day,
           'tags', to_jsonb(c.tags),
           'rfq_enabled', c.rfq_enabled,
           'rfq_min_qty', c.rfq_min_qty,
           'min_price_cents', (select min(pr.amount_cents)
                                 from public.product_variants v
                                 join public.prices pr on pr.variant_id = v.id
                                where v.product_id = c.id and v.active),
           'compare_at_cents', null,
           'available', (select coalesce(sum(greatest(a.available, 0)), 0)
                           from public.variant_availability a
                           join public.product_variants v on v.id = a.variant_id
                          where v.product_id = c.id and v.active),
           'main_image', (select i.path from public.product_images i
                           where i.product_id = c.id order by i.sort limit 1)
         ) order by c.rank, c.sold_count desc, c.rating_count desc, c.id), '[]')
    into v_related
    from candidates c;

  select s.value into v_free
    from public.app_settings s
   where s.key = 'free_delivery_cents';

  return jsonb_build_object(
    'id', v_product.id,
    'slug', v_product.slug,
    'name', v_product.name,
    'description', v_product.description,
    'brand', v_product.brand,
    'category_id', v_product.category_id,
    'specs', v_product.specs,
    'highlights', v_product.highlights,
    'max_per_order', v_product.max_per_order,
    'same_day', v_product.same_day,
    'rfq_enabled', v_product.rfq_enabled,
    'rfq_min_qty', v_product.rfq_min_qty,
    'rating_avg', v_product.rating_avg,
    'rating_count', v_product.rating_count,
    'sold_count', v_product.sold_count,
    'images', v_images,
    'variants', v_variants,
    'related', v_related,
    'free_delivery_cents', v_free
  );
end;
$$;
revoke execute on function public.product_detail(uuid) from public;
grant execute on function public.product_detail(uuid) to anon, authenticated;
