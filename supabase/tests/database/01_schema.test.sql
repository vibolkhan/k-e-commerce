begin;
select plan(50);

-- Every public table is protected, and has at least one policy.
select is(
  (select count(*)::int from pg_tables where schemaname = 'public' and not rowsecurity),
  0,
  'every public table has RLS enabled'
);
select is(
  (select count(*)::int
     from pg_tables t
    where t.schemaname = 'public'
      and not exists (
        select 1 from pg_policies p
         where p.schemaname = 'public' and p.tablename = t.tablename
      )),
  0,
  'every public table has at least one policy'
);

-- PRD §9 tables.
select has_table('public', t, 'table ' || t || ' exists')
  from unnest(array[
    'profiles', 'business_profiles', 'staff_members', 'addresses', 'device_tokens',
    'categories', 'products', 'product_variants', 'prices', 'warehouses', 'stock',
    'carts', 'cart_items', 'wishlists', 'orders', 'order_items', 'payments', 'refunds',
    'delivery_zones', 'deliveries', 'rider_locations', 'rfqs', 'rfq_items', 'quotes',
    'quote_items', 'returns', 'reviews', 'conversations', 'messages', 'notifications',
    'banners', 'collections', 'app_settings', 'audit_logs'
  ]) as t;

-- App Flow §5 statuses.
select enum_has_labels('public', 'order_status', array[
  'pending_payment', 'awaiting_bank_transfer', 'confirmed', 'packing', 'ready',
  'out_for_delivery', 'delivered', 'failed_delivery', 'cancelled', 'returned'
], 'order statuses');
select enum_has_labels('public', 'payment_status', array[
  'pending', 'unpaid_cod', 'awaiting_confirmation', 'rejected', 'paid', 'expired',
  'refunded', 'partially_refunded'
], 'payment statuses');
select enum_has_labels('public', 'rfq_status', array[
  'submitted', 'in_review', 'quoted', 'revision_requested', 'accepted', 'rejected',
  'expired', 'cancelled'
], 'RFQ statuses');
select enum_has_labels('public', 'quote_status', array[
  'draft', 'sent', 'accepted', 'rejected', 'expired', 'superseded'
], 'quote statuses');
select enum_has_labels('public', 'delivery_status', array[
  'unassigned', 'assigned', 'picked_up', 'delivered', 'failed'
], 'delivery statuses');
select enum_has_labels('public', 'return_status', array[
  'requested', 'approved', 'picked_up', 'inspected', 'refunded', 'rejected'
], 'return statuses');
select enum_has_labels('public', 'verification_status', array[
  'pending', 'approved', 'rejected'
], 'verification statuses');
select enum_has_labels('public', 'review_status', array[
  'pending', 'published', 'hidden'
], 'review statuses');

-- F03 contract: app_settings(key text pk, value jsonb).
select col_is_pk('public', 'app_settings', 'key', 'app_settings.key is the primary key');
select col_type_is('public', 'app_settings', 'key', 'text', 'app_settings.key is text');
select col_type_is('public', 'app_settings', 'value', 'jsonb', 'app_settings.value is jsonb');

-- Sign-up creates a customer profile with the chosen language.
insert into auth.users (id, email, raw_user_meta_data)
values ('a0000000-0000-4000-8000-0000000000ff', 'new@kstore.example', '{"locale": "km", "full_name": "New User"}');
select is(
  (select role from public.profiles where id = 'a0000000-0000-4000-8000-0000000000ff'),
  'customer'::public.user_role,
  'sign-up creates a customer profile'
);
select is(
  (select locale from public.profiles where id = 'a0000000-0000-4000-8000-0000000000ff'),
  'km',
  'sign-up keeps the chosen language'
);

select ok(
  not has_function_privilege('authenticated', 'public.prune_rider_locations()', 'execute'),
  'service-only functions are not callable by app users'
);

select * from finish();
rollback;
