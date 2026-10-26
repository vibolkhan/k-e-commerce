-- F04 · Carts, wishlists, orders, payments and refunds.
-- Money is integer US cents incl. 10% VAT. Orders, payments and refunds are
-- written only by Edge Functions (service role); clients read their own.

-- CHK-01: one cart per signed-in retail customer.
create table public.carts (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null unique references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.cart_items (
  id uuid primary key default gen_random_uuid(),
  cart_id uuid not null references public.carts (id) on delete cascade,
  variant_id uuid not null references public.product_variants (id) on delete cascade,
  qty integer not null check (qty between 1 and 999),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (cart_id, variant_id)
);

-- WSH-01.
create table public.wishlists (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles (id) on delete cascade,
  product_id uuid not null references public.products (id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (profile_id, product_id)
);

-- Order numbers as shown in the design: K-10265, K-10266, ...
create sequence public.order_number_seq start 10265;

create table public.orders (
  id uuid primary key default gen_random_uuid(),
  number text not null unique default ('K-' || nextval('public.order_number_seq')),
  profile_id uuid not null references public.profiles (id) on delete restrict,
  is_business boolean not null default false,
  status public.order_status not null default 'pending_payment',
  payment_method public.payment_method not null,
  payment_status public.payment_status not null default 'pending',
  subtotal_cents integer not null check (subtotal_cents >= 0),
  delivery_fee_cents integer not null default 0 check (delivery_fee_cents >= 0),
  tax_cents integer not null default 0 check (tax_cents >= 0),
  total_cents integer not null check (total_cents >= 0),
  -- Retail prices include VAT (tax_cents is the share inside the total).
  -- Quote-based B2B orders add VAT on top, as on the quote.
  prices_include_tax boolean not null default true,
  address jsonb not null,  -- snapshot at checkout
  zone_id uuid references public.delivery_zones (id) on delete set null,
  delivery_date date,
  delivery_slot text,
  note text,
  quote_id uuid,  -- FK added with quotes
  cancel_reason text,
  cancelled_by uuid references public.profiles (id) on delete set null,
  reserved_until timestamptz,  -- stock hold for unpaid KHQR
  placed_at timestamptz not null default now(),
  delivered_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (
    total_cents = subtotal_cents + delivery_fee_cents
      + case when prices_include_tax then 0 else tax_cents end
  )
);
create index orders_profile_idx on public.orders (profile_id, placed_at desc);
create index orders_status_idx on public.orders (status);

alter table public.stock_movements
  add constraint stock_movements_order_fk
  foreign key (order_id) references public.orders (id) on delete set null;

create table public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders (id) on delete cascade,
  variant_id uuid not null references public.product_variants (id) on delete restrict,
  product_id uuid not null references public.products (id) on delete restrict,
  name jsonb not null,  -- snapshot
  sku text not null,
  attributes jsonb not null default '{}',
  unit_price_cents integer not null check (unit_price_cents >= 0),
  qty integer not null check (qty >= 1),
  line_total_cents integer generated always as (unit_price_cents * qty) stored,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index order_items_order_idx on public.order_items (order_id);
create index order_items_product_idx on public.order_items (product_id);

-- One row per payment attempt (a KHQR retry is a new row).
create table public.payments (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders (id) on delete cascade,
  provider text not null,  -- khqr | cod | bank_transfer | (payway, next phase)
  method public.payment_method not null,
  status public.payment_status not null,
  amount_cents integer not null check (amount_cents >= 0),
  provider_ref text,
  raw_payload jsonb,
  slip_path text,  -- storage: bank-slips/<uid>/...
  rejection_reason text,
  expires_at timestamptz,
  confirmed_at timestamptz,
  confirmed_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index payments_order_idx on public.payments (order_id);
create unique index payments_provider_ref_idx on public.payments (provider, provider_ref)
  where provider_ref is not null;

-- PAY-06.
create table public.refunds (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders (id) on delete cascade,
  payment_id uuid references public.payments (id) on delete set null,
  return_id uuid,  -- FK added with returns
  amount_cents integer not null check (amount_cents > 0),
  method text not null,  -- khqr | cash | bank_transfer
  status public.refund_status not null default 'pending',
  reason text,
  created_by uuid references public.profiles (id) on delete set null,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index refunds_order_idx on public.refunds (order_id);
