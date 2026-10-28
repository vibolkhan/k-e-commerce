-- F09: catalog writes through the service-role functions, the audit trail,
-- product images and the back-office reads.
begin;
select plan(30);

-- Writes are for the Edge Functions only.
select tests.login_as('visal@kstore.example');
select throws_ok(
  $$ select public.catalog_save_product(tests.uid('visal@kstore.example'), '{}') $$,
  '42501', null, 'staff cannot call catalog_save_product directly'
);
select throws_ok(
  $$ select public.catalog_set_status(tests.uid('visal@kstore.example'), '{}', 'archived') $$,
  '42501', null, 'staff cannot call catalog_set_status directly'
);
select throws_ok(
  $$ select public.catalog_import(tests.uid('visal@kstore.example'), '[]'::jsonb) $$,
  '42501', null, 'staff cannot call catalog_import directly'
);

-- Create a product the way catalog-manage does.
select tests.as_owner();
select is(
  public.catalog_save_product(
    tests.uid('visal@kstore.example'),
    jsonb_build_object(
      'category_id', (select id from public.categories where slug = 'audio'),
      'slug', 'test-studio-monitor',
      'brand', 'Sonora',
      'name', '{"en": " Studio Monitor ", "km": ""}'::jsonb,
      'description', '{"en": "Near-field monitor."}'::jsonb,
      'highlights', '[{"en": "5 inch woofer"}]'::jsonb,
      'specs', '[{"name": "Power", "value": "50 W"}]'::jsonb,
      'tags', '["New"]'::jsonb,
      'options', '[{"name": {"en": "Colour"}, "values": ["Black", "White"]}]'::jsonb,
      'status', 'active',
      'rfq_enabled', true,
      'rfq_min_qty', 4,
      'variants', '[
        {"sku": "TST-MON-BLK", "attributes": {"Colour": "Black"}, "price_cents": 12900, "initial_qty": 8},
        {"sku": "TST-MON-WHT", "attributes": {"Colour": "White"}, "price_cents": 12900}
      ]'::jsonb,
      'images', '[
        {"path": "products/test/front.jpg", "alt": {"en": "Monitor, front"}, "variant_sku": "TST-MON-BLK"},
        {"path": "products/test/back.jpg", "alt": {"en": "Monitor, back"}}
      ]'::jsonb
    )
  ) ->> 'status',
  'saved',
  'a new product is saved'
);
select is(
  (select name from public.products where slug = 'test-studio-monitor'),
  '{"en": "Studio Monitor"}'::jsonb,
  'names are trimmed and an empty Khmer name is dropped'
);
select is(
  (select created_by from public.products where slug = 'test-studio-monitor'),
  tests.uid('visal@kstore.example'),
  'the product records who created it'
);
select is(
  (select qty from public.stock s join public.product_variants v on v.id = s.variant_id
    where v.sku = 'TST-MON-BLK'),
  8,
  'opening stock is written for a new variant'
);
select is(
  (select count(*)::int from public.stock_movements m join public.product_variants v on v.id = m.variant_id
    where v.sku = 'TST-MON-BLK' and m.reason = 'received' and m.actor_id = tests.uid('visal@kstore.example')),
  1,
  'opening stock has a received movement with its author'
);
select is(
  (select count(*)::int from public.stock s join public.product_variants v on v.id = s.variant_id
    where v.sku = 'TST-MON-WHT'),
  0,
  'no stock row when no opening stock is given'
);
select is(
  (select array_agg(path order by sort) from public.product_images i
     join public.products p on p.id = i.product_id where p.slug = 'test-studio-monitor'),
  array['products/test/front.jpg', 'products/test/back.jpg'],
  'images keep their order; the first is the main image'
);
select is(
  (select count(*)::int from public.audit_logs
    where entity = 'prices' and action = 'insert' and actor_id = tests.uid('visal@kstore.example')),
  2,
  'new prices are in the audit log with the staff member as actor'
);

-- Validation.
select is(
  public.catalog_save_product(
    tests.uid('visal@kstore.example'),
    jsonb_build_object(
      'category_id', (select id from public.categories where slug = 'audio'),
      'name', '{"en": "Copy"}'::jsonb,
      'variants', '[{"sku": "HP-PRO-BLK", "price_cents": 100}]'::jsonb
    )
  ),
  '{"status": "sku_taken", "sku": "HP-PRO-BLK"}'::jsonb,
  'a SKU already used by another product is refused'
);
select is(
  public.catalog_save_product(
    tests.uid('visal@kstore.example'),
    jsonb_build_object('category_id', (select id from public.categories where slug = 'audio'),
                       'name', '{"en": ""}'::jsonb, 'variants', '[{"sku": "X-1", "price_cents": 100}]'::jsonb)
  ) ->> 'field',
  'name',
  'an English name is required'
);
select is(
  public.catalog_save_product(
    tests.uid('visal@kstore.example'),
    jsonb_build_object('category_id', (select id from public.categories where slug = 'audio'),
                       'name', '{"en": "Quote item"}'::jsonb, 'rfq_enabled', true,
                       'variants', '[{"sku": "X-2", "price_cents": 100}]'::jsonb)
  ) ->> 'field',
  'rfq_min_qty',
  'a quote-enabled product needs a minimum quantity'
);
select throws_ok(
  $$ select public.catalog_save_product(
       tests.uid('visal@kstore.example'),
       jsonb_build_object('category_id', (select id from public.categories where slug = 'audio'),
                          'name', '{"en": "No alt"}'::jsonb,
                          'variants', '[{"sku": "X-3", "price_cents": 100}]'::jsonb,
                          'images', '[{"path": "products/x.jpg", "alt": {"en": " "}}]'::jsonb)) $$,
  '22023', 'image alt text required', 'every image needs alt text'
);

-- A price change: only the changed variant is logged, with old and new.
select is(
  public.catalog_save_product(
    tests.uid('chenda@kstore.example'),
    (select jsonb_build_object(
       'id', p.id, 'category_id', p.category_id, 'name', p.name, 'status', 'active',
       'rfq_enabled', true, 'rfq_min_qty', 4,
       'variants', (select jsonb_agg(jsonb_build_object(
                      'id', v.id, 'sku', v.sku, 'attributes', v.attributes,
                      'price_cents', case v.sku when 'TST-MON-BLK' then 11900 else 12900 end)
                      order by v.sort)
                      from public.product_variants v where v.product_id = p.id),
       'images', (select jsonb_agg(jsonb_build_object('id', i.id, 'path', i.path, 'alt', i.alt) order by i.sort desc)
                    from public.product_images i where i.product_id = p.id))
       from public.products p where p.slug = 'test-studio-monitor')
  ) ->> 'status',
  'saved',
  'an existing product is updated'
);
select is(
  (select diff -> 'amount_cents' from public.audit_logs
    where entity = 'prices' and action = 'update' and actor_id = tests.uid('chenda@kstore.example')),
  '{"old": 12900, "new": 11900}'::jsonb,
  'the price change is audited once, with old and new amounts and the actor'
);
select is(
  (select path from public.product_images i join public.products p on p.id = i.product_id
    where p.slug = 'test-studio-monitor' order by sort limit 1),
  'products/test/back.jpg',
  'reordering images changes the main image'
);

-- Catalog staff read the price history; sales cannot.
select tests.login_as('visal@kstore.example');
select is(
  (select new_cents from public.product_price_history(
     (select id from public.products where slug = 'test-studio-monitor')) where action = 'update'),
  11900,
  'catalog staff see the price history'
);
select is(
  (select actor_name from public.product_price_history(
     (select id from public.products where slug = 'test-studio-monitor')) where action = 'update'),
  'Chenda Lim',
  'the history names who changed the price'
);
select is(
  (select (public.catalog_admin_list('active', 'TST-MON') -> 'rows' -> 0 ->> 'min_price_cents')::int),
  11900,
  'the product list finds a product by SKU with its lowest price'
);
select is(
  (select public.catalog_admin_list('active', 'TST-MON') -> 'rows' -> 0 ->> 'main_image'),
  'products/test/back.jpg',
  'the product list shows the main image'
);
select tests.login_as('dalin@kstore.example');
select throws_ok(
  $$ select * from public.product_price_history((select id from public.products where slug = 'test-studio-monitor')) $$,
  '42501', null, 'sales cannot read the price history'
);

-- Customers see the live product with prices and images; business buyers no prices.
select tests.logout();
select is(
  (select count(*)::int from public.prices pr join public.product_variants v on v.id = pr.variant_id
    where v.sku like 'TST-MON-%'),
  2,
  'visitors see the new product''s prices'
);
select is(
  (select count(*)::int from public.product_images i join public.products p on p.id = i.product_id
    where p.slug = 'test-studio-monitor'),
  2,
  'visitors see its images'
);
select tests.login_as('sokha@kstore.example');
select is(
  (select count(*)::int from public.prices pr join public.product_variants v on v.id = pr.variant_id
    where v.sku like 'TST-MON-%'),
  0,
  'business buyers see no retail prices'
);

-- Archive hides it everywhere outside the back office.
select tests.as_owner();
select is(
  public.catalog_set_status(
    tests.uid('visal@kstore.example'),
    array[(select id from public.products where slug = 'test-studio-monitor')],
    'archived'
  ),
  1,
  'the product is archived'
);
select tests.logout();
select is(
  (select count(*)::int from public.products where slug = 'test-studio-monitor'),
  0,
  'visitors no longer see an archived product'
);
select is(
  (select count(*)::int from public.product_images i join public.products p on p.id = i.product_id
    where p.slug = 'test-studio-monitor'),
  0,
  'nor its images'
);

-- Images are written by catalog staff only.
select tests.login_as('dalin@kstore.example');
select throws_ok(
  $$ insert into public.product_images (product_id, path, alt)
     select id, 'products/x.jpg', '{"en": "x"}'::jsonb from public.products where slug = 'led-desk-lamp' $$,
  '42501', null, 'sales cannot add product images'
);

select * from finish();
rollback;
