-- Staff by role (A-14d matrix).
begin;
select plan(26);

-- Catalog: products and prices, not orders.
select tests.login_as('visal@kstore.example');
select is(
  tests.rows($$ update public.prices set amount_cents = 4700
                where variant_id = (select id from public.product_variants where sku = 'HP-PRO-BLK') $$),
  1,
  'catalog staff can change a price'
);
select lives_ok(
  $$ insert into public.products (slug, category_id, name, status)
     select 'test-product', id, '{"en": "Test product"}', 'draft'
       from public.categories where slug = 'office' $$,
  'catalog staff can add a product'
);
select is(
  (select count(*)::int from public.products where slug = 'rice-cooker-1-8l'),
  1,
  'staff see draft products'
);
select is((select count(*)::int from public.orders), 0, 'catalog staff see no orders');
select is((select count(*)::int from public.rfqs), 0, 'catalog staff see no RFQs');
select is((select count(*)::int from public.audit_logs), 0, 'catalog staff cannot read the audit log');
select is(
  tests.rows($$ update public.app_settings set value = '5000' where key = 'khr_per_usd' $$),
  0,
  'catalog staff cannot change settings'
);
select is(
  tests.rows($$ update public.profiles set is_blocked = true where id = tests.uid('dara@kstore.example') $$),
  0,
  'catalog staff cannot block customers'
);

-- Sales: orders, RFQs and quotes, customers.
select tests.login_as('dalin@kstore.example');
select is((select count(*)::int from public.orders), 3, 'sales see all orders');
select is((select count(*)::int from public.rfqs), 2, 'sales see all RFQs');
select is((select count(*)::int from public.conversations), 1, 'sales see RFQ threads, not support chats');
select is((select count(*)::int from public.returns), 0, 'sales do not handle returns');
select is((select count(*)::int from public.audit_logs), 0, 'sales cannot read the audit log');
select throws_ok(
  $$ update public.orders set status = 'packing' $$,
  '42501', null, 'even staff change order status through the server'
);
select lives_ok(
  $$ insert into public.quotes (rfq_id, version, created_by)
     values ('b0000000-0000-4000-8000-000000000312', 2, auth.uid()) $$,
  'sales can draft a new quote version'
);
select throws_ok(
  $$ update public.quotes set status = 'sent', valid_until = current_date + 7
      where rfq_id = 'b0000000-0000-4000-8000-000000000312' and version = 2 $$,
  '42501', null, 'sending a quote goes through the server'
);
select is(
  tests.rows($$ update public.profiles set is_blocked = true where id = tests.uid('bopha@kstore.example') $$),
  1,
  'sales can block a customer'
);

-- Support: chats, returns, reviews.
select tests.login_as('sophea@kstore.example');
select is((select count(*)::int from public.conversations), 1, 'support see support chats, not RFQ threads');
select is((select count(*)::int from public.returns), 1, 'support see returns');
select is((select count(*)::int from public.rfqs), 0, 'support see no RFQs');
select is(
  tests.rows($$ update public.reviews set status = 'hidden', admin_reply = 'Thanks!' $$),
  1,
  'support moderate reviews'
);

-- Invited staff have no rights until active.
select tests.login_as('rachana@kstore.example');
select is((select count(*)::int from public.conversations), 0, 'invited staff see nothing yet');

-- Super admin: settings and the audit log.
select tests.login_as('chenda@kstore.example');
select is(
  tests.rows($$ update public.app_settings set value = '4150' where key = 'khr_per_usd' $$),
  1,
  'super admin can change the KHR rate'
);
select is(
  (select count(*)::int from public.audit_logs
    where entity = 'prices' and actor_id = tests.uid('visal@kstore.example')),
  1,
  'the price change is in the audit log with its author'
);
select is(
  (select diff -> 'value' from public.audit_logs where entity = 'app_settings' and entity_id = 'khr_per_usd'),
  '{"old": 4100, "new": 4150}'::jsonb,
  'settings changes are audited with old and new values'
);
select throws_ok(
  $$ update public.stock set qty = 0 $$,
  '42501', null, 'stock changes go through the server, even for super admins'
);

select * from finish();
rollback;
