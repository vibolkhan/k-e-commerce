-- F04 · Riders, deliveries and live rider locations.

create table public.riders (
  profile_id uuid primary key references public.profiles (id) on delete cascade,
  plate text,
  on_duty boolean not null default false,  -- RID-01
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.rider_zones (
  id uuid primary key default gen_random_uuid(),
  rider_id uuid not null references public.riders (profile_id) on delete cascade,
  zone_id uuid not null references public.delivery_zones (id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (rider_id, zone_id)
);

-- One delivery job per order, plus return pickups (R-02d).
create table public.deliveries (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders (id) on delete cascade,
  kind text not null default 'order' check (kind in ('order', 'return_pickup')),
  return_id uuid,  -- FK added with returns
  rider_id uuid references public.riders (profile_id) on delete set null,
  status public.delivery_status not null default 'unassigned',
  assigned_at timestamptz,
  picked_up_at timestamptz,
  delivered_at timestamptz,
  pod_photo_path text,  -- storage: pod-photos/<rider uid>/...
  recipient_name text,
  cod_due_cents integer not null default 0 check (cod_due_cents >= 0),
  cod_collected_cents integer check (cod_collected_cents >= 0),
  failed_reason text,
  failed_note text,
  handed_over_at timestamptz,  -- COD cash handed to the store (A-08b)
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((status = 'unassigned') = (rider_id is null)),
  -- US-12: a photo is required to mark delivered.
  check (status <> 'delivered' or pod_photo_path is not null),
  check (status <> 'failed' or failed_reason is not null),
  check ((kind = 'return_pickup') = (return_id is not null))
);
create unique index deliveries_one_per_order_idx on public.deliveries (order_id) where kind = 'order';
create index deliveries_rider_idx on public.deliveries (rider_id, status);

-- RID-05: high volume; written every ~15 s while out for delivery and pruned
-- once the delivery is finished.
create table public.rider_locations (
  id bigint generated always as identity primary key,
  delivery_id uuid not null references public.deliveries (id) on delete cascade,
  rider_id uuid not null references public.riders (profile_id) on delete cascade,
  lat double precision not null check (lat between -90 and 90),
  lng double precision not null check (lng between -180 and 180),
  heading real,
  recorded_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);
create index rider_locations_delivery_idx on public.rider_locations (delivery_id, recorded_at desc);

-- Removes locations of deliveries that finished more than a day ago.
-- Called from a scheduled Edge Function / pg_cron (service role only).
create function public.prune_rider_locations()
returns integer
language sql
security definer
set search_path = ''
as $$
  with gone as (
    delete from public.rider_locations l
     using public.deliveries d
     where d.id = l.delivery_id
       and d.status in ('delivered', 'failed')
       and d.updated_at < now() - interval '1 day'
    returning 1
  )
  select count(*)::integer from gone;
$$;
