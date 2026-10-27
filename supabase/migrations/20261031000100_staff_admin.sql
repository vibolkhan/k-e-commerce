-- F08 · Admin back-office shell & staff roles (ADM-09, AUTH-06).
--
-- * Staff invites expire after 7 days; an invited member becomes active on
--   their first sign-in. Removed staff keep their row (audit) but no rights.
-- * staff_members is written only by the staff-manage Edge Function (service
--   role). A trigger keeps at least one active super admin.
-- * staff_directory() feeds A-14d; admin_badge_counts() feeds the sidebar and
--   runs as the caller, so RLS scopes every count.
-- * F04 reads that went wider than the A-14d matrix are tightened.

-- ---------------------------------------------------------------------------
-- staff_members: invite lifecycle
-- ---------------------------------------------------------------------------

alter table public.staff_members
  add column invited_at timestamptz,
  add column invite_expires_at timestamptz;

alter table public.staff_members drop constraint staff_members_status_check;
alter table public.staff_members
  add constraint staff_members_status_check check (status in ('active', 'invited', 'removed'));

-- Only the Edge Function changes staff: drop the direct super admin path.
drop policy "staff_members: super admin manages" on public.staff_members;
revoke insert, update, delete on public.staff_members from anon, authenticated;

-- An invite that hasn't expired turns active on the first sign-in.
create function private.activate_staff_invite()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.staff_members
     set status = 'active'
   where profile_id = new.id
     and status = 'invited'
     and (invite_expires_at is null or invite_expires_at > now());
  return new;
end;
$$;
revoke execute on function private.activate_staff_invite() from public, anon, authenticated;

create trigger on_auth_user_signed_in
  after update of last_sign_in_at on auth.users
  for each row
  when (new.last_sign_in_at is distinct from old.last_sign_in_at)
  execute function private.activate_staff_invite();

-- There is always an active super admin to manage staff and settings.
create function private.keep_a_super_admin()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.staff_role = 'super_admin' and old.status = 'active'
     and not exists (
       select 1 from public.staff_members
        where staff_role = 'super_admin' and status = 'active'
     ) then
    raise exception 'at least one active super admin is required'
      using errcode = 'P0001', hint = 'last_super_admin';
  end if;
  return null;
end;
$$;
revoke execute on function private.keep_a_super_admin() from public, anon, authenticated;

create trigger keep_a_super_admin
  after update or delete on public.staff_members
  for each row execute function private.keep_a_super_admin();

-- ---------------------------------------------------------------------------
-- A-14d staff list (super admin only)
-- ---------------------------------------------------------------------------

create function public.staff_directory()
returns table (
  profile_id uuid,
  full_name text,
  email text,
  phone text,
  staff_role public.staff_role,
  status text,
  last_sign_in_at timestamptz,
  invited_at timestamptz,
  invite_expires_at timestamptz,
  is_me boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.is_staff('super_admin') then
    raise exception 'only a super admin can list staff' using errcode = '42501';
  end if;
  return query
    select s.profile_id,
           p.full_name,
           coalesce(u.email, p.email)::text,
           coalesce(p.phone, nullif(u.phone, ''))::text,
           s.staff_role,
           s.status,
           u.last_sign_in_at,
           s.invited_at,
           s.invite_expires_at,
           s.profile_id = auth.uid()
      from public.staff_members s
      join public.profiles p on p.id = s.profile_id
      left join auth.users u on u.id = s.profile_id
     where s.status <> 'removed'
     order by (s.staff_role = 'super_admin') desc, s.status, p.full_name;
end;
$$;
revoke execute on function public.staff_directory() from public, anon;
grant execute on function public.staff_directory() to authenticated;

-- ---------------------------------------------------------------------------
-- Sidebar badges (as the caller: RLS decides what each role can count)
-- ---------------------------------------------------------------------------

create function public.admin_badge_counts()
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select case when public.is_staff() then jsonb_build_object(
    'orders', (select count(*) from public.orders
                where status in ('confirmed', 'awaiting_bank_transfer')),
    'rfqs', (select count(*) from public.rfqs
              where status in ('submitted', 'revision_requested')),
    'returns', (select count(*) from public.returns where status = 'requested'),
    'inventory', (select count(*) from public.variant_availability a
                    join public.products pr on pr.id = a.product_id
                   where pr.status = 'active' and (a.low_stock or a.out_of_stock)),
    'customers', (select count(*) from public.business_profiles
                   where verification_status = 'pending'),
    'reviews', (select count(*) from public.reviews where status = 'pending'),
    'chat', (select count(*) from public.conversations
              where kind = 'support' and status = 'open' and assigned_agent_id is null)
  ) else '{}'::jsonb end;
$$;
revoke execute on function public.admin_badge_counts() from public, anon;
grant execute on function public.admin_badge_counts() to authenticated;

-- ---------------------------------------------------------------------------
-- Line F04 reads up with the A-14d matrix
-- ---------------------------------------------------------------------------

-- True when [p_profile_id] is a staff member (any status). Lets catalog staff
-- see colleagues' names without seeing customers.
create function public.is_staff_profile(p_profile_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.staff_members where profile_id = p_profile_id);
$$;

-- Customers & verification: sales full, support view, catalog none.
drop policy "profiles: own, related or staff" on public.profiles;
create policy "profiles: own, related or staff"
  on public.profiles for select to authenticated
  using (
    id = (select auth.uid())
    or (select public.is_staff('sales', 'support'))
    or ((select public.is_staff()) and public.is_staff_profile(id))
    or public.is_related_profile(id)
  );

drop policy "addresses: staff read" on public.addresses;
create policy "addresses: sales/support read"
  on public.addresses for select to authenticated
  using ((select public.is_staff('sales', 'support')));

-- Riders & cash: super admin; sales and support see the rider on an order.
drop policy "riders: own, related customer or staff" on public.riders;
create policy "riders: own, related customer or staff"
  on public.riders for select to authenticated
  using (
    profile_id = (select auth.uid())
    or (select public.is_staff('sales', 'support'))
    or public.is_related_profile(profile_id)
  );

drop policy "rider_zones: own or staff" on public.rider_zones;
create policy "rider_zones: own or super admin"
  on public.rider_zones for select to authenticated
  using (rider_id = (select auth.uid()) or (select public.is_staff('super_admin')));

drop policy "rider_locations: rider, tracking customer or staff" on public.rider_locations;
create policy "rider_locations: rider, tracking customer or staff"
  on public.rider_locations for select to authenticated
  using (
    rider_id = (select auth.uid())
    or (select public.is_staff('sales', 'support'))
    or public.can_track_delivery(delivery_id)
  );

-- ---------------------------------------------------------------------------
-- Local SMS outbox for staff invites (DEV ONLY; SMS_PROVIDER=dev_outbox)
-- ---------------------------------------------------------------------------
--   select phone, body, created_at from private.dev_sms_messages order by id desc limit 5;

create table private.dev_sms_messages (
  id bigserial primary key,
  phone text not null,
  body text not null,
  created_at timestamptz not null default now()
);
alter table private.dev_sms_messages enable row level security;

create function public.dev_record_sms(p_phone text, p_body text)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into private.dev_sms_messages (phone, body) values (p_phone, p_body);
$$;
revoke execute on function public.dev_record_sms(text, text) from public, anon, authenticated;
grant execute on function public.dev_record_sms(text, text) to service_role;

-- ---------------------------------------------------------------------------
-- Lookups for staff-manage (service role only)
-- ---------------------------------------------------------------------------

-- A staff member with their sign-in email and phone (auth.users).
create function public.staff_member_info(p_uid uuid)
returns table (
  profile_id uuid,
  full_name text,
  email text,
  phone text,
  staff_role public.staff_role,
  status text
)
language sql
stable
security definer
set search_path = ''
as $$
  select s.profile_id, p.full_name, u.email::text,
         case when coalesce(u.phone, '') = '' then null else '+' || ltrim(u.phone, '+') end,
         s.staff_role, s.status
    from public.staff_members s
    join public.profiles p on p.id = s.profile_id
    left join auth.users u on u.id = s.profile_id
   where s.profile_id = p_uid;
$$;

-- The account that signs in with this email or phone (E.164), if any.
create function public.staff_account_for(p_email text default null, p_phone text default null)
returns table (profile_id uuid, role public.user_role, staff_status text)
language sql
stable
security definer
set search_path = ''
as $$
  select u.id, p.role, s.status
    from auth.users u
    join public.profiles p on p.id = u.id
    left join public.staff_members s on s.profile_id = u.id
   where (p_email is not null and lower(u.email) = lower(p_email))
      or (p_phone is not null and u.phone = ltrim(p_phone, '+'))
   limit 1;
$$;

revoke execute on function public.staff_member_info(uuid) from public, anon, authenticated;
revoke execute on function public.staff_account_for(text, text) from public, anon, authenticated;
grant execute on function public.staff_member_info(uuid) to service_role;
grant execute on function public.staff_account_for(text, text) to service_role;
