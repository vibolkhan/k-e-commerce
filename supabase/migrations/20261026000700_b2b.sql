-- F04 · Business quote requests (RFQ) and quotes.
-- An RFQ has one or more quote versions ("Quote v1", "v2" after a revision).
-- Accepting a quote creates an order at the quoted prices (Edge Function).

create sequence public.rfq_number_seq start 316;

create table public.rfqs (
  id uuid primary key default gen_random_uuid(),
  number text not null unique
    default ('RFQ-' || lpad(nextval('public.rfq_number_seq')::text, 4, '0')),
  profile_id uuid not null references public.profiles (id) on delete restrict,
  status public.rfq_status not null default 'submitted',
  required_date date,
  delivery_address jsonb,
  zone_id uuid references public.delivery_zones (id) on delete set null,
  notes text,
  attachments text[] not null default '{}',
  assigned_to uuid references public.profiles (id) on delete set null,
  submitted_at timestamptz not null default now(),
  cancelled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index rfqs_profile_idx on public.rfqs (profile_id, submitted_at desc);
create index rfqs_status_idx on public.rfqs (status);

create table public.rfq_items (
  id uuid primary key default gen_random_uuid(),
  rfq_id uuid not null references public.rfqs (id) on delete cascade,
  product_id uuid not null references public.products (id) on delete restrict,
  variant_id uuid references public.product_variants (id) on delete restrict,
  qty integer not null check (qty >= 1),
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index rfq_items_rfq_idx on public.rfq_items (rfq_id);

-- US-06: only quote-enabled products, at or above their minimum quantity.
create function public.rfq_item_check()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  p record;
begin
  select rfq_enabled, rfq_min_qty into p
    from public.products
   where id = new.product_id;
  if not coalesce(p.rfq_enabled, false) then
    raise exception 'Product is not available for quotes' using errcode = '23514';
  end if;
  if new.qty < coalesce(p.rfq_min_qty, 1) then
    raise exception 'Minimum quote quantity is %', p.rfq_min_qty using errcode = '23514';
  end if;
  if new.variant_id is not null and not exists (
    select 1 from public.product_variants v
     where v.id = new.variant_id and v.product_id = new.product_id
  ) then
    raise exception 'Variant does not belong to product' using errcode = '23514';
  end if;
  return new;
end;
$$;
create trigger rfq_item_check
  before insert or update on public.rfq_items
  for each row execute function public.rfq_item_check();

create table public.quotes (
  id uuid primary key default gen_random_uuid(),
  rfq_id uuid not null references public.rfqs (id) on delete cascade,
  version integer not null default 1 check (version >= 1),
  status public.quote_status not null default 'draft',
  valid_until date,
  terms text,
  subtotal_cents integer not null default 0 check (subtotal_cents >= 0),
  delivery_fee_cents integer not null default 0 check (delivery_fee_cents >= 0),
  tax_cents integer not null default 0 check (tax_cents >= 0),
  total_cents integer not null default 0 check (total_cents >= 0),
  prices_include_tax boolean not null default false,  -- quotes show VAT on top
  revision_note text,
  rejection_reason text,
  created_by uuid references public.profiles (id) on delete set null,
  sent_at timestamptz,
  responded_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (rfq_id, version),
  check (status = 'draft' or valid_until is not null),
  check (
    total_cents = subtotal_cents + delivery_fee_cents
      + case when prices_include_tax then 0 else tax_cents end
  )
);

create table public.quote_items (
  id uuid primary key default gen_random_uuid(),
  quote_id uuid not null references public.quotes (id) on delete cascade,
  product_id uuid not null references public.products (id) on delete restrict,
  variant_id uuid references public.product_variants (id) on delete restrict,
  name jsonb not null,
  sku text,
  qty integer not null check (qty >= 1),
  unit_price_cents integer not null check (unit_price_cents >= 0),
  line_total_cents integer generated always as (unit_price_cents * qty) stored,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index quote_items_quote_idx on public.quote_items (quote_id);

alter table public.orders
  add constraint orders_quote_fk
  foreign key (quote_id) references public.quotes (id) on delete restrict;
create unique index orders_one_per_quote_idx on public.orders (quote_id) where quote_id is not null;
