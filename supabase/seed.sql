-- F04 · Local seed data, taken from the K UX/UI design screens.
-- Runs on `supabase db reset`. LOCAL ONLY: demo accounts share the password
-- `password123`. Money is US cents incl. VAT.
--
-- Fixed ids so tests and docs can refer to them:
--   a0…01 Chenda Lim   super_admin     a0…11 Vuthy Kim   rider
--   a0…02 Dalin Chhay  sales           a0…12 Sokun Ly    rider
--   a0…03 Sophea Mao   support         a0…21 Dara Sok    customer
--   a0…04 Visal Keo    catalog         a0…22 Bopha Lim   customer
--   a0…05 Rachana Ty   support, invited a0…23 Vannak Sum customer, blocked
--   a0…31 Sokha Chan   business (Mekong Desk Co., approved)
--   a0…32 Lina Sok     customer applying (Sovann Trading Co., pending)

-- ---------------------------------------------------------------------------
-- Auth users (handle_new_user creates their customer profiles)
-- ---------------------------------------------------------------------------
do $$
declare
  u record;
begin
  for u in
    select * from (values
      ('a0000000-0000-4000-8000-000000000001'::uuid, 'chenda@kstore.example', 'Chenda Lim',   '85512000001'),
      ('a0000000-0000-4000-8000-000000000002'::uuid, 'dalin@kstore.example',  'Dalin Chhay',  '85512000002'),
      ('a0000000-0000-4000-8000-000000000003'::uuid, 'sophea@kstore.example', 'Sophea Mao',   '85512000003'),
      ('a0000000-0000-4000-8000-000000000004'::uuid, 'visal@kstore.example',  'Visal Keo',    '85512000004'),
      ('a0000000-0000-4000-8000-000000000005'::uuid, 'rachana@kstore.example','Rachana Ty',   '85592115408'),
      ('a0000000-0000-4000-8000-000000000011'::uuid, 'vuthy@kstore.example',  'Vuthy Kim',    '85511482377'),
      ('a0000000-0000-4000-8000-000000000012'::uuid, 'sokun@kstore.example',  'Sokun Ly',     '85592315640'),
      ('a0000000-0000-4000-8000-000000000021'::uuid, 'dara@kstore.example',   'Dara Sok',     '85512345678'),
      ('a0000000-0000-4000-8000-000000000022'::uuid, 'bopha@kstore.example',  'Bopha Lim',    '85512345679'),
      ('a0000000-0000-4000-8000-000000000023'::uuid, 'vannak@kstore.example', 'Vannak Sum',   '85512345680'),
      ('a0000000-0000-4000-8000-000000000031'::uuid, 'sokha@kstore.example',  'Sokha Chan',   '85512345681'),
      ('a0000000-0000-4000-8000-000000000032'::uuid, 'lina@kstore.example',   'Lina Sok',     '85512345682')
    ) as t (id, email, full_name, phone)
  loop
    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
      phone, raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
      confirmation_token, recovery_token, email_change_token_new, email_change,
      email_change_token_current, phone_change, phone_change_token, reauthentication_token
    ) values (
      '00000000-0000-0000-0000-000000000000', u.id, 'authenticated', 'authenticated',
      u.email, extensions.crypt('password123', extensions.gen_salt('bf')), now(),
      u.phone, '{"provider": "email", "providers": ["email"]}',
      jsonb_build_object('full_name', u.full_name, 'locale', 'en'), now(), now(),
      '', '', '', '', '', '', '', ''
    );
    insert into auth.identities (
      id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at
    ) values (
      gen_random_uuid(), u.id, u.id::text,
      jsonb_build_object('sub', u.id::text, 'email', u.email, 'email_verified', true),
      'email', now(), now(), now()
    );
  end loop;
end;
$$;

-- Roles
update public.profiles set role = 'staff'
 where id in (
   'a0000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000002',
   'a0000000-0000-4000-8000-000000000003', 'a0000000-0000-4000-8000-000000000004',
   'a0000000-0000-4000-8000-000000000005'
 );
update public.profiles set role = 'rider'
 where id in ('a0000000-0000-4000-8000-000000000011', 'a0000000-0000-4000-8000-000000000012');
update public.profiles
   set is_blocked = true, blocked_reason = 'Repeated failed COD deliveries'
 where id = 'a0000000-0000-4000-8000-000000000023';

insert into public.staff_members (profile_id, staff_role, status, invited_by) values
  ('a0000000-0000-4000-8000-000000000001', 'super_admin', 'active', null),
  ('a0000000-0000-4000-8000-000000000002', 'sales', 'active', 'a0000000-0000-4000-8000-000000000001'),
  ('a0000000-0000-4000-8000-000000000003', 'support', 'active', 'a0000000-0000-4000-8000-000000000001'),
  ('a0000000-0000-4000-8000-000000000004', 'catalog', 'active', 'a0000000-0000-4000-8000-000000000001'),
  ('a0000000-0000-4000-8000-000000000005', 'support', 'invited', 'a0000000-0000-4000-8000-000000000001');
-- A-14d: Rachana's invite was sent on 21 Oct by phone and lasts 7 days.
update public.staff_members
   set invited_at = '2026-10-21 10:00+07', invite_expires_at = '2026-10-28 10:00+07'
 where profile_id = 'a0000000-0000-4000-8000-000000000005';

-- Business buyers (A-07 / A-07b). Approving makes Sokha a business buyer.
insert into public.business_profiles (
  profile_id, company_name, vat_tin, address, contact_name, contact_phone,
  verification_status, verified_by, verified_at
) values
  ('a0000000-0000-4000-8000-000000000031', 'Mekong Desk Co., Ltd.', 'K001-100234567',
   '#15 St. 214, Daun Penh, Phnom Penh', 'Sokha Chan', '+855 12 345 681',
   'approved', 'a0000000-0000-4000-8000-000000000002', '2026-10-01 10:00+07'),
  ('a0000000-0000-4000-8000-000000000032', 'Sovann Trading Co.', 'K002-200567891',
   '#42 St. 63, BKK1, Phnom Penh', 'Lina Sok', '+855 12 345 682',
   'pending', null, null);

-- ---------------------------------------------------------------------------
-- Settings (A-14, App Flow §7). `khr_per_usd` is the F03 contract.
-- ---------------------------------------------------------------------------
insert into public.app_settings (key, value, description) values
  ('khr_per_usd', '4100', 'Riel per US dollar for display (A-14b)'),
  ('vat_rate', '0.10', 'Cambodia VAT; retail prices include it'),
  ('timezone', '"Asia/Phnom_Penh"', 'Store time zone (UTC+7)'),
  ('same_day_cutoff', '"15:00"', 'Orders after this time deliver next day'),
  ('delivery_hours', '{"from": "09:00", "to": "20:00", "days": "mon-sun"}', 'Delivery window'),
  ('delivery_slots', '[{"id": "anytime", "from": "09:00", "to": "20:00"}, {"id": "12-15", "from": "12:00", "to": "15:00"}, {"id": "15-18", "from": "15:00", "to": "18:00"}, {"id": "18-20", "from": "18:00", "to": "20:00"}]', 'Checkout time slots (C-07b)'),
  ('holidays', '[{"date": "2026-11-09", "name": "Independence Day"}]', 'No deliveries on these days (A-14c)'),
  ('free_delivery_cents', '5000', 'Default free-delivery threshold'),
  ('cod_limit_cents', '20000', 'Default COD limit per order; zones may override'),
  ('stock_hold_minutes', '15', 'Stock held for unpaid KHQR orders'),
  ('khqr_expiry_minutes', '15', 'KHQR validity'),
  ('khqr_merchant_name', '"K Store"', 'Name shown in banking apps'),
  ('khqr_merchant_id', '""', 'Bakong merchant id (set per environment)'),
  ('return_window_days', '3', 'Days after delivery to request a return'),
  ('return_fee_cents', '200', 'Return fee paid by the customer'),
  ('bank_slip_days_after_quote', '3', 'Days after quote expiry to upload the bank slip'),
  ('bank_account', '{"bank_name": "", "account_name": "", "account_number": ""}', 'Bank transfer details for business buyers'),
  ('chat_reopen_days', '7', 'Resolved chats can be reopened for this many days'),
  ('otp', '{"expiry_seconds": 300, "max_attempts": 5, "resend_seconds": 60, "lockout_minutes": 15}', 'Sign-in code rules');

-- ---------------------------------------------------------------------------
-- Delivery zones (A-14 / A-14a). Polygons are rough boxes around each area.
-- ---------------------------------------------------------------------------
insert into public.delivery_zones (
  name, area, fee_cents, free_threshold_cents, same_day, cod_enabled, cod_limit_cents, active, sort
) values
  ('Boeung Kak', 'SRID=4326;MULTIPOLYGON(((104.900 11.565, 104.910 11.565, 104.910 11.590, 104.900 11.590, 104.900 11.565)))',
   150, 5000, true, true, null, true, 1),
  ('Toul Kork', 'SRID=4326;MULTIPOLYGON(((104.875 11.565, 104.900 11.565, 104.900 11.605, 104.875 11.605, 104.875 11.565)))',
   150, 5000, true, true, null, true, 2),
  ('Daun Penh', 'SRID=4326;MULTIPOLYGON(((104.910 11.555, 104.935 11.555, 104.935 11.590, 104.910 11.590, 104.910 11.555)))',
   150, 5000, true, true, null, true, 3),
  ('BKK1', 'SRID=4326;MULTIPOLYGON(((104.910 11.540, 104.935 11.540, 104.935 11.555, 104.910 11.555, 104.910 11.540)))',
   150, 5000, true, true, 30000, true, 4),
  ('Sen Sok', 'SRID=4326;MULTIPOLYGON(((104.860 11.605, 104.905 11.605, 104.905 11.650, 104.860 11.650, 104.860 11.605)))',
   150, 5000, true, true, null, true, 5),
  ('Chbar Ampov', 'SRID=4326;MULTIPOLYGON(((104.935 11.510, 104.975 11.510, 104.975 11.550, 104.935 11.550, 104.935 11.510)))',
   250, 6000, false, true, null, false, 6);

-- Riders (A-08)
insert into public.riders (profile_id, plate, on_duty) values
  ('a0000000-0000-4000-8000-000000000011', '2BK-4821', true),
  ('a0000000-0000-4000-8000-000000000012', '2AX-1190', true);
insert into public.rider_zones (rider_id, zone_id)
select r.rider_id::uuid, z.id
  from (values
    ('a0000000-0000-4000-8000-000000000011', 'Toul Kork'),
    ('a0000000-0000-4000-8000-000000000011', 'Sen Sok'),
    ('a0000000-0000-4000-8000-000000000011', 'Boeung Kak'),
    ('a0000000-0000-4000-8000-000000000012', 'Daun Penh'),
    ('a0000000-0000-4000-8000-000000000012', 'BKK1')
  ) as r (rider_id, zone_name)
  join public.delivery_zones z on z.name = r.zone_name;

-- Addresses (C-08). zone_id is filled from the pin.
insert into public.addresses (profile_id, label, recipient_name, phone, line, lat, lng, is_default) values
  ('a0000000-0000-4000-8000-000000000021', 'Home', 'Dara Sok', '+855 12 345 678',
   '#24, St. 315, Boeung Kak 1, Toul Kork', 11.585, 104.890, true),
  ('a0000000-0000-4000-8000-000000000021', 'Office', 'Dara Sok', '+855 12 345 678',
   '#88, Norodom Blvd, Daun Penh', 11.570, 104.925, false),
  ('a0000000-0000-4000-8000-000000000022', 'Home', 'Bopha Lim', '+855 12 345 679',
   '#7, St. 278, BKK1', 11.548, 104.925, true),
  ('a0000000-0000-4000-8000-000000000031', 'Office', 'Sokha Chan', '+855 12 345 681',
   '#15 St. 214, Daun Penh', 11.565, 104.920, true);

-- ---------------------------------------------------------------------------
-- Catalog (C-01, C-02, A-05, A-05b, A-06, W-02)
-- ---------------------------------------------------------------------------
insert into public.categories (slug, name, icon, sort) values
  ('electronics',   '{"en": "Electronics", "km": "គ្រឿងអេឡិចត្រូនិក"}', 'devices', 1),
  ('fashion',       '{"en": "Fashion", "km": "សម្លៀកបំពាក់"}', 'shirt', 2),
  ('bags',          '{"en": "Bags", "km": "កាបូប"}', 'bag', 3),
  ('home-living',   '{"en": "Home & living", "km": "ផ្ទះ និងការរស់នៅ"}', 'home', 4),
  ('kitchen',       '{"en": "Kitchen", "km": "ផ្ទះបាយ"}', 'kitchen', 5),
  ('sports',        '{"en": "Sports", "km": "កីឡា"}', 'sports', 6),
  ('office',        '{"en": "Office", "km": "ការិយាល័យ"}', 'office', 7),
  ('pantry',        '{"en": "Pantry", "km": "គ្រឿងទេស និងភេសជ្ជៈ"}', 'pantry', 8),
  ('furnishing',    '{"en": "Furnishing", "km": "គ្រឿងសង្ហារិម"}', 'sofa', 9);
insert into public.categories (parent_id, slug, name, icon, sort)
select c.id, s.slug, s.name::jsonb, s.icon, s.sort
  from (values
    ('phones',      '{"en": "Phones", "km": "ទូរស័ព្ទ"}', 'phone', 1),
    ('audio',       '{"en": "Audio", "km": "សំឡេង"}', 'headphones', 2),
    ('wearables',   '{"en": "Wearables", "km": "ឧបករណ៍ពាក់"}', 'watch', 3),
    ('computers',   '{"en": "Computers", "km": "កុំព្យូទ័រ"}', 'laptop', 4),
    ('cameras',     '{"en": "Cameras", "km": "កាមេរ៉ា"}', 'camera', 5),
    ('accessories', '{"en": "Accessories", "km": "គ្រឿងបន្លាស់"}', 'plug', 6)
  ) as s (slug, name, icon, sort)
  cross join public.categories c
 where c.slug = 'electronics';

insert into public.products (
  slug, category_id, brand, name, description, status, rfq_enabled, rfq_min_qty,
  max_per_order, tags, is_best_seller, specs, created_by
)
select p.slug, c.id, p.brand, jsonb_build_object('en', p.name), jsonb_build_object('en', p.description),
       p.status::public.product_status, p.rfq_enabled, p.rfq_min_qty, p.max_per_order,
       p.tags, p.best_seller, p.specs::jsonb, 'a0000000-0000-4000-8000-000000000004'
  from (values
    ('wireless-headphones-pro', 'audio', 'Sonora', 'Wireless Headphones Pro',
     'Over-ear headphones with active noise cancelling and 30-hour battery.',
     'active', true, 5, 5, array['Wireless', 'Noise cancelling', 'Best seller'], true,
     '{"model": "WH-PRO", "weight_g": 250, "warranty_months": 12}'),
    ('smart-watch-active-2', 'wearables', 'Nimbus', 'Smart Watch Active 2',
     'Fitness tracking, heart rate and 7-day battery.', 'active', false, null, 5, array['New'], false, '{}'),
    ('running-sneakers-air', 'fashion', 'K Basics', 'Running Sneakers Air',
     'Lightweight running shoes with breathable mesh.', 'active', false, null, 5, array[]::text[], true, '{}'),
    ('everyday-backpack-22l', 'bags', 'K Basics', 'Everyday Backpack 22L',
     'Water-resistant backpack with a padded laptop sleeve.', 'active', true, 10, null, array[]::text[], false, '{}'),
    ('ceramic-coffee-mug-set', 'kitchen', 'K Basics', 'Ceramic Coffee Mug Set (4 pcs)',
     'Four 350 ml stoneware mugs.', 'active', true, 10, null, array[]::text[], true, '{}'),
    ('led-desk-lamp', 'home-living', 'Nimbus', 'LED Desk Lamp',
     'Dimmable desk lamp with three colour temperatures.', 'active', true, 5, null, array[]::text[], false, '{}'),
    ('a4-copy-paper-80gsm', 'office', 'K Basics', 'A4 Copy Paper 80 gsm (500 sheets)',
     'Bright white multipurpose paper.', 'active', true, 20, null, array[]::text[], false, '{}'),
    ('bluetooth-speaker-mini', 'audio', 'Sonora', 'Bluetooth Speaker Mini',
     'Pocket speaker, 12-hour battery, splash-proof.', 'active', false, null, null, array['New'], false, '{}'),
    ('rice-cooker-1-8l', 'kitchen', 'Nimbus', 'Rice Cooker 1.8 L',
     'Non-stick inner pot with keep-warm.', 'draft', false, null, null, array['New'], false, '{}'),
    ('stainless-water-bottle-750', 'sports', 'K Basics', 'Stainless Water Bottle 750 ml',
     'Keeps drinks cold for 24 hours.', 'active', true, 20, null, array[]::text[], true, '{}'),
    ('cotton-crew-tshirt', 'fashion', 'K Basics', 'Cotton Crew T-Shirt',
     '100% cotton everyday tee.', 'active', false, null, null, array[]::text[], false, '{}'),
    ('clear-phone-case', 'accessories', 'K Basics', 'Clear Phone Case',
     'Slim shock-absorbing case.', 'active', false, null, null, array[]::text[], false, '{}'),
    ('studio-headphones-wired', 'audio', 'Sonora', 'Studio Headphones, wired',
     'Closed-back monitoring headphones.', 'active', false, null, null, array[]::text[], false, '{}'),
    ('party-speaker-light', 'audio', 'Aurel', 'Party Speaker with Light',
     'Big sound with LED light show.', 'active', false, null, null, array[]::text[], false, '{}'),
    ('kids-headphones', 'audio', 'Sonora', 'Kids Headphones, volume-safe',
     'Volume limited to 85 dB.', 'active', false, null, null, array[]::text[], false, '{}'),
    ('outdoor-speaker-waterproof', 'audio', 'Aurel', 'Outdoor Speaker, waterproof',
     'IP67 waterproof speaker.', 'active', false, null, null, array[]::text[], false, '{}'),
    ('sport-earbuds', 'audio', 'Nimbus', 'Sport Earbuds',
     'Secure-fit earbuds for workouts.', 'active', false, null, null, array[]::text[], false, '{}'),
    ('bookshelf-speakers-pair', 'audio', 'Aurel', 'Bookshelf Speakers (pair)',
     'Powered speakers with Bluetooth.', 'active', false, null, null, array[]::text[], false, '{}'),
    ('gaming-headset-mic', 'audio', 'Sonora', 'Gaming Headset with Mic',
     'Surround sound with a detachable mic.', 'active', false, null, null, array[]::text[], false, '{}'),
    ('smart-speaker-voice', 'audio', 'Nimbus', 'Smart Speaker, voice control',
     'Voice assistant speaker.', 'active', false, null, null, array[]::text[], false, '{}'),
    ('travel-earbuds-case', 'audio', 'K Basics', 'Travel Earbuds with Case',
     'Compact earbuds with a charging case.', 'active', false, null, null, array[]::text[], false, '{}'),
    ('soundbar-compact', 'audio', 'Aurel', 'Soundbar Compact',
     'Compact TV soundbar.', 'active', false, null, null, array[]::text[], false, '{}'),
    ('nimbus-sport-earbuds', 'audio', 'Nimbus', 'Nimbus Sport Earbuds',
     'Sweat-resistant earbuds with ear hooks.', 'active', false, null, null, array[]::text[], false, '{}'),
    ('headphone-travel-case', 'accessories', 'K Basics', 'Headphone Travel Case',
     'Hard case for over-ear headphones.', 'active', false, null, null, array[]::text[], false, '{}')
  ) as p (slug, category, brand, name, description, status, rfq_enabled, rfq_min_qty,
          max_per_order, tags, best_seller, specs)
  join public.categories c on c.slug = p.category;

-- Khmer names (C-04: search in Khmer). The clear phone case stays
-- untranslated on purpose: Khmer may be missing until it is translated.
update public.products p
   set name = p.name || jsonb_build_object('km', k.km)
  from (values
    ('wireless-headphones-pro', 'កាសឥតខ្សែ Pro'),
    ('smart-watch-active-2', 'នាឡិកាឆ្លាតវៃ Active 2'),
    ('running-sneakers-air', 'ស្បែកជើងរត់ Air'),
    ('everyday-backpack-22l', 'កាបូបស្ពាយប្រចាំថ្ងៃ 22L'),
    ('ceramic-coffee-mug-set', 'ឈុតពែងកាហ្វេសេរ៉ាមិច (៤ ពែង)'),
    ('led-desk-lamp', 'ចង្កៀងតុ LED'),
    ('a4-copy-paper-80gsm', 'ក្រដាស A4 80 gsm (៥០០ សន្លឹក)'),
    ('bluetooth-speaker-mini', 'ឧបករណ៍បំពងសំឡេងប៊្លូធូស Mini'),
    ('rice-cooker-1-8l', 'ឆ្នាំងដាំបាយ 1.8 លីត្រ'),
    ('stainless-water-bottle-750', 'ដបទឹកដែកអ៊ីណុក 750 ml'),
    ('cotton-crew-tshirt', 'អាវយឺតកប្បាស'),
    ('studio-headphones-wired', 'កាសស្ទូឌីយោ មានខ្សែ'),
    ('party-speaker-light', 'ឧបករណ៍បំពងសំឡេងពិធីជប់លៀង មានភ្លើង'),
    ('kids-headphones', 'កាសសម្រាប់កុមារ'),
    ('outdoor-speaker-waterproof', 'ឧបករណ៍បំពងសំឡេងក្រៅផ្ទះ ការពារទឹក'),
    ('sport-earbuds', 'កាសត្រចៀកកីឡា'),
    ('bookshelf-speakers-pair', 'ឧបករណ៍បំពងសំឡេងធ្នើសៀវភៅ (មួយគូ)'),
    ('gaming-headset-mic', 'កាសហ្គេម មានមីក្រូ'),
    ('smart-speaker-voice', 'ឧបករណ៍បំពងសំឡេងឆ្លាតវៃ'),
    ('travel-earbuds-case', 'កាសត្រចៀកធ្វើដំណើរ មានប្រអប់'),
    ('soundbar-compact', 'របារសំឡេងតូច'),
    ('nimbus-sport-earbuds', 'កាសត្រចៀកកីឡា Nimbus'),
    ('headphone-travel-case', 'ប្រអប់កាសធ្វើដំណើរ')
  ) as k (slug, km)
 where p.slug = k.slug;

-- Variants with price (cents) and stock (qty, reserved, low-stock alert).
create temporary table seed_variants (
  product_slug text, sku text, attributes jsonb, price_cents integer,
  qty integer, reserved integer, low_at integer, sort integer
) on commit drop;
insert into seed_variants values
  ('wireless-headphones-pro', 'HP-PRO-BLK', '{"colour": "Black"}', 4900, 12, 1, 15, 1),
  ('wireless-headphones-pro', 'HP-PRO-WHT', '{"colour": "White"}', 4900, 40, 0, 15, 2),
  ('wireless-headphones-pro', 'HP-PRO-SKY', '{"colour": "Sky"}', 4900, 0, 0, 10, 3),
  ('smart-watch-active-2', 'SW-ACT2-GRY', '{"colour": "Grey"}', 7900, 6, 2, 8, 1),
  ('smart-watch-active-2', 'SW-ACT2-BLK', '{"colour": "Black"}', 7900, 58, 0, 8, 2),
  ('running-sneakers-air', 'SNK-AIR-39', '{"size": "39"}', 5900, 15, 0, 5, 1),
  ('running-sneakers-air', 'SNK-AIR-40', '{"size": "40"}', 5900, 20, 0, 5, 2),
  ('running-sneakers-air', 'SNK-AIR-41', '{"size": "41"}', 5900, 18, 0, 5, 3),
  ('running-sneakers-air', 'SNK-AIR-42', '{"size": "42"}', 5900, 3, 0, 5, 4),
  ('running-sneakers-air', 'SNK-AIR-43', '{"size": "43"}', 5900, 20, 0, 5, 5),
  ('running-sneakers-air', 'SNK-AIR-44', '{"size": "44"}', 5900, 12, 0, 5, 6),
  ('everyday-backpack-22l', 'BAG-22L-BLK', '{"colour": "Black"}', 3500, 50, 0, 10, 1),
  ('everyday-backpack-22l', 'BAG-22L-OLV', '{"colour": "Olive"}', 3500, 40, 0, 10, 2),
  ('everyday-backpack-22l', 'BAG-22L-NVY', '{"colour": "Navy"}', 3500, 30, 0, 10, 3),
  ('ceramic-coffee-mug-set', 'MUG-4-SND', '{"colour": "Sand"}', 1800, 110, 0, 20, 1),
  ('ceramic-coffee-mug-set', 'MUG-4-WHT', '{"colour": "White"}', 1800, 100, 0, 20, 2),
  ('led-desk-lamp', 'LMP-LED-WHT', '{"colour": "White"}', 2400, 4, 1, 10, 1),
  ('a4-copy-paper-80gsm', 'PAP-A4-80-1', '{"pack": "1 ream"}', 520, 980, 0, 100, 1),
  ('a4-copy-paper-80gsm', 'PAP-A4-80-5', '{"pack": "Box of 5 reams"}', 2500, 500, 0, 50, 2),
  ('bluetooth-speaker-mini', 'SPK-MINI-BLK', '{"colour": "Black"}', 2900, 0, 0, 10, 1),
  ('bluetooth-speaker-mini', 'SPK-MINI-SKY', '{"colour": "Sky"}', 2900, 0, 0, 10, 2),
  ('rice-cooker-1-8l', 'RCK-18-WHT', '{"colour": "White"}', 4500, null, null, null, 1),
  ('stainless-water-bottle-750', 'BTL-750-SKY', '{"colour": "Sky"}', 1250, 9, 2, 12, 1),
  ('stainless-water-bottle-750', 'BTL-750-BLK', '{"colour": "Black"}', 1250, 331, 0, 12, 2),
  ('cotton-crew-tshirt', 'TSH-CRW-WHT-M', '{"colour": "White", "size": "M"}', 990, 60, 0, 10, 1),
  ('cotton-crew-tshirt', 'TSH-CRW-NVY-M', '{"colour": "Navy", "size": "M"}', 990, 60, 0, 10, 2),
  ('cotton-crew-tshirt', 'TSH-CRW-SKY-M', '{"colour": "Sky", "size": "M"}', 990, 60, 0, 10, 3),
  ('clear-phone-case', 'CASE-CLR-01', '{}', 800, 70, 0, 10, 1),
  ('studio-headphones-wired', 'AUD-STU-HP', '{}', 3900, 25, 0, 5, 1),
  ('party-speaker-light', 'AUD-PRT-SPK', '{}', 6900, 25, 0, 5, 1),
  ('kids-headphones', 'AUD-KID-HP', '{}', 1900, 25, 0, 5, 1),
  ('outdoor-speaker-waterproof', 'AUD-OUT-SPK', '{}', 4500, 25, 0, 5, 1),
  ('sport-earbuds', 'AUD-SPT-EB', '{}', 2500, 25, 0, 5, 1),
  ('bookshelf-speakers-pair', 'AUD-BKS-SPK', '{}', 7900, 25, 0, 5, 1),
  ('gaming-headset-mic', 'AUD-GAM-HS', '{}', 5500, 25, 0, 5, 1),
  ('smart-speaker-voice', 'AUD-SMT-SPK', '{}', 5900, 25, 0, 5, 1),
  ('travel-earbuds-case', 'AUD-TRV-EB', '{}', 3200, 25, 0, 5, 1),
  ('soundbar-compact', 'AUD-SND-BAR', '{}', 7500, 25, 0, 5, 1),
  ('nimbus-sport-earbuds', 'AUD-NIM-EB', '{}', 3500, 25, 0, 5, 1),
  ('headphone-travel-case', 'ACC-HP-CASE', '{}', 1200, 25, 0, 5, 1);

insert into public.product_variants (product_id, sku, attributes, sort)
select p.id, v.sku, v.attributes, v.sort
  from seed_variants v
  join public.products p on p.slug = v.product_slug;

insert into public.prices (variant_id, amount_cents)
select pv.id, v.price_cents
  from seed_variants v
  join public.product_variants pv on pv.sku = v.sku;

insert into public.warehouses (name, address)
values ('Phnom Penh store', 'Phnom Penh');

-- The rice cooker is a draft and not stocked yet.
insert into public.stock (variant_id, warehouse_id, qty, reserved, low_stock_at)
select pv.id, w.id, v.qty, v.reserved, v.low_at
  from seed_variants v
  join public.product_variants pv on pv.sku = v.sku
  cross join public.warehouses w
 where v.qty is not null;

insert into public.stock_movements (variant_id, warehouse_id, delta, reason, note, actor_id)
select pv.id, w.id, 50, 'received', 'DN-2210', 'a0000000-0000-4000-8000-000000000004'
  from public.product_variants pv cross join public.warehouses w
 where pv.sku = 'MUG-4-SND';

-- ---------------------------------------------------------------------------
-- Home content (A-12)
-- ---------------------------------------------------------------------------
insert into public.collections (slug, title, audience, sort) values
  ('best-sellers', '{"en": "Best sellers"}', 'all', 1),
  ('new-arrivals', '{"en": "New arrivals"}', 'all', 2),
  ('office-essentials', '{"en": "Office essentials"}', 'all', 3),
  ('rainy-season', '{"en": "Rainy season"}', 'all', 4),
  ('popular-for-offices', '{"en": "Popular for offices"}', 'business', 5);

insert into public.collection_items (collection_id, product_id, sort)
select c.id, p.id, i.sort
  from (values
    ('best-sellers', 'wireless-headphones-pro', 1),
    ('best-sellers', 'running-sneakers-air', 2),
    ('best-sellers', 'ceramic-coffee-mug-set', 3),
    ('best-sellers', 'stainless-water-bottle-750', 4),
    ('new-arrivals', 'smart-watch-active-2', 1),
    ('new-arrivals', 'bluetooth-speaker-mini', 2),
    ('office-essentials', 'a4-copy-paper-80gsm', 1),
    ('office-essentials', 'led-desk-lamp', 2),
    ('office-essentials', 'everyday-backpack-22l', 3),
    ('rainy-season', 'everyday-backpack-22l', 1),
    ('popular-for-offices', 'a4-copy-paper-80gsm', 1),
    ('popular-for-offices', 'ceramic-coffee-mug-set', 2),
    ('popular-for-offices', 'stainless-water-bottle-750', 3),
    ('popular-for-offices', 'led-desk-lamp', 4)
  ) as i (collection, product, sort)
  join public.collections c on c.slug = i.collection
  join public.products p on p.slug = i.product;

insert into public.banners (
  title, subtitle, cta, badge, image_path, link_type, link_target, audience, starts_at, ends_at, sort
) values
  ('{"en": "Order by 3 PM, get it today"}',
   '{"en": "Free delivery on orders over $50 in Phnom Penh."}',
   '{"en": "Shop now"}', '{"en": "Same-day delivery"}', 'banners/same-day-truck.png',
   'collection', 'best-sellers', 'all', null, null, 1),
  ('{"en": "Buying in bulk? Request a quote"}', '{}', '{"en": "Request a quote"}', '{}', null,
   'page', 'request-quote', 'business', null, null, 2),
  ('{"en": "Back to school"}', '{}', '{"en": "Shop now"}', '{}', null,
   'collection', 'office-essentials', 'all', '2026-11-01 00:00+07', '2026-11-16 00:00+07', 3),
  ('{"en": "Rainy season essentials"}', '{}', '{"en": "Shop now"}', '{}', null,
   'collection', 'rainy-season', 'all', '2026-09-01 00:00+07', '2026-10-16 00:00+07', 4);

insert into public.content_pages (slug, title, body, published) values
  ('terms', '{"en": "Terms of service"}', '{"en": ""}', true),
  ('privacy', '{"en": "Privacy policy"}', '{"en": ""}', true),
  ('faq', '{"en": "FAQ"}', '{"en": ""}', true),
  ('returns', '{"en": "Returns and refunds"}', '{"en": "Request a return within 3 days of delivery. A $2.00 return fee applies."}', true),
  ('delivery', '{"en": "Delivery"}', '{"en": "Order by 3:00 PM for same-day delivery in Phnom Penh. Deliveries 9 AM to 8 PM."}', true);

-- ---------------------------------------------------------------------------
-- Carts and wishlists
-- ---------------------------------------------------------------------------
insert into public.carts (id, profile_id) values
  ('c0000000-0000-4000-8000-000000000021', 'a0000000-0000-4000-8000-000000000021'),
  ('c0000000-0000-4000-8000-000000000022', 'a0000000-0000-4000-8000-000000000022');
insert into public.cart_items (cart_id, variant_id, qty)
select c.cart_id::uuid, pv.id, c.qty
  from (values
    ('c0000000-0000-4000-8000-000000000021', 'TSH-CRW-NVY-M', 2),
    ('c0000000-0000-4000-8000-000000000022', 'HP-PRO-WHT', 1)
  ) as c (cart_id, sku, qty)
  join public.product_variants pv on pv.sku = c.sku;

insert into public.wishlists (profile_id, product_id)
select 'a0000000-0000-4000-8000-000000000021', id from public.products
 where slug in ('smart-watch-active-2', 'running-sneakers-air');

-- ---------------------------------------------------------------------------
-- Orders (C-11, C-12, A-02)
--   K-10248  Dara  delivered, KHQR paid (free delivery; $8.36 VAT included)
--   K-10250  Dara  out for delivery, COD, rider Vuthy
--   K-10251  Bopha ready, KHQR paid, rider Sokun assigned
--   K-10252  Bopha confirmed, COD (stock held: 2 × SW-ACT2-GRY)
--   K-10253  Bopha packing, KHQR paid (stock held: HP-PRO-BLK, LMP-LED-WHT, 2 × BTL-750-SKY)
--   The held units are the `reserved` numbers in the stock seed (A-06, F10).
-- ---------------------------------------------------------------------------
insert into public.orders (
  id, number, profile_id, status, payment_method, payment_status,
  subtotal_cents, delivery_fee_cents, tax_cents, total_cents, address, zone_id,
  delivery_date, delivery_slot, placed_at, delivered_at
)
select o.id::uuid, o.number, o.profile_id::uuid, o.status::public.order_status,
       o.method::public.payment_method, o.pay_status::public.payment_status,
       o.subtotal, o.fee, o.tax, o.total, to_jsonb(a) - 'profile_id' - 'created_at' - 'updated_at',
       a.zone_id, o.delivery_date::date, o.slot, o.placed_at::timestamptz, o.delivered_at::timestamptz
  from (values
    ('d0000000-0000-4000-8000-000000010248', 'K-10248', 'a0000000-0000-4000-8000-000000000021',
     'delivered', 'khqr', 'paid', 9200, 0, 836, 9200, 'Home',
     '2026-10-22', 'anytime', '2026-10-22 10:12+07', '2026-10-22 16:40+07'),
    ('d0000000-0000-4000-8000-000000010250', 'K-10250', 'a0000000-0000-4000-8000-000000000021',
     'out_for_delivery', 'cod', 'unpaid_cod', 2400, 150, 232, 2550, 'Home',
     '2026-10-26', '15-18', '2026-10-26 09:05+07', null),
    ('d0000000-0000-4000-8000-000000010251', 'K-10251', 'a0000000-0000-4000-8000-000000000022',
     'ready', 'khqr', 'paid', 7900, 0, 718, 7900, 'Home',
     '2026-10-26', 'anytime', '2026-10-26 08:30+07', null),
    ('d0000000-0000-4000-8000-000000010252', 'K-10252', 'a0000000-0000-4000-8000-000000000022',
     'confirmed', 'cod', 'unpaid_cod', 15800, 150, 1450, 15950, 'Home',
     '2026-10-27', '15-18', '2026-10-27 09:40+07', null),
    ('d0000000-0000-4000-8000-000000010253', 'K-10253', 'a0000000-0000-4000-8000-000000000022',
     'packing', 'khqr', 'paid', 9800, 0, 891, 9800, 'Home',
     '2026-10-27', 'anytime', '2026-10-27 10:24+07', null)
  ) as o (id, number, profile_id, status, method, pay_status, subtotal, fee, tax, total,
          address_label, delivery_date, slot, placed_at, delivered_at)
  join public.addresses a on a.profile_id = o.profile_id::uuid and a.label = o.address_label;

insert into public.order_items (order_id, variant_id, product_id, name, sku, attributes, unit_price_cents, qty)
select i.order_id::uuid, pv.id, p.id, p.name, pv.sku, pv.attributes, i.unit_price, i.qty
  from (values
    ('d0000000-0000-4000-8000-000000010248', 'HP-PRO-BLK', 4900, 1),
    ('d0000000-0000-4000-8000-000000010248', 'MUG-4-SND', 1800, 1),
    ('d0000000-0000-4000-8000-000000010248', 'BTL-750-SKY', 1250, 2),
    ('d0000000-0000-4000-8000-000000010250', 'LMP-LED-WHT', 2400, 1),
    ('d0000000-0000-4000-8000-000000010251', 'SW-ACT2-GRY', 7900, 1),
    ('d0000000-0000-4000-8000-000000010252', 'SW-ACT2-GRY', 7900, 2),
    ('d0000000-0000-4000-8000-000000010253', 'HP-PRO-BLK', 4900, 1),
    ('d0000000-0000-4000-8000-000000010253', 'LMP-LED-WHT', 2400, 1),
    ('d0000000-0000-4000-8000-000000010253', 'BTL-750-SKY', 1250, 2)
  ) as i (order_id, sku, unit_price, qty)
  join public.product_variants pv on pv.sku = i.sku
  join public.products p on p.id = pv.product_id;

insert into public.payments (order_id, provider, method, status, amount_cents, provider_ref, confirmed_at) values
  ('d0000000-0000-4000-8000-000000010248', 'khqr', 'khqr', 'paid', 9200, 'KQ-7F3A92', '2026-10-22 10:14+07'),
  ('d0000000-0000-4000-8000-000000010250', 'cod', 'cod', 'unpaid_cod', 2550, null, null),
  ('d0000000-0000-4000-8000-000000010251', 'khqr', 'khqr', 'paid', 7900, 'KQ-8B21C4', '2026-10-26 08:32+07'),
  ('d0000000-0000-4000-8000-000000010252', 'cod', 'cod', 'unpaid_cod', 15950, null, null),
  ('d0000000-0000-4000-8000-000000010253', 'khqr', 'khqr', 'paid', 9800, 'KQ-9C40D7', '2026-10-27 10:25+07');

-- Stock held for the two orders not yet out of the door (F10). The stock seed
-- already counts these units in `reserved`.
insert into public.stock_reservations (order_id, variant_id, warehouse_id, qty)
select i.order_id, i.variant_id, w.id, i.qty
  from public.order_items i
  cross join public.warehouses w
 where i.order_id in ('d0000000-0000-4000-8000-000000010252', 'd0000000-0000-4000-8000-000000010253');

insert into public.stock_movements (variant_id, warehouse_id, delta, reason, order_id, created_at)
select r.variant_id, r.warehouse_id, -r.qty, 'reserved', r.order_id, o.placed_at
  from public.stock_reservations r
  join public.orders o on o.id = r.order_id;

insert into public.deliveries (
  id, order_id, rider_id, status, assigned_at, picked_up_at, delivered_at,
  pod_photo_path, recipient_name, cod_due_cents
) values
  ('e0000000-0000-4000-8000-000000010248', 'd0000000-0000-4000-8000-000000010248',
   'a0000000-0000-4000-8000-000000000011', 'delivered', '2026-10-22 13:00+07', '2026-10-22 15:10+07',
   '2026-10-22 16:40+07', 'a0000000-0000-4000-8000-000000000011/K-10248.jpg', 'Dara Sok', 0),
  ('e0000000-0000-4000-8000-000000010250', 'd0000000-0000-4000-8000-000000010250',
   'a0000000-0000-4000-8000-000000000011', 'picked_up', '2026-10-26 11:00+07', '2026-10-26 14:20+07',
   null, null, null, 2550),
  ('e0000000-0000-4000-8000-000000010251', 'd0000000-0000-4000-8000-000000010251',
   'a0000000-0000-4000-8000-000000000012', 'assigned', '2026-10-26 10:00+07', null,
   null, null, null, 0);

insert into public.rider_locations (delivery_id, rider_id, lat, lng, recorded_at) values
  ('e0000000-0000-4000-8000-000000010250', 'a0000000-0000-4000-8000-000000000011', 11.5801, 104.8955, now());

-- ---------------------------------------------------------------------------
-- Reviews (C-05b, A-10) and a return (A-09, RET-0087)
-- ---------------------------------------------------------------------------
insert into public.reviews (product_id, profile_id, order_id, variant_label, rating, body, status)
select p.id, 'a0000000-0000-4000-8000-000000000021', 'd0000000-0000-4000-8000-000000010248',
       'Black', 5, 'Great sound and the noise cancelling works on the bus.', 'published'
  from public.products p where p.slug = 'wireless-headphones-pro';

insert into public.returns (id, number, order_id, profile_id, status, reason, details, fee_cents, fee_method)
values ('f0000000-0000-4000-8000-000000000087', 'RET-0087', 'd0000000-0000-4000-8000-000000010248',
        'a0000000-0000-4000-8000-000000000021', 'requested', 'Arrived damaged',
        'One bottle has a dent on the side.', 200, 'from_refund');
insert into public.return_items (return_id, order_item_id, qty)
select 'f0000000-0000-4000-8000-000000000087', i.id, 1
  from public.order_items i
 where i.order_id = 'd0000000-0000-4000-8000-000000010248' and i.sku = 'BTL-750-SKY';

-- ---------------------------------------------------------------------------
-- RFQs and quotes (A-04, B-04, B-05)
--   RFQ-0312  Mekong Desk, quoted (v1 sent, VAT on top: $2,260.50)
--   RFQ-0298  Mekong Desk, expired
-- ---------------------------------------------------------------------------
insert into public.rfqs (id, number, profile_id, status, required_date, delivery_address, notes, assigned_to, submitted_at)
values
  ('b0000000-0000-4000-8000-000000000312', 'RFQ-0312', 'a0000000-0000-4000-8000-000000000031',
   'quoted', '2026-10-30', '{"line": "#15 St. 214, Daun Penh", "city": "Phnom Penh"}',
   'Monthly office restock.', 'a0000000-0000-4000-8000-000000000002', '2026-10-24 09:30+07'),
  ('b0000000-0000-4000-8000-000000000298', 'RFQ-0298', 'a0000000-0000-4000-8000-000000000031',
   'expired', '2026-10-15', '{"line": "#15 St. 214, Daun Penh", "city": "Phnom Penh"}',
   'Staff welcome kits.', 'a0000000-0000-4000-8000-000000000002', '2026-10-05 14:00+07');

insert into public.rfq_items (rfq_id, product_id, variant_id, qty)
select r.rfq_id::uuid, pv.product_id, pv.id, r.qty
  from (values
    ('b0000000-0000-4000-8000-000000000312', 'PAP-A4-80-1', 200),
    ('b0000000-0000-4000-8000-000000000312', 'MUG-4-SND', 40),
    ('b0000000-0000-4000-8000-000000000312', 'LMP-LED-WHT', 25),
    ('b0000000-0000-4000-8000-000000000298', 'BAG-22L-BLK', 30),
    ('b0000000-0000-4000-8000-000000000298', 'BTL-750-BLK', 50)
  ) as r (rfq_id, sku, qty)
  join public.product_variants pv on pv.sku = r.sku;

insert into public.quotes (
  id, rfq_id, version, status, valid_until, terms, subtotal_cents, delivery_fee_cents,
  tax_cents, total_cents, created_by, sent_at
) values
  ('b1000000-0000-4000-8000-000000000312', 'b0000000-0000-4000-8000-000000000312', 1, 'sent',
   '2026-11-05', 'Pay by KHQR, COD or bank transfer. Delivery within 2 days of acceptance.',
   204000, 1500, 20550, 226050, 'a0000000-0000-4000-8000-000000000002', '2026-10-25 11:00+07'),
  ('b1000000-0000-4000-8000-000000000298', 'b0000000-0000-4000-8000-000000000298', 1, 'expired',
   '2026-10-12', 'Pay by bank transfer.',
   147000, 0, 14700, 161700, 'a0000000-0000-4000-8000-000000000002', '2026-10-06 10:00+07');

insert into public.quote_items (quote_id, product_id, variant_id, name, sku, qty, unit_price_cents)
select q.quote_id::uuid, p.id, pv.id, p.name, pv.sku, q.qty, q.unit_price
  from (values
    ('b1000000-0000-4000-8000-000000000312', 'PAP-A4-80-1', 200, 460),
    ('b1000000-0000-4000-8000-000000000312', 'MUG-4-SND', 40, 1550),
    ('b1000000-0000-4000-8000-000000000312', 'LMP-LED-WHT', 25, 2000),
    ('b1000000-0000-4000-8000-000000000298', 'BAG-22L-BLK', 30, 3100),
    ('b1000000-0000-4000-8000-000000000298', 'BTL-750-BLK', 50, 1080)
  ) as q (quote_id, sku, qty, unit_price)
  join public.product_variants pv on pv.sku = q.sku
  join public.products p on p.id = pv.product_id;

-- ---------------------------------------------------------------------------
-- Chat (C-17a, A-11) and notifications
-- ---------------------------------------------------------------------------
insert into public.conversations (id, kind, customer_id, order_id, rfq_id, assigned_agent_id, status, subject) values
  ('91000000-0000-4000-8000-000000000001', 'support', 'a0000000-0000-4000-8000-000000000021',
   'd0000000-0000-4000-8000-000000010250', null, 'a0000000-0000-4000-8000-000000000003',
   'assigned', 'Delivery time for K-10250'),
  ('91000000-0000-4000-8000-000000000002', 'rfq', 'a0000000-0000-4000-8000-000000000031',
   null, 'b0000000-0000-4000-8000-000000000312', 'a0000000-0000-4000-8000-000000000002',
   'open', 'RFQ-0312');

insert into public.messages (conversation_id, sender_id, body, created_at) values
  ('91000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000021',
   'Hi, can the rider come after 5 PM?', '2026-10-26 13:02+07'),
  ('91000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000003',
   'Sure, I''ve asked Vuthy to arrive after 5 PM.', '2026-10-26 13:05+07'),
  ('91000000-0000-4000-8000-000000000002', 'a0000000-0000-4000-8000-000000000002',
   'Your quote is ready. The mug price includes a 14% bulk discount.', '2026-10-25 11:00+07');

-- Inbox (S-07): Dara's rows match the design, newest first; three unread.
-- Copy is stored in both languages, as notify() writes it.
insert into public.notifications (profile_id, type, category, title, body, payload, read_at, created_at) values
  ('a0000000-0000-4000-8000-000000000021', 'chat_message', 'chat',
   '{"en": "K Support replied", "km": "K Support បានឆ្លើយតប"}',
   '{"en": "Sophea: I''ve asked Vuthy to arrive after 5 PM.", "km": "Sophea: I''ve asked Vuthy to arrive after 5 PM."}',
   '{"route": "/customer/chat/91000000-0000-4000-8000-000000000001", "conversation_id": "91000000-0000-4000-8000-000000000001"}',
   null, now() - interval '8 minutes'),
  ('a0000000-0000-4000-8000-000000000021', 'order_out_for_delivery', 'orders',
   '{"en": "Your order is on the way", "km": "ការបញ្ជាទិញរបស់អ្នកកំពុងដឹកមក"}',
   '{"en": "Vuthy is delivering #K-10250. Arriving in about 18 min.", "km": "Vuthy កំពុងដឹក #K-10250។ នឹងមកដល់ក្នុងរយៈពេលប្រហែល 18 នាទី។"}',
   '{"route": "/customer/orders/d0000000-0000-4000-8000-000000010250", "order_id": "d0000000-0000-4000-8000-000000010250"}',
   null, now() - interval '16 minutes'),
  ('a0000000-0000-4000-8000-000000000021', 'payment_received', 'orders',
   '{"en": "Payment received", "km": "បានទទួលការទូទាត់"}',
   '{"en": "We got $92.00 by KHQR for #K-10248. Your order is confirmed.", "km": "យើងបានទទួល $92.00 តាម KHQR សម្រាប់ #K-10248។ ការបញ្ជាទិញរបស់អ្នកត្រូវបានបញ្ជាក់។"}',
   '{"route": "/customer/orders/d0000000-0000-4000-8000-000000010248", "order_id": "d0000000-0000-4000-8000-000000010248"}',
   null, now() - interval '3 hours'),
  ('a0000000-0000-4000-8000-000000000021', 'review_reminder', 'orders',
   '{"en": "How were your headphones?", "km": "តើកាសរបស់អ្នកយ៉ាងម៉េចដែរ?"}',
   '{"en": "Rate Wireless Headphones Pro from #K-10248 and help other shoppers.", "km": "វាយតម្លៃ Wireless Headphones Pro ពី #K-10248 ដើម្បីជួយអ្នកទិញផ្សេងទៀត។"}',
   '{"route": "/customer/orders/d0000000-0000-4000-8000-000000010248", "order_id": "d0000000-0000-4000-8000-000000010248"}',
   now() - interval '1 day', now() - interval '1 day 2 hours'),
  ('a0000000-0000-4000-8000-000000000021', 'order_delivered', 'orders',
   '{"en": "Delivered", "km": "បានដឹកជូនរួចរាល់"}',
   '{"en": "#K-10248 was delivered at 4:40 PM. Returns are open for 3 days.", "km": "#K-10248 ត្រូវបានដឹកជូននៅម៉ោង 4:40 PM។ អាចប្តូរ/ត្រឡប់ទំនិញបានក្នុងរយៈពេល 3 ថ្ងៃ។"}',
   '{"route": "/customer/orders/d0000000-0000-4000-8000-000000010248", "order_id": "d0000000-0000-4000-8000-000000010248"}',
   now() - interval '3 days', now() - interval '4 days'),
  ('a0000000-0000-4000-8000-000000000031', 'quote_ready', 'quotes',
   '{"en": "Your quote is ready", "km": "សម្រង់តម្លៃរបស់អ្នករួចរាល់ហើយ"}',
   '{"en": "RFQ-0312 · $2,260.50 · valid until 5 Nov. Review and accept.", "km": "RFQ-0312 · $2,260.50 · មានសុពលភាពដល់ 5 វិច្ឆិកា។ ពិនិត្យ និងទទួលយក។"}',
   '{"route": "/business/quotes/b0000000-0000-4000-8000-000000000312", "rfq_id": "b0000000-0000-4000-8000-000000000312"}',
   null, now() - interval '2 hours');

-- Display ratings and sales counts from the design (A-05, C-05b). The reviews
-- trigger keeps them in step from here on.
update public.products p
   set rating_avg = r.avg, rating_count = r.n, sold_count = r.sold
  from (values
    ('wireless-headphones-pro', 4.6, 128, 840),
    ('smart-watch-active-2', 4.4, 86, 310),
    ('running-sneakers-air', 4.7, 204, 920),
    ('everyday-backpack-22l', 4.5, 61, 280),
    ('ceramic-coffee-mug-set', 4.8, 152, 610),
    ('led-desk-lamp', 4.3, 40, 150),
    ('bluetooth-speaker-mini', 4.5, 77, 260),
    ('stainless-water-bottle-750', 4.6, 310, 1250),
    ('clear-phone-case', 4.3, 52, 300),
    ('studio-headphones-wired', 4.4, 52, 120),
    ('party-speaker-light', 4.6, 31, 80),
    ('kids-headphones', 4.5, 44, 140),
    ('outdoor-speaker-waterproof', 4.7, 90, 200),
    ('sport-earbuds', 4.3, 118, 380),
    ('bookshelf-speakers-pair', 4.8, 23, 40),
    ('gaming-headset-mic', 4.4, 66, 150),
    ('smart-speaker-voice', 4.2, 37, 90),
    ('travel-earbuds-case', 4.5, 140, 420),
    ('soundbar-compact', 4.4, 19, 35),
    ('nimbus-sport-earbuds', 4.4, 59, 170),
    ('headphone-travel-case', 4.5, 18, 60)
  ) as r (slug, avg, n, sold)
 where p.slug = r.slug;

-- Seeding is not an admin action: start the audit log empty.
truncate public.audit_logs;
