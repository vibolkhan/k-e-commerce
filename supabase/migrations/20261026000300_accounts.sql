-- F04 · Accounts, staff, business profiles, delivery zones and addresses.
-- Delivery zones live here because addresses resolve their zone on save.

-- 1:1 with auth.users. Created by handle_new_user() on sign-up.
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  role public.user_role not null default 'customer',
  full_name text,
  phone text,
  email text,
  avatar_url text,
  locale text not null default 'en' check (locale in ('en', 'km')),
  notification_prefs jsonb not null default '{}',
  is_blocked boolean not null default false,
  blocked_reason text,
  deletion_requested_at timestamptz,  -- AUTH-07
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index profiles_role_idx on public.profiles (role);

-- One staff role per staff user (A-14d). Invited staff stay `invited` until
-- they sign in.
create table public.staff_members (
  profile_id uuid primary key references public.profiles (id) on delete cascade,
  staff_role public.staff_role not null,
  status text not null default 'invited' check (status in ('active', 'invited')),
  invited_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- AUTH-05: a customer applies for a business account; sales verify it.
create table public.business_profiles (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null unique references public.profiles (id) on delete cascade,
  company_name text not null,
  vat_tin text not null,
  address text not null,
  contact_name text,
  contact_phone text,
  licence_path text,  -- storage: business-docs/<uid>/...
  verification_status public.verification_status not null default 'pending',
  rejection_reason text,
  verified_by uuid references public.profiles (id) on delete set null,
  verified_at timestamptz,
  submitted_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index business_profiles_status_idx on public.business_profiles (verification_status);

-- CHK-03 / PAY-03: fee, free-delivery threshold and COD limit per zone.
create table public.delivery_zones (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  area extensions.geography (multipolygon, 4326) not null,
  fee_cents integer not null check (fee_cents >= 0),
  free_threshold_cents integer check (free_threshold_cents >= 0),
  same_day boolean not null default true,
  cod_enabled boolean not null default true,
  cod_limit_cents integer check (cod_limit_cents >= 0),  -- null = app_settings.cod_limit_cents
  active boolean not null default true,
  sort integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index delivery_zones_area_idx on public.delivery_zones using gist (area);

-- The active zone a point falls in, or null ("We don't deliver here yet").
create function public.zone_for_point(lat double precision, lng double precision)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select z.id
    from public.delivery_zones z
   where z.active
     and extensions.st_covers(
           z.area,
           extensions.st_setsrid(extensions.st_makepoint(lng, lat), 4326)::extensions.geography
         )
   order by z.sort
   limit 1;
$$;

create table public.addresses (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles (id) on delete cascade,
  label text not null,
  recipient_name text,
  phone text,
  line text not null,
  city text not null default 'Phnom Penh',
  lat double precision check (lat between -90 and 90),
  lng double precision check (lng between -180 and 180),
  zone_id uuid references public.delivery_zones (id) on delete set null,
  note text,
  is_default boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index addresses_profile_idx on public.addresses (profile_id);
create unique index addresses_one_default_idx on public.addresses (profile_id) where is_default;

-- The zone always comes from the map pin, never from the client.
create function public.address_before_write()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.zone_id := case
    when new.lat is null or new.lng is null then null
    else public.zone_for_point(new.lat, new.lng)
  end;
  if new.is_default then
    update public.addresses
       set is_default = false
     where profile_id = new.profile_id
       and id <> new.id
       and is_default;
  end if;
  return new;
end;
$$;
create trigger address_before_write
  before insert or update on public.addresses
  for each row execute function public.address_before_write();

-- FCM tokens (NOT-01).
create table public.device_tokens (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles (id) on delete cascade,
  token text not null unique,
  platform text not null check (platform in ('ios', 'android', 'web')),
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index device_tokens_profile_idx on public.device_tokens (profile_id);

-- ---------------------------------------------------------------------------
-- Role helpers used by RLS policies. SECURITY DEFINER so they can read
-- profiles/staff_members without recursing into those tables' policies.
-- A blocked user has no role, so every role-based policy fails for them.
-- ---------------------------------------------------------------------------

create function public.auth_role()
returns public.user_role
language sql
stable
security definer
set search_path = ''
as $$
  select p.role
    from public.profiles p
   where p.id = auth.uid()
     and not p.is_blocked;
$$;

-- True for active staff holding one of `roles` (any role when empty).
-- super_admin always passes.
create function public.is_staff(variadic roles public.staff_role[] default '{}')
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
      from public.staff_members s
      join public.profiles p on p.id = s.profile_id
     where s.profile_id = auth.uid()
       and s.status = 'active'
       and p.role = 'staff'
       and not p.is_blocked
       and (
         s.staff_role = 'super_admin'
         or cardinality(roles) = 0
         or s.staff_role = any (roles)
       )
  );
$$;

create function public.is_business()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(public.auth_role() = 'business', false);
$$;

create function public.is_verified_business()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.is_business()
     and exists (
       select 1
         from public.business_profiles b
        where b.profile_id = auth.uid()
          and b.verification_status = 'approved'
     );
$$;

create function public.is_rider()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(public.auth_role() = 'rider', false);
$$;

-- ---------------------------------------------------------------------------
-- Sign-up: every new auth user gets a customer profile (App Flow F1).
-- ---------------------------------------------------------------------------
create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, email, phone, full_name, locale)
  values (
    new.id,
    new.email,
    new.phone,
    new.raw_user_meta_data ->> 'full_name',
    case
      when new.raw_user_meta_data ->> 'locale' in ('en', 'km')
        then new.raw_user_meta_data ->> 'locale'
      else 'en'
    end
  );
  return new;
end;
$$;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Approving a business profile makes the customer a business buyer;
-- rejecting or reopening it turns them back into a customer.
create function public.business_profile_sync_role()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.verification_status = 'approved' then
    update public.profiles set role = 'business'
     where id = new.profile_id and role = 'customer';
  else
    update public.profiles set role = 'customer'
     where id = new.profile_id and role = 'business';
  end if;
  return new;
end;
$$;
create trigger business_profile_sync_role
  after insert or update of verification_status on public.business_profiles
  for each row execute function public.business_profile_sync_role();

-- A rejected applicant who edits their details is sent back for review.
create function public.business_profile_resubmit()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if current_user in ('anon', 'authenticated')
     and not public.is_staff('sales')
     and old.verification_status = 'rejected' then
    new.verification_status := 'pending';
    new.rejection_reason := null;
    new.submitted_at := now();
  end if;
  return new;
end;
$$;
-- Named so it fires after the column guard (triggers run in name order).
create trigger resubmit_on_edit
  before update on public.business_profiles
  for each row execute function public.business_profile_resubmit();
