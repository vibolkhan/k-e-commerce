-- F10 · Inventory & stock reservation (ADM-03, CAT-05, CHK-04; A-06, A-06a).
--
-- * Available = on hand (stock.qty) − reserved. Every unit in `reserved`
--   belongs to a held row in stock_reservations, one per order and variant.
-- * reserve_stock / release_stock / commit_stock are the only way an order
--   moves stock. They are service-role only: checkout, payment, cancel and
--   fulfilment Edge Functions call them (F17 – F20, F31).
--     reserve  at order placement (KHQR and COD): reserved += n
--     release  on KHQR expiry or cancel before packing: reserved -= n
--     commit   when the goods leave the store: qty -= n, reserved -= n
-- * Row locks: each function locks the order row, then the stock rows it
--   touches with FOR UPDATE in variant_id order, so two checkouts for the
--   last unit queue up and the second one sees what the first one took.
--   Locking in one order means concurrent orders never deadlock.
-- * pg_cron runs release_expired_reservations() every minute: unpaid KHQR
--   holds are released once orders.reserved_until (placement +
--   app_settings.stock_hold_minutes) has passed. The order and payment
--   status are left to the KHQR flow (F18), which may reserve again on retry.
-- * adjust_stock is A-06a: add, remove or set a count with a reason, acting
--   as the staff member so audit_logs records who changed the stock.
-- * Low-stock alerts fire once per crossing: stock.low_alerted_at is set when
--   available falls to the alert level and cleared when it rises above it.
--   The functions return the crossings; the Edge Function notifies staff.
-- * stock_movements.delta: for `reserved` / `released` rows it is the change
--   in available; for every other reason it is the change in on hand.

-- ---------------------------------------------------------------------------
-- Schema
-- ---------------------------------------------------------------------------

create extension if not exists pg_cron;

alter table public.stock add column low_alerted_at timestamptz;

create table public.stock_reservations (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders (id) on delete cascade,
  variant_id uuid not null references public.product_variants (id) on delete restrict,
  warehouse_id uuid not null references public.warehouses (id) on delete restrict,
  qty integer not null check (qty > 0),
  status text not null default 'held' check (status in ('held', 'committed', 'released')),
  created_at timestamptz not null default now(),
  settled_at timestamptz,
  unique (order_id, variant_id, warehouse_id)
);
create index stock_reservations_held_idx on public.stock_reservations (variant_id)
  where status = 'held';

alter table public.stock_reservations enable row level security;
create policy "stock_reservations: staff read"
  on public.stock_reservations for select to authenticated
  using ((select public.is_staff()));

-- release_expired_reservations() scans unpaid orders by hold expiry.
create index orders_reserved_until_idx on public.orders (reserved_until)
  where status = 'pending_payment' and reserved_until is not null;

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- The store's warehouse (v1 has one; the same pick as catalog_save_product).
create function private.default_warehouse()
returns uuid
language sql
stable
set search_path = ''
as $$
  select id from public.warehouses where active order by created_at limit 1;
$$;

-- Sets or clears the low-stock flag for these variants and returns the ones
-- that just fell to their alert level:
-- [{variant_id, sku, product_name, available, threshold}].
create function private.low_stock_crossings(p_variants uuid[])
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_crossed jsonb;
begin
  update public.stock
     set low_alerted_at = null
   where variant_id = any (p_variants)
     and low_alerted_at is not null
     and qty - reserved > low_stock_at;

  with crossed as (
    update public.stock s
       set low_alerted_at = now()
     where s.variant_id = any (p_variants)
       and s.low_alerted_at is null
       and s.qty - s.reserved <= s.low_stock_at
    returning s.variant_id, s.qty - s.reserved as available, s.low_stock_at
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'variant_id', c.variant_id,
           'sku', v.sku,
           'product_name', private.variant_label(v.id),
           'available', c.available,
           'threshold', c.low_stock_at
         ) order by v.sku), '[]')
    into v_crossed
    from crossed c
    join public.product_variants v on v.id = c.variant_id;
  return v_crossed;
end;
$$;

-- "LED Desk Lamp · White" — product name (English) and attribute values.
create function private.variant_label(p_variant uuid)
returns text
language sql
stable
set search_path = ''
as $$
  select p.name ->> 'en'
         || coalesce(' · ' || nullif((select string_agg(a.value, ' / ' order by a.key)
                                        from jsonb_each_text(v.attributes) a), ''), '')
    from public.product_variants v
    join public.products p on p.id = v.product_id
   where v.id = p_variant;
$$;

-- ---------------------------------------------------------------------------
-- Order stock: reserve, release, commit (service role only)
-- ---------------------------------------------------------------------------

-- Holds stock for every line of the order. All or nothing:
--   {"status": "reserved", "low": [...]}            held now (or already held)
--   {"status": "insufficient", "items": [{variant_id, requested, available}]}
--   {"status": "not_found"} | {"status": "invalid_status"}
-- KHQR orders awaiting payment get reserved_until = now + stock_hold_minutes.
create function public.reserve_stock(p_order uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order public.orders;
  v_warehouse uuid := private.default_warehouse();
  v_short jsonb;
  v_variants uuid[];
  v_hold int;
begin
  select * into v_order from public.orders where id = p_order for update;
  if not found then
    return jsonb_build_object('status', 'not_found');
  end if;
  if v_order.status not in ('pending_payment', 'awaiting_bank_transfer', 'confirmed') then
    return jsonb_build_object('status', 'invalid_status');
  end if;
  if exists (select 1 from public.stock_reservations
              where order_id = p_order and status = 'held') then
    return jsonb_build_object('status', 'reserved', 'low', '[]'::jsonb);
  end if;

  select array_agg(distinct variant_id order by variant_id) into v_variants
    from public.order_items where order_id = p_order;
  if v_variants is null then
    return jsonb_build_object('status', 'invalid_status');
  end if;

  -- The lock: concurrent orders for the same variant wait here.
  perform 1 from public.stock
   where warehouse_id = v_warehouse and variant_id = any (v_variants)
   order by variant_id
     for update;

  with wanted as (
    select variant_id, sum(qty)::int as requested
      from public.order_items where order_id = p_order group by variant_id
  )
  select jsonb_agg(jsonb_build_object(
           'variant_id', w.variant_id,
           'requested', w.requested,
           'available', greatest(coalesce(s.qty - s.reserved, 0), 0)
         ) order by w.variant_id)
    into v_short
    from wanted w
    left join public.stock s on s.variant_id = w.variant_id and s.warehouse_id = v_warehouse
   where coalesce(s.qty - s.reserved, 0) < w.requested;

  if v_short is not null then
    return jsonb_build_object('status', 'insufficient', 'items', v_short);
  end if;

  with wanted as (
    select variant_id, sum(qty)::int as requested
      from public.order_items where order_id = p_order group by variant_id
  ),
  held as (
    insert into public.stock_reservations (order_id, variant_id, warehouse_id, qty)
    select p_order, w.variant_id, v_warehouse, w.requested from wanted w
    on conflict (order_id, variant_id, warehouse_id)
      do update set qty = excluded.qty, status = 'held', settled_at = null, created_at = now()
    returning variant_id, qty
  ),
  moved as (
    insert into public.stock_movements (variant_id, warehouse_id, delta, reason, order_id)
    select h.variant_id, v_warehouse, -h.qty, 'reserved', p_order from held h
  )
  update public.stock s
     set reserved = s.reserved + h.qty
    from held h
   where s.variant_id = h.variant_id and s.warehouse_id = v_warehouse;

  if v_order.payment_method = 'khqr' and v_order.status = 'pending_payment' then
    select coalesce((value #>> '{}')::int, 15) into v_hold
      from public.app_settings where key = 'stock_hold_minutes';
    update public.orders
       set reserved_until = now() + make_interval(mins => coalesce(v_hold, 15))
     where id = p_order;
  end if;

  return jsonb_build_object('status', 'reserved', 'low', private.low_stock_crossings(v_variants));
end;
$$;

-- Gives the order's held units back. Nothing held is a no-op:
--   {"status": "released", "units": n} | {"status": "not_found"}
create function public.release_stock(p_order uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_units int;
  v_variants uuid[];
begin
  perform 1 from public.orders where id = p_order for update;
  if not found then
    return jsonb_build_object('status', 'not_found');
  end if;

  perform 1 from public.stock s
    join public.stock_reservations r
      on r.variant_id = s.variant_id and r.warehouse_id = s.warehouse_id
   where r.order_id = p_order and r.status = 'held'
   order by s.variant_id
     for update of s;

  with released as (
    update public.stock_reservations
       set status = 'released', settled_at = now()
     where order_id = p_order and status = 'held'
    returning variant_id, warehouse_id, qty
  ),
  moved as (
    insert into public.stock_movements (variant_id, warehouse_id, delta, reason, order_id)
    select r.variant_id, r.warehouse_id, r.qty, 'released', p_order from released r
  ),
  restocked as (
    update public.stock s
       set reserved = s.reserved - r.qty
      from released r
     where s.variant_id = r.variant_id and s.warehouse_id = r.warehouse_id
    returning r.variant_id, r.qty
  )
  select coalesce(sum(qty), 0)::int, array_agg(variant_id) into v_units, v_variants
    from restocked;

  update public.orders set reserved_until = null
   where id = p_order and reserved_until is not null;

  if v_variants is not null then
    perform private.low_stock_crossings(v_variants);
  end if;
  return jsonb_build_object('status', 'released', 'units', v_units);
end;
$$;

-- Turns the order's held units into sold ones (the goods left the store):
--   {"status": "committed", "units": n} | {"status": "not_held"} | {"status": "not_found"}
-- Available does not change, so no low-stock crossing can happen here.
create function public.commit_stock(p_order uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_units int;
begin
  perform 1 from public.orders where id = p_order for update;
  if not found then
    return jsonb_build_object('status', 'not_found');
  end if;
  if not exists (select 1 from public.stock_reservations
                  where order_id = p_order and status = 'held') then
    return jsonb_build_object('status', 'not_held');
  end if;

  perform 1 from public.stock s
    join public.stock_reservations r
      on r.variant_id = s.variant_id and r.warehouse_id = s.warehouse_id
   where r.order_id = p_order and r.status = 'held'
   order by s.variant_id
     for update of s;

  with committed as (
    update public.stock_reservations
       set status = 'committed', settled_at = now()
     where order_id = p_order and status = 'held'
    returning variant_id, warehouse_id, qty
  ),
  moved as (
    insert into public.stock_movements (variant_id, warehouse_id, delta, reason, order_id)
    select c.variant_id, c.warehouse_id, -c.qty, 'sold', p_order from committed c
  ),
  sold as (
    update public.products p
       set sold_count = p.sold_count + x.qty
      from (select v.product_id, sum(c.qty)::int as qty
              from committed c join public.product_variants v on v.id = c.variant_id
             group by v.product_id) x
     where p.id = x.product_id
  ),
  shipped as (
    update public.stock s
       set qty = s.qty - c.qty,
           reserved = s.reserved - c.qty
      from committed c
     where s.variant_id = c.variant_id and s.warehouse_id = c.warehouse_id
    returning c.qty
  )
  select coalesce(sum(qty), 0)::int into v_units from shipped;

  update public.orders set reserved_until = null
   where id = p_order and reserved_until is not null;

  return jsonb_build_object('status', 'committed', 'units', v_units);
end;
$$;

-- The scheduled job: releases KHQR holds whose 15 minutes are up. Orders
-- another transaction is working on (e.g. a payment arriving) are skipped
-- and picked up on the next run. Returns how many orders were released.
create function public.release_expired_reservations()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order uuid;
  v_count int := 0;
begin
  for v_order in
    select id from public.orders
     where status = 'pending_payment'
       and payment_method = 'khqr'
       and reserved_until < now()
     order by reserved_until
     limit 500
       for update skip locked
  loop
    perform public.release_stock(v_order);
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

-- ---------------------------------------------------------------------------
-- A-06a: adjust stock (service role, acting as the staff member)
-- ---------------------------------------------------------------------------

-- p_mode: add | remove | set. p_qty: units to add or remove, or the new count.
-- p_reason: received | returned | adjustment | damaged. p_low_stock_at: a new
-- alert level, or null to keep it.
--   {"status": "adjusted", on_hand, reserved, available, low_stock_at, delta, low: [...]}
--   {"status": "below_reserved", reserved} | {"status": "not_found"}
--   {"status": "invalid", "field"}
create function public.adjust_stock(
  p_actor uuid,
  p_variant uuid,
  p_mode text,
  p_qty integer,
  p_reason public.stock_reason,
  p_note text default null,
  p_low_stock_at integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_warehouse uuid := private.default_warehouse();
  v_stock public.stock;
  v_new int;
  v_delta int;
begin
  perform private.act_as(p_actor);

  if p_mode not in ('add', 'remove', 'set') then
    return jsonb_build_object('status', 'invalid', 'field', 'mode');
  end if;
  if p_qty is null or p_qty < 0 or (p_mode <> 'set' and p_qty = 0) then
    return jsonb_build_object('status', 'invalid', 'field', 'qty');
  end if;
  if p_reason not in ('received', 'returned', 'adjustment', 'damaged')
     or (p_mode = 'add' and p_reason = 'damaged')
     or (p_mode = 'remove' and p_reason in ('received', 'returned')) then
    return jsonb_build_object('status', 'invalid', 'field', 'reason');
  end if;
  if p_low_stock_at is not null and p_low_stock_at < 0 then
    return jsonb_build_object('status', 'invalid', 'field', 'low_stock_at');
  end if;
  if not exists (select 1 from public.product_variants where id = p_variant) then
    return jsonb_build_object('status', 'not_found');
  end if;

  -- A variant that was never stocked gets its first row here.
  insert into public.stock (variant_id, warehouse_id, qty)
  values (p_variant, v_warehouse, 0)
  on conflict (variant_id, warehouse_id) do nothing;

  select * into v_stock from public.stock
   where variant_id = p_variant and warehouse_id = v_warehouse
     for update;

  v_new := case p_mode
             when 'add' then v_stock.qty + p_qty
             when 'remove' then v_stock.qty - p_qty
             else p_qty
           end;
  if v_new < v_stock.reserved then
    return jsonb_build_object('status', 'below_reserved', 'reserved', v_stock.reserved);
  end if;
  v_delta := v_new - v_stock.qty;
  if v_delta > 0 and p_reason = 'damaged' or v_delta < 0 and p_reason in ('received', 'returned') then
    return jsonb_build_object('status', 'invalid', 'field', 'reason');
  end if;

  update public.stock
     set qty = v_new,
         low_stock_at = coalesce(p_low_stock_at, low_stock_at)
   where id = v_stock.id;

  if v_delta <> 0 then
    insert into public.stock_movements (variant_id, warehouse_id, delta, reason, note, actor_id)
    values (p_variant, v_warehouse, v_delta, p_reason,
            nullif(btrim(coalesce(p_note, '')), ''), p_actor);
  end if;

  return jsonb_build_object(
    'status', 'adjusted',
    'on_hand', v_new,
    'reserved', v_stock.reserved,
    'available', v_new - v_stock.reserved,
    'low_stock_at', coalesce(p_low_stock_at, v_stock.low_stock_at),
    'delta', v_delta,
    'low', private.low_stock_crossings(array[p_variant])
  );
end;
$$;

-- Active catalog staff and super admins: who gets the low-stock alert.
create function public.low_stock_recipients()
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select s.profile_id
    from public.staff_members s
    join public.profiles p on p.id = s.profile_id
   where s.status = 'active'
     and s.staff_role in ('catalog', 'super_admin')
     and p.role = 'staff'
     and not p.is_blocked
     and p.deleted_at is null;
$$;

revoke execute on function public.reserve_stock(uuid) from public, anon, authenticated;
revoke execute on function public.release_stock(uuid) from public, anon, authenticated;
revoke execute on function public.commit_stock(uuid) from public, anon, authenticated;
revoke execute on function public.release_expired_reservations() from public, anon, authenticated;
revoke execute on function public.adjust_stock(uuid, uuid, text, integer, public.stock_reason, text, integer)
  from public, anon, authenticated;
revoke execute on function public.low_stock_recipients() from public, anon, authenticated;
revoke execute on function private.default_warehouse() from public, anon, authenticated;
revoke execute on function private.low_stock_crossings(uuid[]) from public, anon, authenticated;
revoke execute on function private.variant_label(uuid) from public, anon, authenticated;
grant execute on function public.reserve_stock(uuid) to service_role;
grant execute on function public.release_stock(uuid) to service_role;
grant execute on function public.commit_stock(uuid) to service_role;
grant execute on function public.release_expired_reservations() to service_role;
grant execute on function public.adjust_stock(uuid, uuid, text, integer, public.stock_reason, text, integer)
  to service_role;
grant execute on function public.low_stock_recipients() to service_role;

select cron.schedule(
  'release-expired-stock',
  '* * * * *',
  'select public.release_expired_reservations()'
);

-- ---------------------------------------------------------------------------
-- Reads for A-06 (any staff: sales and support view, catalog edits)
-- ---------------------------------------------------------------------------

-- One row per variant of a non-archived product, with the summary tiles and
-- the filter counts. p_filter: restock (low or out) | out | all.
create function public.inventory_admin_list(
  p_search text default null,
  p_filter text default 'restock',
  p_limit integer default 25,
  p_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_search text := nullif(btrim(coalesce(p_search, '')), '');
  v_warehouse uuid := private.default_warehouse();
  v_result jsonb;
begin
  if not public.is_staff() then
    raise exception 'staff only' using errcode = '42501';
  end if;

  with base as (
    select v.id as variant_id, v.sku, v.attributes, p.id as product_id, p.name, v.sort,
           s.id is not null as stocked,
           coalesce(s.qty, 0) as on_hand,
           coalesce(s.reserved, 0) as reserved,
           coalesce(s.qty - s.reserved, 0) as available,
           coalesce(s.low_stock_at, 10) as alert_at,
           pr.amount_cents
      from public.product_variants v
      join public.products p on p.id = v.product_id
      left join public.stock s on s.variant_id = v.id and s.warehouse_id = v_warehouse
      left join public.prices pr on pr.variant_id = v.id
     where v.active and p.status <> 'archived'
  ),
  stated as (
    select b.*,
           case when not b.stocked then 'none'
                when b.available <= 0 then 'out'
                when b.available <= b.alert_at then 'low'
                else 'ok' end as state
      from base b
  ),
  searched as (
    select * from stated s
     where v_search is null
        or s.sku ilike '%' || v_search || '%'
        or s.name ->> 'en' ilike '%' || v_search || '%'
        or coalesce(s.name ->> 'km', '') ilike '%' || v_search || '%'
  ),
  filtered as (
    select * from searched s
     where case p_filter
             when 'out' then s.state = 'out'
             when 'all' then true
             else s.state in ('low', 'out')
           end
  )
  select jsonb_build_object(
    'summary', (select jsonb_build_object(
                  'low', count(*) filter (where state = 'low'),
                  'out', count(*) filter (where state = 'out'),
                  'reserved_units', coalesce(sum(reserved), 0),
                  'stock_value_cents', coalesce(sum(on_hand::bigint * coalesce(amount_cents, 0)), 0))
                  from stated),
    'counts', (select jsonb_build_object(
                 'restock', count(*) filter (where state in ('low', 'out')),
                 'out', count(*) filter (where state = 'out'),
                 'all', count(*))
                 from searched),
    'total', (select count(*) from filtered),
    'rows', (select coalesce(jsonb_agg(row_data order by rank, available, sku), '[]')
               from (
                 select case f.state when 'out' then 0 when 'low' then 1 when 'ok' then 2 else 3 end as rank,
                        f.available, f.sku,
                        jsonb_build_object(
                          'variant_id', f.variant_id,
                          'product_id', f.product_id,
                          'sku', f.sku,
                          'name', f.name,
                          'attributes', f.attributes,
                          'main_image', (select i.path from public.product_images i
                                          where i.product_id = f.product_id
                                          order by (i.variant_id = f.variant_id) desc nulls last, i.sort
                                          limit 1),
                          'on_hand', f.on_hand,
                          'reserved', f.reserved,
                          'available', f.available,
                          'alert_at', f.alert_at,
                          'state', f.state,
                          'last', (select jsonb_build_object(
                                            'reason', m.reason,
                                            'delta', m.delta,
                                            'note', m.note,
                                            'at', m.created_at,
                                            'actor', a.full_name,
                                            'order_number', o.number)
                                     from public.stock_movements m
                                     left join public.profiles a on a.id = m.actor_id
                                     left join public.orders o on o.id = m.order_id
                                    where m.variant_id = f.variant_id
                                      and m.reason not in ('reserved', 'released')
                                    order by m.created_at desc
                                    limit 1)
                        ) as row_data
                   from filtered f
                  order by rank, f.available, f.sku
                  limit greatest(p_limit, 1) offset greatest(p_offset, 0)
               ) page)
  ) into v_result;

  return v_result;
end;
$$;
revoke execute on function public.inventory_admin_list(text, text, integer, integer) from public, anon;
grant execute on function public.inventory_admin_list(text, text, integer, integer) to authenticated;

-- A-06a and "View adjustment history": stock movements, newest first, for
-- one variant or (p_variant null) every variant. Staff cannot read names of
-- other staff or order numbers directly, so this reads them for them.
create function public.stock_history(p_variant uuid default null, p_limit integer default 30)
returns table (
  at timestamptz,
  variant_id uuid,
  sku text,
  label text,
  reason public.stock_reason,
  delta integer,
  note text,
  order_number text,
  actor_name text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.is_staff() then
    raise exception 'staff only' using errcode = '42501';
  end if;
  return query
    select m.created_at, m.variant_id, v.sku, private.variant_label(v.id),
           m.reason, m.delta, m.note, o.number, a.full_name
      from public.stock_movements m
      join public.product_variants v on v.id = m.variant_id
      left join public.orders o on o.id = m.order_id
      left join public.profiles a on a.id = m.actor_id
     where p_variant is null or m.variant_id = p_variant
     order by m.created_at desc, m.id
     limit least(greatest(p_limit, 1), 200);
end;
$$;
revoke execute on function public.stock_history(uuid, integer) from public, anon;
grant execute on function public.stock_history(uuid, integer) to authenticated;
