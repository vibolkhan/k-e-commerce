-- F04 · Catalog, prices, stock and home content.
-- Translatable text is jsonb keyed by locale: {"en": "...", "km": "..."};
-- English is required, Khmer may be missing until translated.

create table public.categories (
  id uuid primary key default gen_random_uuid(),
  parent_id uuid references public.categories (id) on delete restrict,
  name jsonb not null check (jsonb_typeof(name) = 'object' and name ? 'en'),
  slug text not null unique,
  icon text,
  banner_path text,
  sort integer not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (parent_id is distinct from id)
);
create index categories_parent_idx on public.categories (parent_id);

create table public.products (
  id uuid primary key default gen_random_uuid(),
  category_id uuid not null references public.categories (id) on delete restrict,
  slug text not null unique,
  brand text,
  name jsonb not null check (jsonb_typeof(name) = 'object' and name ? 'en'),
  description jsonb not null default '{}' check (jsonb_typeof(description) = 'object'),
  specs jsonb not null default '{}',
  status public.product_status not null default 'draft',
  rfq_enabled boolean not null default false,  -- CAT-07 "B2B quote available"
  rfq_min_qty integer check (rfq_min_qty >= 1),
  max_per_order integer check (max_per_order >= 1),
  tags text[] not null default '{}',
  is_best_seller boolean not null default false,
  rating_avg numeric(2, 1) not null default 0,  -- kept by the reviews trigger
  rating_count integer not null default 0,
  sold_count integer not null default 0,
  search_tsv tsvector generated always as (
    to_tsvector(
      'simple',
      coalesce(name ->> 'en', '') || ' ' || coalesce(name ->> 'km', '') || ' ' || coalesce(brand, '')
    )
  ) stored,
  created_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (not rfq_enabled or rfq_min_qty is not null)
);
create index products_category_idx on public.products (category_id);
create index products_status_idx on public.products (status);
create index products_search_idx on public.products using gin (search_tsv);
-- CAT-03: typo-tolerant search in both languages.
create index products_name_en_trgm_idx on public.products
  using gin ((name ->> 'en') extensions.gin_trgm_ops);
create index products_name_km_trgm_idx on public.products
  using gin ((name ->> 'km') extensions.gin_trgm_ops);

create table public.product_variants (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products (id) on delete cascade,
  sku text not null unique,
  barcode text,
  attributes jsonb not null default '{}',  -- e.g. {"colour": "Black"}
  images text[] not null default '{}',     -- storage: product-images/...
  active boolean not null default true,
  sort integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index product_variants_product_idx on public.product_variants (product_id);

-- Retail price in US cents incl. VAT. One market (Cambodia), so one price per
-- variant. Business buyers can never read this table (RLS).
create table public.prices (
  id uuid primary key default gen_random_uuid(),
  variant_id uuid not null unique references public.product_variants (id) on delete cascade,
  currency text not null default 'USD' check (currency = 'USD'),
  amount_cents integer not null check (amount_cents > 0),
  compare_at_cents integer check (compare_at_cents > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.warehouses (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  address text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- CAT-05 / CHK-04. `reserved` is held for unpaid KHQR orders (15 minutes).
-- Only Edge Functions change these numbers.
create table public.stock (
  id uuid primary key default gen_random_uuid(),
  variant_id uuid not null references public.product_variants (id) on delete cascade,
  warehouse_id uuid not null references public.warehouses (id) on delete restrict,
  qty integer not null default 0 check (qty >= 0),
  reserved integer not null default 0,
  low_stock_at integer not null default 10 check (low_stock_at >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (variant_id, warehouse_id),
  constraint stock_reserved_within_qty check (reserved >= 0 and reserved <= qty)
);

-- ADM-03: every stock change with its reason (A-06a).
create table public.stock_movements (
  id uuid primary key default gen_random_uuid(),
  variant_id uuid not null references public.product_variants (id) on delete cascade,
  warehouse_id uuid not null references public.warehouses (id) on delete restrict,
  delta integer not null check (delta <> 0),
  reason public.stock_reason not null,
  note text,
  order_id uuid,  -- FK added with orders
  actor_id uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index stock_movements_variant_idx on public.stock_movements (variant_id, created_at desc);

-- What can still be ordered, per variant across warehouses.
create view public.variant_availability
with (security_invoker = true)
as
select
  v.id as variant_id,
  v.product_id,
  coalesce(sum(s.qty), 0)::integer as qty,
  coalesce(sum(s.reserved), 0)::integer as reserved,
  coalesce(sum(s.qty - s.reserved), 0)::integer as available,
  coalesce(sum(s.qty - s.reserved), 0) <= 0 as out_of_stock,
  coalesce(sum(s.qty - s.reserved), 0) > 0
    and coalesce(sum(s.qty - s.reserved), 0) <= coalesce(min(s.low_stock_at), 0) as low_stock
from public.product_variants v
left join public.stock s on s.variant_id = v.id
group by v.id, v.product_id;

-- CAT-06 / ADM-08: curated collections and home banners.
create table public.collections (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  title jsonb not null check (jsonb_typeof(title) = 'object' and title ? 'en'),
  audience public.banner_audience not null default 'all',
  sort integer not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.collection_items (
  id uuid primary key default gen_random_uuid(),
  collection_id uuid not null references public.collections (id) on delete cascade,
  product_id uuid not null references public.products (id) on delete cascade,
  sort integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (collection_id, product_id)
);

create table public.banners (
  id uuid primary key default gen_random_uuid(),
  title jsonb not null check (jsonb_typeof(title) = 'object' and title ? 'en'),
  subtitle jsonb not null default '{}',
  cta jsonb not null default '{}',
  badge jsonb not null default '{}',
  image_path text,
  link_type text check (link_type in ('collection', 'category', 'product', 'page', 'url')),
  link_target text,
  audience public.banner_audience not null default 'all',
  starts_at timestamptz,
  ends_at timestamptz,
  active boolean not null default true,
  sort integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at is null or starts_at is null or ends_at > starts_at)
);

-- Terms, privacy, FAQ and other static pages (ADM-08).
create table public.content_pages (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  title jsonb not null check (jsonb_typeof(title) = 'object' and title ? 'en'),
  body jsonb not null default '{}',
  published boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
