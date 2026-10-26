-- F04 · Returns and reviews.

create sequence public.return_number_seq start 88;

-- ORD-05: within 3 days of delivery; $2.00 fee paid by the customer.
create table public.returns (
  id uuid primary key default gen_random_uuid(),
  number text not null unique
    default ('RET-' || lpad(nextval('public.return_number_seq')::text, 4, '0')),
  order_id uuid not null references public.orders (id) on delete restrict,
  profile_id uuid not null references public.profiles (id) on delete restrict,
  status public.return_status not null default 'requested',
  reason text not null,
  details text,
  photos text[] not null default '{}',
  fee_cents integer not null default 200 check (fee_cents >= 0),
  fee_method public.return_fee_method not null default 'from_refund',
  refund_cents integer check (refund_cents >= 0),
  rejection_reason text,
  decided_by uuid references public.profiles (id) on delete set null,
  decided_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index returns_order_idx on public.returns (order_id);
create index returns_status_idx on public.returns (status);

create table public.return_items (
  id uuid primary key default gen_random_uuid(),
  return_id uuid not null references public.returns (id) on delete cascade,
  order_item_id uuid not null references public.order_items (id) on delete restrict,
  qty integer not null check (qty >= 1),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (return_id, order_item_id)
);

alter table public.refunds
  add constraint refunds_return_fk
  foreign key (return_id) references public.returns (id) on delete set null;
alter table public.deliveries
  add constraint deliveries_return_fk
  foreign key (return_id) references public.returns (id) on delete cascade;

-- REV-01..03: one review per product per order, moderated before showing.
create table public.reviews (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products (id) on delete cascade,
  profile_id uuid not null references public.profiles (id) on delete cascade,
  order_id uuid not null references public.orders (id) on delete cascade,
  variant_label text,
  rating smallint not null check (rating between 1 and 5),
  body text,
  photos text[] not null default '{}',
  status public.review_status not null default 'pending',
  admin_reply text,
  replied_by uuid references public.profiles (id) on delete set null,
  replied_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (order_id, product_id)
);
create index reviews_product_idx on public.reviews (product_id, status);

-- REV-02: keep products.rating_avg / rating_count in step with published reviews.
create function public.refresh_product_rating()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  pid uuid := coalesce(new.product_id, old.product_id);
begin
  update public.products p
     set rating_avg = coalesce(r.avg_rating, 0),
         rating_count = r.n
    from (
      select round(avg(rating), 1) as avg_rating, count(*)::integer as n
        from public.reviews
       where product_id = pid and status = 'published'
    ) r
   where p.id = pid;
  return null;
end;
$$;
create trigger refresh_product_rating
  after insert or update or delete on public.reviews
  for each row execute function public.refresh_product_rating();
