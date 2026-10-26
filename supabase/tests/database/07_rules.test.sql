-- Business rules enforced by the schema itself.
begin;
select plan(11);

select throws_ok(
  $$ update public.stock set reserved = qty + 1
      where variant_id = (select id from public.product_variants where sku = 'MUG-4-SND') $$,
  '23514', null, 'reserved stock can never exceed stock on hand'
);

-- Zones.
select is(
  (select name from public.delivery_zones where id = public.zone_for_point(11.590, 104.885)),
  'Toul Kork',
  'a Toul Kork pin is in the Toul Kork zone'
);
select is(public.zone_for_point(13.362, 103.860), null, 'Siem Reap is outside every zone');
select is(public.zone_for_point(11.530, 104.950), null, 'paused zones do not take orders');

-- Numbers and totals.
insert into public.orders (id, profile_id, payment_method, subtotal_cents, total_cents, address)
values ('d0000000-0000-4000-8000-0000000009a1', tests.uid('dara@kstore.example'), 'khqr', 1000, 1000, '{}');
select matches(
  (select number from public.orders where id = 'd0000000-0000-4000-8000-0000000009a1'),
  '^K-\d{5}$',
  'order numbers look like K-10265'
);
select throws_ok(
  $$ insert into public.orders (profile_id, payment_method, subtotal_cents, delivery_fee_cents, total_cents, address)
     values (tests.uid('dara@kstore.example'), 'cod', 1000, 150, 1000, '{}') $$,
  '23514', null, 'order total must equal items plus delivery'
);
select lives_ok(
  $$ insert into public.orders (profile_id, payment_method, subtotal_cents, delivery_fee_cents,
                                tax_cents, total_cents, prices_include_tax, address)
     values (tests.uid('sokha@kstore.example'), 'bank_transfer', 204000, 1500, 20550, 226050, false, '{}') $$,
  'quote-based orders may add VAT on top'
);
select throws_ok(
  $$ update public.deliveries set status = 'delivered', delivered_at = now()
      where id = 'e0000000-0000-4000-8000-000000010250' $$,
  '23514', null, 'a delivery needs a proof-of-delivery photo'
);

-- Ratings follow published reviews.
insert into public.reviews (product_id, profile_id, order_id, rating, status)
select id, tests.uid('dara@kstore.example'), 'd0000000-0000-4000-8000-000000010248', 4, 'published'
  from public.products where slug = 'ceramic-coffee-mug-set';
select is(
  (select rating_count from public.products where slug = 'ceramic-coffee-mug-set'),
  1,
  'publishing a review updates the rating count'
);

-- Audit diffs keep only changed columns.
update public.prices set amount_cents = 1900
 where variant_id = (select id from public.product_variants where sku = 'MUG-4-SND');
select is(
  (select array_agg(k) from public.audit_logs, jsonb_object_keys(diff) k where entity = 'prices'),
  array['amount_cents'],
  'an audited update records only what changed'
);

-- Location pruning keeps active deliveries.
select is(public.prune_rider_locations(), 0, 'pruning leaves active deliveries alone');

select * from finish();
rollback;
