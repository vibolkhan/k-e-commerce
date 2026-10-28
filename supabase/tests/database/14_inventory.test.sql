-- F10: stock reservation, adjustments, low-stock crossings, the expiry job and
-- the A-06 reads. (Two sessions racing for the last unit is covered by
-- supabase/functions/_integration/stock_race_test.ts.)
begin;
select plan(60);

-- ---------------------------------------------------------------- the seed

select is(
  (select count(*)::int from public.stock s
    where s.reserved <> coalesce((select sum(r.qty) from public.stock_reservations r
                                   where r.variant_id = s.variant_id
                                     and r.warehouse_id = s.warehouse_id
                                     and r.status = 'held'), 0)),
  0,
  'every reserved unit in the seed belongs to a held order'
);
select is(
  (select count(*)::int from cron.job where jobname = 'release-expired-stock' and schedule = '* * * * *'),
  1,
  'the expiry job runs every minute'
);

-- ---------------------------------------------------------------- who may call what

select tests.login_as('visal@kstore.example');
select throws_ok($$ select public.reserve_stock(gen_random_uuid()) $$, '42501', null,
  'staff cannot reserve stock directly');
select throws_ok($$ select public.release_stock(gen_random_uuid()) $$, '42501', null,
  'staff cannot release stock directly');
select throws_ok($$ select public.commit_stock(gen_random_uuid()) $$, '42501', null,
  'staff cannot commit stock directly');
select throws_ok($$ select public.release_expired_reservations() $$, '42501', null,
  'staff cannot run the expiry job');
select throws_ok(
  $$ select public.adjust_stock(tests.uid('visal@kstore.example'), gen_random_uuid(), 'add', 1, 'received') $$,
  '42501', null, 'staff cannot adjust stock without the Edge Function');
select throws_ok($$ select public.low_stock_recipients() $$, '42501', null,
  'staff cannot list alert recipients directly');
select throws_ok(
  $$ update public.stock set qty = qty + 1 where variant_id = (select id from public.product_variants where sku = 'MUG-4-SND') $$,
  '42501', null, 'staff cannot write stock rows');

-- A-06 for catalog staff, on the seed.
select is(
  public.inventory_admin_list() -> 'summary',
  '{"low": 5, "out": 3, "reserved_units": 6, "stock_value_cents": 5866000}'::jsonb,
  'summary tiles: low, out, reserved units and stock value at retail price'
);
select is(
  public.inventory_admin_list() -> 'counts',
  '{"restock": 8, "out": 3, "all": 40}'::jsonb,
  'filter counts: needs restock = low + out'
);
select is(
  (select array_agg(r ->> 'state' order by ord)
     from jsonb_array_elements(public.inventory_admin_list(null, 'restock', 25, 0) -> 'rows')
          with ordinality as x (r, ord)),
  array['out', 'out', 'out', 'low', 'low', 'low', 'low', 'low'],
  'needs restock lists out of stock first, then low'
);
select is(
  (public.inventory_admin_list('lmp-led', 'all', 25, 0) #>> '{rows,0,available}')::int,
  3,
  'available = on hand − reserved (LED Desk Lamp 4 − 1)'
);
select is(
  (public.inventory_admin_list(null, 'out', 25, 0) ->> 'total')::int,
  3,
  'the out filter shows sold-out variants only'
);
select is(
  public.inventory_admin_list('MUG-4-SND', 'all', 25, 0) #>> '{rows,0,last,actor}',
  'Visal Keo',
  'each row carries its last change and who made it'
);
select is(
  public.inventory_admin_list('RCK-18', 'all', 25, 0) #>> '{rows,0,state}',
  'none',
  'a variant that was never stocked is not stocked, not out of stock'
);

-- Support can view (A-14d: Products & inventory = View).
select tests.login_as('sophea@kstore.example');
select is(
  (select actor_name from public.stock_history(
     (select id from public.product_variants where sku = 'MUG-4-SND')) limit 1),
  'Visal Keo',
  'support read the stock history with staff names'
);
select is((select sum(qty)::int from public.stock_reservations), 6,
  'staff read the reservations');

-- Customers cannot.
select tests.login_as('dara@kstore.example');
select throws_ok($$ select public.inventory_admin_list() $$, '42501', null,
  'customers cannot read the inventory list');
select throws_ok($$ select * from public.stock_history() $$, '42501', null,
  'customers cannot read the stock history');
select is((select count(*)::int from public.stock_reservations), 0,
  'customers see no reservations');

-- ---------------------------------------------------------------- reserve

select tests.as_owner();
create temporary table t (name text primary key, id uuid) on commit drop;
insert into t values
  ('snk', (select id from public.product_variants where sku = 'SNK-AIR-42')),  -- 3 on hand, alert at 5
  ('mug', (select id from public.product_variants where sku = 'MUG-4-WHT')),
  ('a', gen_random_uuid()), ('b', gen_random_uuid()), ('c', gen_random_uuid()),
  ('d', gen_random_uuid()), ('e', gen_random_uuid());

insert into public.orders (id, profile_id, status, payment_method, payment_status, subtotal_cents, total_cents, address)
select t.id, tests.uid('dara@kstore.example'), o.status::public.order_status,
       o.method::public.payment_method, o.pay::public.payment_status, 100, 100, '{}'
  from (values ('a', 'pending_payment', 'khqr', 'pending'),
               ('b', 'confirmed', 'cod', 'unpaid_cod'),
               ('c', 'confirmed', 'cod', 'unpaid_cod'),
               ('d', 'confirmed', 'cod', 'unpaid_cod'),
               ('e', 'pending_payment', 'khqr', 'pending')) as o (name, status, method, pay)
  join t on t.name = o.name;

insert into public.order_items (order_id, variant_id, product_id, name, sku, unit_price_cents, qty)
select o.id, v.id, v.product_id, '{"en": "x"}', v.sku, 100, i.qty
  from (values ('a', 'snk', 2), ('b', 'snk', 2), ('c', 'snk', 1), ('d', 'snk', 2), ('e', 'mug', 3))
       as i (order_name, variant_name, qty)
  join t o on o.name = i.order_name
  join t tv on tv.name = i.variant_name
  join public.product_variants v on v.id = tv.id;

select is(public.reserve_stock((select id from t where name = 'a')) ->> 'status', 'reserved',
  'order A holds 2 of 3');
select is((select reserved from public.stock where variant_id = (select id from t where name = 'snk')), 2,
  'the hold is counted in reserved');
select ok(
  (select reserved_until between now() + interval '14 minutes' and now() + interval '16 minutes'
     from public.orders where id = (select id from t where name = 'a')),
  'an unpaid KHQR order is held for stock_hold_minutes');
select is(
  (select delta from public.stock_movements
    where order_id = (select id from t where name = 'a') and reason = 'reserved'),
  -2, 'the hold is in the ledger as −2 available');
select is(public.reserve_stock((select id from t where name = 'a')) ->> 'status', 'reserved',
  'reserving the same order again is harmless');
select is((select reserved from public.stock where variant_id = (select id from t where name = 'snk')), 2,
  'and holds nothing twice');

select is(
  public.reserve_stock((select id from t where name = 'b')),
  jsonb_build_object('status', 'insufficient', 'items', jsonb_build_array(jsonb_build_object(
    'variant_id', (select id from t where name = 'snk'), 'requested', 2, 'available', 1))),
  'order B cannot have 2 when 1 is left, and is told what is left');
select is((select reserved from public.stock where variant_id = (select id from t where name = 'snk')), 2,
  'a refused order holds nothing');
select is((select count(*)::int from public.stock_reservations where order_id = (select id from t where name = 'b')), 0,
  'and leaves no reservation rows');

select is(public.reserve_stock((select id from t where name = 'c')) -> 'low', '[]'::jsonb,
  'order C takes the last unit; the low-stock alert already went out with order A');
select is(public.reserve_stock((select id from t where name = 'b')) ->> 'status', 'insufficient',
  'nothing left for order B');

-- ---------------------------------------------------------------- release and commit

select is(public.release_stock((select id from t where name = 'a')), '{"status": "released", "units": 2}'::jsonb,
  'releasing order A gives 2 back');
select is((select reserved from public.stock where variant_id = (select id from t where name = 'snk')), 1,
  'only order C is still held');
select is((select reserved_until from public.orders where id = (select id from t where name = 'a')), null,
  'a released order has no hold time');
select is(public.release_stock((select id from t where name = 'a')) ->> 'units', '0',
  'releasing twice gives nothing back twice');

select is(public.commit_stock((select id from t where name = 'c')), '{"status": "committed", "units": 1}'::jsonb,
  'committing order C ships 1');
select is(
  (select array[qty, reserved] from public.stock where variant_id = (select id from t where name = 'snk')),
  array[2, 0], 'on hand and reserved both drop by the shipped unit');
select is(
  (select delta from public.stock_movements
    where order_id = (select id from t where name = 'c') and reason = 'sold'),
  -1, 'the sale is in the ledger as −1 on hand');
select is(public.commit_stock((select id from t where name = 'c')) ->> 'status', 'not_held',
  'an order is committed once');
select is(public.release_stock((select id from t where name = 'c')) ->> 'units', '0',
  'a committed order has nothing to release');

-- ---------------------------------------------------------------- adjust (A-06a)

select is(
  public.adjust_stock(tests.uid('visal@kstore.example'), (select id from t where name = 'snk'),
                      'add', 10, 'received', ' DN-2210 ') - 'low',
  '{"status": "adjusted", "on_hand": 12, "reserved": 0, "available": 12, "low_stock_at": 5, "delta": 10}'::jsonb,
  'adding 10 received units');
select is((select low_alerted_at from public.stock where variant_id = (select id from t where name = 'snk')), null,
  'back above the alert level re-arms the low-stock alert');
select is(
  (select array[note, (select full_name from public.profiles where id = actor_id)]
     from public.stock_movements
    where variant_id = (select id from t where name = 'snk') and reason = 'received'
    order by created_at desc limit 1),
  array['DN-2210', 'Visal Keo'], 'the movement keeps the note and the staff member');
select ok(
  exists (select 1 from public.audit_logs l
           where l.entity = 'stock'
             and l.entity_id = (select id::text from public.stock where variant_id = (select id from t where name = 'snk'))
             and l.diff #>> '{qty,new}' = '12'
             and l.actor_id = tests.uid('visal@kstore.example')),
  'the audit log names who changed the stock');

select is(public.reserve_stock((select id from t where name = 'd')) ->> 'status', 'reserved',
  'order D holds 2');
select is(
  public.adjust_stock(tests.uid('visal@kstore.example'), (select id from t where name = 'snk'), 'set', 1, 'adjustment'),
  '{"status": "below_reserved", "reserved": 2}'::jsonb,
  'a count cannot go below what open orders hold');
select is(
  public.adjust_stock(tests.uid('visal@kstore.example'), (select id from t where name = 'snk'),
                      'set', 2, 'adjustment', 'Count') #>> '{low,0,product_name}',
  'Running Sneakers Air · 42', 'falling to the alert level reports a crossing');
select is(
  public.adjust_stock(tests.uid('visal@kstore.example'), (select id from t where name = 'snk'), 'add', 1, 'damaged'),
  '{"status": "invalid", "field": "reason"}'::jsonb, 'damaged stock is never added');
select is(
  public.adjust_stock(tests.uid('visal@kstore.example'), (select id from t where name = 'snk'), 'remove', 1, 'received'),
  '{"status": "invalid", "field": "reason"}'::jsonb, 'received stock is never removed');
select is(
  public.adjust_stock(tests.uid('visal@kstore.example'), (select id from t where name = 'snk'), 'add', 0, 'received'),
  '{"status": "invalid", "field": "qty"}'::jsonb, 'adding nothing is refused');
select is(
  public.adjust_stock(tests.uid('visal@kstore.example'), (select id from t where name = 'snk'), 'set', 9, 'damaged'),
  '{"status": "invalid", "field": "reason"}'::jsonb, 'a count that goes up cannot be damage');
select is(
  public.adjust_stock(tests.uid('visal@kstore.example'), gen_random_uuid(), 'add', 1, 'received'),
  '{"status": "not_found"}'::jsonb, 'an unknown variant is not found');
select is(
  public.adjust_stock(tests.uid('visal@kstore.example'),
                      (select id from public.product_variants where sku = 'RCK-18-WHT'),
                      'add', 5, 'received', null, 3) ->> 'on_hand',
  '5', 'the first delivery of a never-stocked variant creates its stock row');

-- ---------------------------------------------------------------- the expiry job

select is(public.reserve_stock((select id from t where name = 'e')) ->> 'status', 'reserved',
  'order E (unpaid KHQR) holds 3 mugs');
update public.orders set reserved_until = now() - interval '1 minute'
 where id = (select id from t where name = 'e');
select ok(public.release_expired_reservations() >= 1, 'the job releases expired holds');
select is(
  (select status from public.stock_reservations where order_id = (select id from t where name = 'e')),
  'released', 'order E is released');
select is((select reserved from public.stock where variant_id = (select id from t where name = 'mug')), 0,
  'and the mugs are available again');

-- ---------------------------------------------------------------- invariants

select is(
  (select count(*)::int from public.stock s
    where s.reserved <> coalesce((select sum(r.qty) from public.stock_reservations r
                                   where r.variant_id = s.variant_id
                                     and r.warehouse_id = s.warehouse_id
                                     and r.status = 'held'), 0)),
  0, 'reserved still equals the held reservations after all of the above');
select is(
  (select array_agg(r order by r) from public.low_stock_recipients() as r),
  array[tests.uid('chenda@kstore.example'), tests.uid('visal@kstore.example')]::uuid[],
  'low-stock alerts go to active catalog staff and super admins');

select * from finish();
rollback;
