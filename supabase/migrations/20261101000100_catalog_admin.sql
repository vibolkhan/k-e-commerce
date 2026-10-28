-- F09 · Catalog management (ADM-02, CAT-01, CAT-07; A-05 – A-05e).
--
-- * Product fields the editor needs: highlights, options, same-day flag,
--   quote multiples, who last changed it. Specs are written as an ordered
--   array of {"name", "value"}; older rows may still hold an object.
-- * product_images: ordered gallery per product, alt text required. The
--   first image (lowest sort) is the main image.
-- * Every write goes through the catalog-manage / catalog-import Edge
--   Functions, which call the service-role functions below. They act as the
--   staff member (request.jwt.claims) so audit_row() records the real actor
--   on every price, product and stock change.
-- * Read helpers for A-05 (list), A-05b (price history) and A-05e (impact).

-- ---------------------------------------------------------------------------
-- Product fields
-- ---------------------------------------------------------------------------

alter table public.products
  add column highlights jsonb not null default '[]' check (jsonb_typeof(highlights) = 'array'),
  add column options jsonb not null default '[]' check (jsonb_typeof(options) = 'array'),
  add column same_day boolean not null default true,
  add column rfq_multiple integer not null default 1 check (rfq_multiple >= 1),
  add column updated_by uuid references public.profiles (id) on delete set null;

-- ---------------------------------------------------------------------------
-- Product images (A-05c)
-- ---------------------------------------------------------------------------

create table public.product_images (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products (id) on delete cascade,
  variant_id uuid references public.product_variants (id) on delete set null,
  path text not null check (path <> ''),  -- storage: product-images/<path>
  alt jsonb not null check (jsonb_typeof(alt) = 'object' and coalesce(btrim(alt ->> 'en'), '') <> ''),
  sort integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index product_images_product_idx on public.product_images (product_id, sort);

alter table public.product_images enable row level security;

create trigger set_updated_at before update on public.product_images
  for each row execute function public.set_updated_at();
create trigger audit after insert or update or delete on public.product_images
  for each row execute function public.audit_row();

create policy "product_images: of visible products"
  on public.product_images for select to anon, authenticated
  using (exists (select 1 from public.products p where p.id = product_id));
create policy "product_images: catalog manages"
  on public.product_images for all to authenticated
  using ((select public.is_staff('catalog')))
  with check ((select public.is_staff('catalog')));
grant insert, update, delete on public.product_images to authenticated;

-- ---------------------------------------------------------------------------
-- Acting as a staff member inside service-role functions
-- ---------------------------------------------------------------------------

-- Makes auth.uid() return the staff member for the rest of the transaction,
-- so audit rows carry the actor even though the Edge Function uses the
-- service role.
create function private.act_as(p_actor uuid)
returns void
language plpgsql
set search_path = ''
as $$
begin
  if p_actor is null then
    raise exception 'actor required' using errcode = '22023';
  end if;
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', p_actor, 'role', 'service_role')::text,
    true
  );
end;
$$;
revoke execute on function private.act_as(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Save a product with its variants, prices, images and first stock
-- ---------------------------------------------------------------------------

-- p_product:
--   { id?, category_id, slug?, brand?, name{en,km?}, description{en?,km?},
--     highlights[{en,km?}], specs[{name,value}], tags[], options[{name{en,km?},values[]}],
--     status, is_best_seller, same_day, rfq_enabled, rfq_min_qty?, rfq_multiple,
--     variants[{ id?, sku, barcode?, attributes{}, active, price_cents, compare_at_cents?,
--                initial_qty? }],
--     images[{ id?, path, alt{en,km?}, variant_sku? }] }   -- array order = display order
--
-- Returns {"status": "saved", "id"} or {"status": "sku_taken", "sku"} /
-- {"status": "not_found"} / {"status": "invalid", "field"}.
-- Variants left out of an existing product are switched off (they may be in
-- orders); images left out are removed.
create function public.catalog_save_product(p_actor uuid, p_product jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := nullif(p_product ->> 'id', '')::uuid;
  v_slug text := nullif(btrim(coalesce(p_product ->> 'slug', '')), '');
  v_warehouse uuid;
  v_variant jsonb;
  v_variant_id uuid;
  v_image jsonb;
  v_image_id uuid;
  v_sort int := 0;
  v_keep_variants uuid[] := '{}';
  v_keep_images uuid[] := '{}';
  v_taken text;
  v_qty int;
begin
  perform private.act_as(p_actor);

  if coalesce(btrim(p_product #>> '{name,en}'), '') = '' then
    return jsonb_build_object('status', 'invalid', 'field', 'name');
  end if;
  if not exists (select 1 from public.categories where id = (p_product ->> 'category_id')::uuid) then
    return jsonb_build_object('status', 'invalid', 'field', 'category');
  end if;
  if jsonb_array_length(coalesce(p_product -> 'variants', '[]')) = 0 then
    return jsonb_build_object('status', 'invalid', 'field', 'variants');
  end if;
  if coalesce((p_product ->> 'rfq_enabled')::boolean, false)
     and coalesce((p_product ->> 'rfq_min_qty')::int, 0) < 1 then
    return jsonb_build_object('status', 'invalid', 'field', 'rfq_min_qty');
  end if;

  -- A SKU belongs to one variant across the catalogue.
  select v.value ->> 'sku' into v_taken
    from jsonb_array_elements(p_product -> 'variants') v
    join public.product_variants pv on pv.sku = btrim(v.value ->> 'sku')
   where v_id is null or pv.product_id <> v_id
   limit 1;
  if v_taken is not null then
    return jsonb_build_object('status', 'sku_taken', 'sku', v_taken);
  end if;

  if v_id is null then
    v_slug := coalesce(v_slug, private.product_slug(p_product #>> '{name,en}'));
    insert into public.products (
      category_id, slug, brand, name, description, highlights, specs, tags, options, status,
      is_best_seller, same_day, rfq_enabled, rfq_min_qty, rfq_multiple, created_by, updated_by
    ) values (
      (p_product ->> 'category_id')::uuid,
      v_slug,
      nullif(btrim(coalesce(p_product ->> 'brand', '')), ''),
      private.i18n(p_product -> 'name'),
      coalesce(private.i18n(p_product -> 'description'), '{}'),
      coalesce(p_product -> 'highlights', '[]'),
      coalesce(p_product -> 'specs', '[]'),
      coalesce(array(select jsonb_array_elements_text(p_product -> 'tags')), '{}'),
      coalesce(p_product -> 'options', '[]'),
      coalesce(p_product ->> 'status', 'draft')::public.product_status,
      coalesce((p_product ->> 'is_best_seller')::boolean, false),
      coalesce((p_product ->> 'same_day')::boolean, true),
      coalesce((p_product ->> 'rfq_enabled')::boolean, false),
      (p_product ->> 'rfq_min_qty')::int,
      coalesce((p_product ->> 'rfq_multiple')::int, 1),
      p_actor,
      p_actor
    )
    returning id into v_id;
  else
    update public.products set
      category_id = (p_product ->> 'category_id')::uuid,
      slug = coalesce(v_slug, slug),
      brand = nullif(btrim(coalesce(p_product ->> 'brand', '')), ''),
      name = private.i18n(p_product -> 'name'),
      description = coalesce(private.i18n(p_product -> 'description'), '{}'),
      highlights = coalesce(p_product -> 'highlights', '[]'),
      specs = coalesce(p_product -> 'specs', '[]'),
      tags = coalesce(array(select jsonb_array_elements_text(p_product -> 'tags')), '{}'),
      options = coalesce(p_product -> 'options', '[]'),
      status = coalesce(p_product ->> 'status', status::text)::public.product_status,
      is_best_seller = coalesce((p_product ->> 'is_best_seller')::boolean, false),
      same_day = coalesce((p_product ->> 'same_day')::boolean, true),
      rfq_enabled = coalesce((p_product ->> 'rfq_enabled')::boolean, false),
      rfq_min_qty = (p_product ->> 'rfq_min_qty')::int,
      rfq_multiple = coalesce((p_product ->> 'rfq_multiple')::int, 1),
      updated_by = p_actor
    where id = v_id;
    if not found then
      return jsonb_build_object('status', 'not_found');
    end if;
  end if;

  select id into v_warehouse from public.warehouses where active order by created_at limit 1;

  for v_variant in select value from jsonb_array_elements(p_product -> 'variants') loop
    v_sort := v_sort + 1;
    v_variant_id := nullif(v_variant ->> 'id', '')::uuid;
    if (v_variant ->> 'price_cents')::int is null or (v_variant ->> 'price_cents')::int <= 0 then
      raise exception 'price must be above zero' using errcode = '22023';
    end if;

    if v_variant_id is null then
      insert into public.product_variants (product_id, sku, barcode, attributes, active, sort)
      values (
        v_id,
        btrim(v_variant ->> 'sku'),
        nullif(btrim(coalesce(v_variant ->> 'barcode', '')), ''),
        coalesce(v_variant -> 'attributes', '{}'),
        coalesce((v_variant ->> 'active')::boolean, true),
        v_sort
      )
      returning id into v_variant_id;

      -- First stock for a new variant (later changes: A-06, F10).
      v_qty := coalesce((v_variant ->> 'initial_qty')::int, 0);
      if v_warehouse is not null and v_qty > 0 then
        insert into public.stock (variant_id, warehouse_id, qty)
        values (v_variant_id, v_warehouse, v_qty);
        insert into public.stock_movements (variant_id, warehouse_id, delta, reason, note, actor_id)
        values (v_variant_id, v_warehouse, v_qty, 'received', 'Opening stock', p_actor);
      end if;
    else
      update public.product_variants set
        sku = btrim(v_variant ->> 'sku'),
        barcode = nullif(btrim(coalesce(v_variant ->> 'barcode', '')), ''),
        attributes = coalesce(v_variant -> 'attributes', '{}'),
        active = coalesce((v_variant ->> 'active')::boolean, true),
        sort = v_sort
      where id = v_variant_id and product_id = v_id;
      if not found then
        raise exception 'variant % is not part of this product', v_variant_id using errcode = '22023';
      end if;
    end if;
    v_keep_variants := v_keep_variants || v_variant_id;

    -- Only a real change touches the row, so the audit log holds price changes only.
    insert into public.prices (variant_id, amount_cents, compare_at_cents)
    values (v_variant_id, (v_variant ->> 'price_cents')::int, (v_variant ->> 'compare_at_cents')::int)
    on conflict (variant_id) do update
      set amount_cents = excluded.amount_cents,
          compare_at_cents = excluded.compare_at_cents
      where public.prices.amount_cents is distinct from excluded.amount_cents
         or public.prices.compare_at_cents is distinct from excluded.compare_at_cents;
  end loop;

  update public.product_variants set active = false
   where product_id = v_id and not (id = any (v_keep_variants)) and active;

  v_sort := 0;
  for v_image in select value from jsonb_array_elements(coalesce(p_product -> 'images', '[]')) loop
    if coalesce(btrim(v_image #>> '{alt,en}'), '') = '' then
      raise exception 'image alt text required' using errcode = '22023';
    end if;
    v_variant_id := (
      select id from public.product_variants
       where product_id = v_id and sku = v_image ->> 'variant_sku'
    );
    if nullif(v_image ->> 'id', '') is null then
      insert into public.product_images (product_id, variant_id, path, alt, sort)
      values (v_id, v_variant_id, v_image ->> 'path', private.i18n(v_image -> 'alt'), v_sort)
      returning id into v_image_id;
    else
      v_image_id := (v_image ->> 'id')::uuid;
      update public.product_images set
        variant_id = v_variant_id,
        alt = private.i18n(v_image -> 'alt'),
        sort = v_sort
      where id = v_image_id and product_id = v_id;
    end if;
    v_keep_images := v_keep_images || v_image_id;
    v_sort := v_sort + 1;
  end loop;

  delete from public.product_images where product_id = v_id and not (id = any (v_keep_images));

  return jsonb_build_object('status', 'saved', 'id', v_id);
end;
$$;

-- {"en": " x ", "km": ""} -> {"en": "x"}: trimmed, empty locales dropped.
create function private.i18n(p_text jsonb)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select case when p_text is null or jsonb_typeof(p_text) <> 'object' then null else
    coalesce(
      (select jsonb_object_agg(key, btrim(value))
         from jsonb_each_text(p_text)
        where key in ('en', 'km') and btrim(value) <> ''),
      '{}'
    )
  end;
$$;

-- A unique URL slug from the English name.
create function private.product_slug(p_name text)
returns text
language plpgsql
set search_path = ''
as $$
declare
  v_base text := coalesce(
    nullif(trim(both '-' from regexp_replace(lower(p_name), '[^a-z0-9]+', '-', 'g')), ''),
    'product'
  );
  v_slug text := v_base;
  v_n int := 1;
begin
  while exists (select 1 from public.products where slug = v_slug) loop
    v_n := v_n + 1;
    v_slug := v_base || '-' || v_n;
  end loop;
  return v_slug;
end;
$$;

-- ---------------------------------------------------------------------------
-- Status (archive / restore) and category, one or many products
-- ---------------------------------------------------------------------------

create function public.catalog_set_status(p_actor uuid, p_ids uuid[], p_status public.product_status)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count int;
begin
  perform private.act_as(p_actor);
  update public.products
     set status = p_status, updated_by = p_actor
   where id = any (p_ids) and status <> p_status;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

create function public.catalog_set_category(p_actor uuid, p_ids uuid[], p_category uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count int;
begin
  perform private.act_as(p_actor);
  if not exists (select 1 from public.categories where id = p_category) then
    raise exception 'unknown category' using errcode = '22023';
  end if;
  update public.products
     set category_id = p_category, updated_by = p_actor
   where id = any (p_ids) and category_id <> p_category;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- ---------------------------------------------------------------------------
-- CSV import (A-05d): rows already validated by catalog-import
-- ---------------------------------------------------------------------------

-- p_products: [{ name{en,km?}, description{en?,km?}, brand?, category_id, tags[],
--               variants[{ sku, barcode?, attributes{}, price_cents, initial_qty? }] }]
-- Imported products start as drafts (no images yet). All or nothing.
create function public.catalog_import(p_actor uuid, p_products jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_product jsonb;
  v_result jsonb;
  v_ids uuid[] := '{}';
begin
  for v_product in select value from jsonb_array_elements(p_products) loop
    v_result := public.catalog_save_product(
      p_actor,
      (v_product - 'id' - 'images' - 'status') || '{"status": "draft"}'
    );
    if v_result ->> 'status' <> 'saved' then
      raise exception 'import stopped: %', v_result using errcode = '22023';
    end if;
    v_ids := v_ids || (v_result ->> 'id')::uuid;
  end loop;
  return jsonb_build_object('status', 'imported', 'products', cardinality(v_ids), 'ids', to_jsonb(v_ids));
end;
$$;

-- SKUs from a file that already exist (catalog-import preview).
create function public.catalog_existing_skus(p_skus text[])
returns setof text
language sql
stable
security definer
set search_path = ''
as $$
  select sku from public.product_variants where sku = any (p_skus);
$$;

revoke execute on function public.catalog_save_product(uuid, jsonb) from public, anon, authenticated;
revoke execute on function public.catalog_set_status(uuid, uuid[], public.product_status) from public, anon, authenticated;
revoke execute on function public.catalog_set_category(uuid, uuid[], uuid) from public, anon, authenticated;
revoke execute on function public.catalog_import(uuid, jsonb) from public, anon, authenticated;
revoke execute on function public.catalog_existing_skus(text[]) from public, anon, authenticated;
revoke execute on function private.i18n(jsonb) from public, anon, authenticated;
revoke execute on function private.product_slug(text) from public, anon, authenticated;
grant execute on function public.catalog_save_product(uuid, jsonb) to service_role;
grant execute on function public.catalog_set_status(uuid, uuid[], public.product_status) to service_role;
grant execute on function public.catalog_set_category(uuid, uuid[], uuid) to service_role;
grant execute on function public.catalog_import(uuid, jsonb) to service_role;
grant execute on function public.catalog_existing_skus(text[]) to service_role;

-- ---------------------------------------------------------------------------
-- Reads for the back office (run as the caller; staff only)
-- ---------------------------------------------------------------------------

-- A-05: one row per product with what the table shows, plus the tab counts.
-- p_tab: all | active | draft | archived. p_stock: any | in | low | out.
create function public.catalog_admin_list(
  p_tab text default 'all',
  p_search text default null,
  p_category uuid default null,
  p_stock text default 'any',
  p_quote_only boolean default false,
  p_limit integer default 25,
  p_offset integer default 0
)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  v_search text := nullif(btrim(coalesce(p_search, '')), '');
  v_rows jsonb;
  v_total int;
  v_counts jsonb;
begin
  if not public.is_staff() then
    raise exception 'staff only' using errcode = '42501';
  end if;

  with base as (
    select p.*,
           (select count(*) from public.product_variants v where v.product_id = p.id and v.active) as variant_count,
           (select min(pr.amount_cents) from public.product_variants v
              join public.prices pr on pr.variant_id = v.id
             where v.product_id = p.id and v.active) as min_price,
           (select max(pr.amount_cents) from public.product_variants v
              join public.prices pr on pr.variant_id = v.id
             where v.product_id = p.id and v.active) as max_price,
           (select coalesce(sum(a.available), 0) from public.variant_availability a
              join public.product_variants v on v.id = a.variant_id
             where a.product_id = p.id and v.active) as available,
           (select count(*) from public.variant_availability a
              join public.product_variants v on v.id = a.variant_id
             where a.product_id = p.id and v.active and a.out_of_stock) as out_count,
           (select count(*) from public.variant_availability a
              join public.product_variants v on v.id = a.variant_id
             where a.product_id = p.id and v.active and a.low_stock) as low_count,
           (select count(*) from public.stock s
              join public.product_variants v on v.id = s.variant_id
             where v.product_id = p.id) as stock_rows,
           (select string_agg(v.sku, ' ') from public.product_variants v where v.product_id = p.id) as skus
      from public.products p
     where (p_category is null or p.category_id = p_category
            or p.category_id in (select id from public.categories where parent_id = p_category))
       and (not p_quote_only or p.rfq_enabled)
       and (v_search is null
            or p.name ->> 'en' ilike '%' || v_search || '%'
            or coalesce(p.name ->> 'km', '') ilike '%' || v_search || '%'
            or coalesce(p.brand, '') ilike '%' || v_search || '%'
            or exists (select 1 from public.product_variants v
                        where v.product_id = p.id and v.sku ilike '%' || v_search || '%'))
  ),
  stocked as (
    select b.*,
           case when b.stock_rows = 0 then 'none'
                when b.available <= 0 then 'out'
                when b.out_count > 0 or b.low_count > 0 then 'low'
                else 'in' end as stock_state
      from base b
  ),
  filtered as (
    select * from stocked s
     where (p_stock = 'any'
            or (p_stock = 'in' and s.stock_state = 'in')
            or (p_stock = 'low' and s.stock_state = 'low')
            or (p_stock = 'out' and s.stock_state in ('out', 'none')))
  )
  select
    (select jsonb_build_object(
       'all', count(*) filter (where status <> 'archived'),
       'active', count(*) filter (where status = 'active'),
       'draft', count(*) filter (where status = 'draft'),
       'archived', count(*) filter (where status = 'archived'))
       from filtered),
    (select count(*) from filtered
      where case p_tab when 'all' then status <> 'archived' else status::text = p_tab end),
    (select coalesce(jsonb_agg(row_data order by updated_at desc, id), '[]')
       from (
         select f.updated_at, f.id,
                jsonb_build_object(
                  'id', f.id,
                  'slug', f.slug,
                  'name', f.name,
                  'brand', f.brand,
                  'status', f.status,
                  'category_id', f.category_id,
                  'category', (select c.name from public.categories c where c.id = f.category_id),
                  'first_sku', (select v.sku from public.product_variants v
                                 where v.product_id = f.id order by v.sort, v.created_at limit 1),
                  'variant_count', f.variant_count,
                  'min_price_cents', f.min_price,
                  'max_price_cents', f.max_price,
                  'available', f.available,
                  'out_count', f.out_count,
                  'stock_state', f.stock_state,
                  'rfq_enabled', f.rfq_enabled,
                  'rfq_min_qty', f.rfq_min_qty,
                  'main_image', (select i.path from public.product_images i
                                  where i.product_id = f.id order by i.sort limit 1),
                  'updated_at', f.updated_at,
                  'updated_by', (select pr.full_name from public.profiles pr
                                  where pr.id = coalesce(f.updated_by, f.created_by))
                ) as row_data
           from filtered f
          where case p_tab when 'all' then f.status <> 'archived' else f.status::text = p_tab end
          order by f.updated_at desc, f.id
          limit greatest(p_limit, 1) offset greatest(p_offset, 0)
       ) page)
    into v_counts, v_total, v_rows;

  return jsonb_build_object('counts', v_counts, 'total', v_total, 'rows', v_rows);
end;
$$;
revoke execute on function public.catalog_admin_list(text, text, uuid, text, boolean, integer, integer) from public, anon;
grant execute on function public.catalog_admin_list(text, text, uuid, text, boolean, integer, integer) to authenticated;

-- A-05b: price changes of a product's variants, newest first. Catalog staff
-- cannot read audit_logs directly (super admin only), so this reads it for them.
create function public.product_price_history(p_product uuid)
returns table (
  at timestamptz,
  sku text,
  action text,
  old_cents integer,
  new_cents integer,
  actor_name text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.is_staff('catalog') then
    raise exception 'catalog staff only' using errcode = '42501';
  end if;
  return query
    select l.created_at,
           v.sku,
           l.action,
           case l.action when 'update' then (l.diff #>> '{amount_cents,old}')::int end,
           case l.action
             when 'update' then (l.diff #>> '{amount_cents,new}')::int
             when 'insert' then (l.diff #>> '{new,amount_cents}')::int
           end,
           p.full_name
      from public.audit_logs l
      join public.prices pr on pr.id::text = l.entity_id
      join public.product_variants v on v.id = pr.variant_id
      left join public.profiles p on p.id = l.actor_id
     where l.entity = 'prices'
       and v.product_id = p_product
       and (l.action = 'insert' or l.diff ? 'amount_cents')
     order by l.created_at desc
     limit 50;
end;
$$;
revoke execute on function public.product_price_history(uuid) from public, anon;
grant execute on function public.product_price_history(uuid) to authenticated;

-- A-05e: what archiving touches. Open orders still ship; open quote
-- requests are counted so staff know before confirming.
create function public.catalog_archive_impact(p_product uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.is_staff('catalog') then
    raise exception 'catalog staff only' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'variants', (select count(*) from public.product_variants where product_id = p_product and active),
    'in_stock', (select coalesce(sum(greatest(available, 0)), 0)
                   from public.variant_availability where product_id = p_product),
    'open_orders', (select count(distinct o.id) from public.orders o
                      join public.order_items i on i.order_id = o.id
                     where i.product_id = p_product
                       and o.status in ('pending_payment', 'awaiting_bank_transfer', 'confirmed',
                                        'packing', 'ready', 'out_for_delivery')),
    'open_rfqs', (select count(distinct r.id) from public.rfqs r
                    join public.rfq_items i on i.rfq_id = r.id
                   where i.product_id = p_product
                     and r.status in ('submitted', 'in_review', 'quoted', 'revision_requested'))
  );
end;
$$;
revoke execute on function public.catalog_archive_impact(uuid) from public, anon;
grant execute on function public.catalog_archive_impact(uuid) to authenticated;
