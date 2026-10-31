-- F15 · Address delivery quotes and the A-14 delivery-zone directory.
-- Money and zone membership are decided here, never in Flutter.

create function public.quote_delivery(
  p_address uuid,
  p_subtotal_cents integer,
  p_now timestamptz default now()
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_address public.addresses;
  v_zone public.delivery_zones;
  v_fee integer;
  v_cod_limit integer;
  v_cutoff time := time '15:00';
  v_local_time time;
begin
  if p_subtotal_cents is null or p_subtotal_cents < 0 then
    raise exception 'subtotal must be a non-negative number' using errcode = '22023';
  end if;

  select * into v_address
    from public.addresses a
   where a.id = p_address
     and a.profile_id = auth.uid();
  if not found then
    return jsonb_build_object('status', 'not_found');
  end if;

  -- Re-evaluate the pin each time so a reshaped or paused zone applies to new
  -- checkouts without mutating a customer's saved address.
  select z.* into v_zone
    from public.delivery_zones z
   where z.active
     and v_address.lat is not null
     and v_address.lng is not null
     and extensions.st_covers(
       z.area,
       extensions.st_setsrid(
         extensions.st_makepoint(v_address.lng, v_address.lat), 4326
       )::extensions.geography
     )
   order by z.sort, z.id
   limit 1;

  if not found then
    return jsonb_build_object(
      'status', 'out_of_zone',
      'address_id', v_address.id,
      'city', v_address.city
    );
  end if;

  v_fee := case
    when v_zone.free_threshold_cents is not null
     and p_subtotal_cents >= v_zone.free_threshold_cents then 0
    else v_zone.fee_cents
  end;
  select coalesce(
           v_zone.cod_limit_cents,
           (select (s.value #>> '{}')::integer
              from public.app_settings s where s.key = 'cod_limit_cents'),
           20000
         ) into v_cod_limit;
  select coalesce(
           (select trim(both '"' from s.value::text)::time
              from public.app_settings s where s.key = 'same_day_cutoff'),
           time '15:00'
         ) into v_cutoff;
  v_local_time := (p_now at time zone 'Asia/Phnom_Penh')::time;

  return jsonb_build_object(
    'status', 'available',
    'address_id', v_address.id,
    'zone_id', v_zone.id,
    'zone_name', v_zone.name,
    'fee_cents', v_fee,
    'free_delivery', v_fee = 0,
    'same_day_eligible', v_zone.same_day and v_local_time < v_cutoff,
    'cod_allowed', v_zone.cod_enabled and p_subtotal_cents + v_fee <= v_cod_limit,
    'cod_limit_cents', v_cod_limit
  );
end;
$$;

revoke execute on function public.quote_delivery(uuid, integer, timestamptz) from public, anon;
grant execute on function public.quote_delivery(uuid, integer, timestamptz) to authenticated;

create function public.delivery_zone_directory()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.is_staff('super_admin') then
    raise insufficient_privilege;
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', z.id,
      'name', z.name,
      'polygon', extensions.st_asgeojson(z.area::extensions.geometry)::jsonb,
      'fee_cents', z.fee_cents,
      'free_threshold_cents', z.free_threshold_cents,
      'same_day', z.same_day,
      'cod_enabled', z.cod_enabled,
      'cod_limit_cents', coalesce(z.cod_limit_cents, 20000),
      'active', z.active,
      'sort', z.sort
    ) order by z.sort, z.name)
    from public.delivery_zones z
  ), '[]'::jsonb);
end;
$$;
revoke execute on function public.delivery_zone_directory() from public, anon;
grant execute on function public.delivery_zone_directory() to authenticated;

-- Called only by delivery-zone-manage with the authenticated super-admin id.
create function public.update_delivery_zone(
  p_actor uuid,
  p_id uuid,
  p_name text,
  p_polygon jsonb,
  p_fee_cents integer,
  p_free_threshold_cents integer,
  p_same_day boolean,
  p_cod_enabled boolean,
  p_cod_limit_cents integer,
  p_active boolean
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_area extensions.geography;
begin
  if not exists (
    select 1 from public.staff_members s join public.profiles p on p.id = s.profile_id
     where s.profile_id = p_actor and s.staff_role = 'super_admin'
       and s.status = 'active' and p.role = 'staff' and not p.is_blocked
  ) then
    return jsonb_build_object('status', 'forbidden');
  end if;
  if nullif(btrim(p_name), '') is null or p_fee_cents < 0
     or p_free_threshold_cents < 0 or p_cod_limit_cents < 0 then
    return jsonb_build_object('status', 'invalid');
  end if;
  begin
    v_area := extensions.st_multi(
      extensions.st_setsrid(extensions.st_geomfromgeojson(p_polygon), 4326)
    )::extensions.geography;
    if not extensions.st_isvalid(v_area::extensions.geometry) then
      return jsonb_build_object('status', 'invalid_polygon');
    end if;
  exception when others then
    return jsonb_build_object('status', 'invalid_polygon');
  end;

  update public.delivery_zones
     set name = btrim(p_name), area = v_area, fee_cents = p_fee_cents,
         free_threshold_cents = p_free_threshold_cents, same_day = p_same_day,
         cod_enabled = p_cod_enabled, cod_limit_cents = p_cod_limit_cents,
         active = p_active
   where id = p_id;
  if not found then return jsonb_build_object('status', 'not_found'); end if;
  return jsonb_build_object('status', 'saved', 'id', p_id);
end;
$$;
revoke execute on function public.update_delivery_zone(uuid, uuid, text, jsonb, integer, integer, boolean, boolean, integer, boolean)
  from public, anon, authenticated;

