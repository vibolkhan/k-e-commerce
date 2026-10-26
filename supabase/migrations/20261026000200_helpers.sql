-- F04 · Shared trigger functions and the audit log.

-- Keeps updated_at current. Attached to every table that has the column in
-- the RLS migration, so new tables only need to be listed there.
create function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- ADM-10 / US-13: admin actions on orders, prices, stock, refunds and settings.
create table public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid references auth.users (id) on delete set null,
  entity text not null,
  entity_id text,
  action text not null check (action in ('insert', 'update', 'delete')),
  diff jsonb not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index audit_logs_entity_idx on public.audit_logs (entity, entity_id);
create index audit_logs_created_at_idx on public.audit_logs (created_at desc);

-- Writes one audit row per change. TG_ARGV[0] names the key column when it
-- is not `id`. Updates store only the columns that changed.
create function public.audit_row()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  key_col text := coalesce(tg_argv[0], 'id');
  row_new jsonb := case when tg_op <> 'DELETE' then to_jsonb(new) end;
  row_old jsonb := case when tg_op <> 'INSERT' then to_jsonb(old) end;
  changes jsonb;
begin
  if tg_op = 'INSERT' then
    changes := jsonb_build_object('new', row_new);
  elsif tg_op = 'DELETE' then
    changes := jsonb_build_object('old', row_old);
  else
    select jsonb_object_agg(n.key, jsonb_build_object('old', o.value, 'new', n.value))
      into changes
      from jsonb_each(row_new) n
      join jsonb_each(row_old) o using (key)
     where n.value is distinct from o.value
       and n.key <> 'updated_at';
    if changes is null then
      return new;
    end if;
  end if;

  insert into public.audit_logs (actor_id, entity, entity_id, action, diff)
  values (
    auth.uid(),
    tg_table_name,
    coalesce(row_new, row_old) ->> key_col,
    lower(tg_op),
    changes
  );
  return coalesce(new, old);
end;
$$;

-- Column guard for API users (anon / authenticated). RLS decides which rows
-- someone may update; this decides which columns. TG_ARGV[0] is a
-- comma-separated list of staff roles allowed to change the columns
-- ('' = nobody: only Edge Functions with the service role). The remaining
-- arguments are the guarded column names. super_admin always passes when a
-- role list is given.
create function public.guard_columns()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  allowed public.staff_role[];
  i int;
begin
  if current_user not in ('anon', 'authenticated') then
    return new;
  end if;

  if tg_argv[0] <> '' then
    allowed := string_to_array(tg_argv[0], ',')::public.staff_role[];
    if public.is_staff(variadic allowed) then
      return new;
    end if;
  end if;

  for i in 1 .. tg_nargs - 1 loop
    if (to_jsonb(new) -> tg_argv[i]) is distinct from (to_jsonb(old) -> tg_argv[i]) then
      raise exception 'Not allowed to change %.%', tg_table_name, tg_argv[i]
        using errcode = '42501';
    end if;
  end loop;
  return new;
end;
$$;
