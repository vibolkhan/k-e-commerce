-- F06 · Account deletion (AUTH-07, S-08f/g).
--
-- Deleting an account removes the person's data but keeps what the law needs:
-- orders, payments, quotes and returns (the invoice record, including the
-- address snapshot on each order) stay, linked to an anonymised profile.
--
-- The account-delete Edge Function checks eligibility, removes Storage files,
-- then deletes the auth user. The trigger below scrubs the profile in the same
-- transaction, so a delete from the dashboard behaves the same way.

alter table public.profiles add column deleted_at timestamptz;

-- The profile outlives its auth user as a tombstone: orders, RFQs and returns
-- reference it `on delete restrict`, so it cannot cascade away.
alter table public.profiles drop constraint profiles_id_fkey;

-- The phone is set by Auth (sign-in), never typed into the profile; deletion
-- is recorded by the server only.
drop trigger guard_columns_service on public.profiles;
create trigger guard_columns_service
  before update on public.profiles
  for each row execute function public.guard_columns(
    '', 'id', 'role', 'created_at', 'phone', 'deleted_at', 'deletion_requested_at'
  );

-- Orders and returns that would be stranded by a deletion: anything not yet
-- finished. The person must wait for them (or cancel) first.
create function public.account_deletion_check(p_uid uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'role', (select role from public.profiles where id = p_uid),
    'active_orders', (
      select count(*) from public.orders
       where profile_id = p_uid
         and status in (
           'pending_payment', 'awaiting_bank_transfer', 'confirmed', 'packing',
           'ready', 'out_for_delivery', 'failed_delivery'
         )
    ),
    'open_returns', (
      select count(*) from public.returns
       where profile_id = p_uid
         and status in ('requested', 'approved', 'picked_up', 'inspected')
    )
  );
$$;
revoke execute on function public.account_deletion_check(uuid) from public, anon, authenticated;
grant execute on function public.account_deletion_check(uuid) to service_role;

-- Removes everything personal for one user and leaves the profile as a
-- tombstone. `p_reason` is the optional "Why are you leaving?" answer.
create function private.anonymise_account(p_uid uuid, p_reason text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role public.user_role;
begin
  select role into v_role from public.profiles where id = p_uid;
  if not found or exists (
    select 1 from public.profiles where id = p_uid and deleted_at is not null
  ) then
    return;
  end if;

  delete from public.addresses where profile_id = p_uid;
  delete from public.wishlists where profile_id = p_uid;
  delete from public.carts where profile_id = p_uid;
  delete from public.conversations where customer_id = p_uid;  -- messages cascade
  delete from public.notifications where profile_id = p_uid;
  delete from public.device_tokens where profile_id = p_uid;

  -- Company name, TIN and address stay: they are printed on B2B invoices.
  update public.business_profiles
     set contact_name = null, contact_phone = null, licence_path = null
   where profile_id = p_uid;

  update public.profiles
     set full_name = null,
         phone = null,
         email = null,
         avatar_url = null,
         notification_prefs = '{}',
         blocked_reason = null,
         deletion_requested_at = coalesce(deletion_requested_at, now()),
         deleted_at = now()
   where id = p_uid;

  insert into public.audit_logs (actor_id, entity, entity_id, action, diff)
  values (
    null,
    'profiles',
    p_uid::text,
    'delete',
    jsonb_build_object('role', v_role, 'reason', nullif(trim(p_reason), ''))
  );
end;
$$;
revoke execute on function private.anonymise_account(uuid, text) from public, anon, authenticated;

create function private.on_auth_user_deleted()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.anonymise_account(
    old.id,
    old.raw_app_meta_data ->> 'deletion_reason'
  );
  return old;
end;
$$;
revoke execute on function private.on_auth_user_deleted() from public, anon, authenticated;

create trigger on_auth_user_deleted
  before delete on auth.users
  for each row execute function private.on_auth_user_deleted();
