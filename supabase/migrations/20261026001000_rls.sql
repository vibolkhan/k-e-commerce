-- F04 · Row-Level Security for every table, in one place.
--
-- The model (see delivery/f04-supabase-schema/README.md):
--   * Customers see only their own rows; business buyers never see `prices`.
--   * Riders see only deliveries assigned to them.
--   * Staff by role (A-14d): super_admin everything; sales orders/RFQs/
--     customers; support chat/returns/reviews; catalog products/content.
--   * Money, stock and status are never written by clients: no client grants
--     on orders, payments, refunds, stock or deliveries. Edge Functions use the
--     service role, which bypasses RLS.
--   * RLS picks the rows; guard_columns() triggers pick the columns.
--
-- Policies call helpers as `(select public.fn())` so Postgres evaluates them
-- once per statement instead of once per row.

-- ---------------------------------------------------------------------------
-- Relationship helpers (SECURITY DEFINER: no recursion into other policies).
-- ---------------------------------------------------------------------------

create function public.owns_order(p_order_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.orders o
     where o.id = p_order_id and o.profile_id = auth.uid()
  );
$$;

create function public.rider_has_order(p_order_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.deliveries d
     where d.order_id = p_order_id and d.rider_id = auth.uid()
  );
$$;

-- A rider and the customer of one of their deliveries may see each other's
-- name and phone (RID-02, C-12d). For the customer, only while it is active.
create function public.is_related_profile(p_profile_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
      from public.deliveries d
      join public.orders o on o.id = d.order_id
     where (d.rider_id = auth.uid() and o.profile_id = p_profile_id)
        or (o.profile_id = auth.uid()
            and d.rider_id = p_profile_id
            and d.status in ('assigned', 'picked_up'))
  );
$$;

-- ORD-02 / US-05: the customer's live map while their order is on the way.
create function public.can_track_delivery(p_delivery_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
      from public.deliveries d
      join public.orders o on o.id = d.order_id
     where d.id = p_delivery_id
       and o.profile_id = auth.uid()
       and d.status = 'picked_up'
       and o.status = 'out_for_delivery'
  );
$$;

-- REV-01: only after a delivered order of theirs that contains the product.
create function public.has_received_product(p_order_id uuid, p_product_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
      from public.orders o
      join public.order_items i on i.order_id = o.id
     where o.id = p_order_id
       and o.profile_id = auth.uid()
       and o.status = 'delivered'
       and i.product_id = p_product_id
  );
$$;

-- ---------------------------------------------------------------------------
-- Every public table: RLS on, updated_at maintained.
-- ---------------------------------------------------------------------------
do $$
declare
  t record;
begin
  for t in select tablename from pg_tables where schemaname = 'public' loop
    execute format('alter table public.%I enable row level security', t.tablename);
  end loop;

  for t in
    select c.table_name
      from information_schema.columns c
      join information_schema.tables tb using (table_schema, table_name)
     where c.table_schema = 'public'
       and c.column_name = 'updated_at'
       and tb.table_type = 'BASE TABLE'
  loop
    execute format(
      'create trigger set_updated_at before update on public.%I '
      'for each row execute function public.set_updated_at()',
      t.table_name
    );
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- Table privileges. Reads stay granted (RLS filters them); writes are granted
-- only where a policy below allows them.
-- ---------------------------------------------------------------------------
revoke insert, update, delete, truncate on all tables in schema public from anon, authenticated;

grant update on public.profiles to authenticated;
grant insert, update on public.business_profiles to authenticated;
grant insert, update, delete on
  public.staff_members,
  public.delivery_zones,
  public.addresses,
  public.device_tokens,
  public.categories,
  public.products,
  public.product_variants,
  public.prices,
  public.warehouses,
  public.collections,
  public.collection_items,
  public.banners,
  public.content_pages,
  public.carts,
  public.cart_items,
  public.wishlists,
  public.riders,
  public.rider_zones,
  public.rfq_items,
  public.quotes,
  public.quote_items,
  public.reviews,
  public.app_settings
to authenticated;
grant insert on public.rider_locations to authenticated;
grant insert, update on public.rfqs, public.conversations, public.messages to authenticated;
grant update, delete on public.notifications to authenticated;

-- Trigger-only and service-only functions are not callable through the API.
revoke execute on function
  public.handle_new_user(),
  public.audit_row(),
  public.business_profile_sync_role(),
  public.refresh_product_rating(),
  public.touch_conversation(),
  public.rfq_item_check(),
  public.prune_rider_locations()
from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Accounts
-- ---------------------------------------------------------------------------

create policy "profiles: own, related or staff"
  on public.profiles for select to authenticated
  using (
    id = (select auth.uid())
    or (select public.is_staff())
    or public.is_related_profile(id)
  );
create policy "profiles: update own"
  on public.profiles for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));
create policy "profiles: sales manage customers"
  on public.profiles for update to authenticated
  using ((select public.is_staff('sales')))
  with check ((select public.is_staff('sales')));
-- Role changes only through Edge Functions (staff invites, rider accounts) or
-- the business-verification trigger. Blocking is for sales (A-07d).
create trigger guard_columns_service
  before update on public.profiles
  for each row execute function public.guard_columns('', 'id', 'role', 'created_at');
create trigger guard_columns_sales
  before update on public.profiles
  for each row execute function public.guard_columns('sales', 'is_blocked', 'blocked_reason');

create policy "staff_members: own row or super admin"
  on public.staff_members for select to authenticated
  using (profile_id = (select auth.uid()) or (select public.is_staff('super_admin')));
create policy "staff_members: super admin manages"
  on public.staff_members for all to authenticated
  using ((select public.is_staff('super_admin')))
  with check ((select public.is_staff('super_admin')));

create policy "business_profiles: own or sales/support"
  on public.business_profiles for select to authenticated
  using (
    profile_id = (select auth.uid())
    or (select public.is_staff('sales', 'support'))
  );
create policy "business_profiles: customer applies"
  on public.business_profiles for insert to authenticated
  with check (
    profile_id = (select auth.uid())
    and (select public.auth_role()) = 'customer'
    and verification_status = 'pending'
    and verified_by is null
    and verified_at is null
  );
create policy "business_profiles: edit own while not approved"
  on public.business_profiles for update to authenticated
  using (
    profile_id = (select auth.uid())
    and verification_status in ('pending', 'rejected')
  )
  with check (profile_id = (select auth.uid()));
create policy "business_profiles: sales verify"
  on public.business_profiles for update to authenticated
  using ((select public.is_staff('sales')))
  with check ((select public.is_staff('sales')));
create trigger guard_columns_service
  before update on public.business_profiles
  for each row execute function public.guard_columns('', 'id', 'profile_id');
create trigger guard_columns_sales
  before update on public.business_profiles
  for each row execute function public.guard_columns(
    'sales', 'verification_status', 'rejection_reason', 'verified_by', 'verified_at'
  );

create policy "delivery_zones: active zones are public"
  on public.delivery_zones for select to anon, authenticated
  using (active or (select public.is_staff()));
create policy "delivery_zones: super admin manages"
  on public.delivery_zones for all to authenticated
  using ((select public.is_staff('super_admin')))
  with check ((select public.is_staff('super_admin')));

create policy "addresses: own"
  on public.addresses for all to authenticated
  using (profile_id = (select auth.uid()))
  with check (profile_id = (select auth.uid()));
create policy "addresses: staff read"
  on public.addresses for select to authenticated
  using ((select public.is_staff()));

create policy "device_tokens: own"
  on public.device_tokens for all to authenticated
  using (profile_id = (select auth.uid()))
  with check (profile_id = (select auth.uid()));

-- ---------------------------------------------------------------------------
-- Catalog (public read of what is live; catalog staff write)
-- ---------------------------------------------------------------------------

create policy "categories: active are public"
  on public.categories for select to anon, authenticated
  using (active or (select public.is_staff()));
create policy "categories: catalog manages"
  on public.categories for all to authenticated
  using ((select public.is_staff('catalog')))
  with check ((select public.is_staff('catalog')));

create policy "products: active are public"
  on public.products for select to anon, authenticated
  using (status = 'active' or (select public.is_staff()));
create policy "products: catalog manages"
  on public.products for all to authenticated
  using ((select public.is_staff('catalog')))
  with check ((select public.is_staff('catalog')));
-- Ratings and sales counts are computed, never typed in.
create trigger guard_columns_service
  before update on public.products
  for each row execute function public.guard_columns('', 'rating_avg', 'rating_count', 'sold_count');

create policy "product_variants: of visible products"
  on public.product_variants for select to anon, authenticated
  using (
    (select public.is_staff())
    or (active and exists (select 1 from public.products p where p.id = product_id))
  );
create policy "product_variants: catalog manages"
  on public.product_variants for all to authenticated
  using ((select public.is_staff('catalog')))
  with check ((select public.is_staff('catalog')));

-- Business buyers never see retail prices (Q8): they buy through quotes.
create policy "prices: everyone except business buyers"
  on public.prices for select to anon, authenticated
  using (
    not (select public.is_business())
    and exists (select 1 from public.product_variants v where v.id = variant_id)
  );
create policy "prices: catalog manages"
  on public.prices for all to authenticated
  using ((select public.is_staff('catalog')))
  with check ((select public.is_staff('catalog')));

create policy "warehouses: public"
  on public.warehouses for select to anon, authenticated
  using (true);
create policy "warehouses: super admin manages"
  on public.warehouses for all to authenticated
  using ((select public.is_staff('super_admin')))
  with check ((select public.is_staff('super_admin')));

-- Stock levels are shown on product pages ("Only 3 left"); changes go through
-- Edge Functions only (reservations, adjustments with a reason).
create policy "stock: public"
  on public.stock for select to anon, authenticated
  using (true);

create policy "stock_movements: staff read"
  on public.stock_movements for select to authenticated
  using ((select public.is_staff()));

create policy "collections: active are public"
  on public.collections for select to anon, authenticated
  using (active or (select public.is_staff()));
create policy "collections: catalog manages"
  on public.collections for all to authenticated
  using ((select public.is_staff('catalog')))
  with check ((select public.is_staff('catalog')));

create policy "collection_items: of visible collections and products"
  on public.collection_items for select to anon, authenticated
  using (
    exists (select 1 from public.collections c where c.id = collection_id)
    and exists (select 1 from public.products p where p.id = product_id)
  );
create policy "collection_items: catalog manages"
  on public.collection_items for all to authenticated
  using ((select public.is_staff('catalog')))
  with check ((select public.is_staff('catalog')));

create policy "banners: live are public"
  on public.banners for select to anon, authenticated
  using (
    (select public.is_staff())
    or (
      active
      and (starts_at is null or starts_at <= now())
      and (ends_at is null or ends_at > now())
    )
  );
create policy "banners: catalog manages"
  on public.banners for all to authenticated
  using ((select public.is_staff('catalog')))
  with check ((select public.is_staff('catalog')));

create policy "content_pages: published are public"
  on public.content_pages for select to anon, authenticated
  using (published or (select public.is_staff()));
create policy "content_pages: catalog manages"
  on public.content_pages for all to authenticated
  using ((select public.is_staff('catalog')))
  with check ((select public.is_staff('catalog')));

-- ---------------------------------------------------------------------------
-- Cart and wishlist (own rows; business buyers have no cart)
-- ---------------------------------------------------------------------------

create policy "carts: own"
  on public.carts for select to authenticated
  using (profile_id = (select auth.uid()));
create policy "carts: retail customer creates"
  on public.carts for insert to authenticated
  with check (
    profile_id = (select auth.uid())
    and (select public.auth_role()) = 'customer'
  );
create policy "carts: delete own"
  on public.carts for delete to authenticated
  using (profile_id = (select auth.uid()));

create policy "cart_items: own cart"
  on public.cart_items for select to authenticated
  using (exists (
    select 1 from public.carts c
     where c.id = cart_id and c.profile_id = (select auth.uid())
  ));
create policy "cart_items: retail customer adds"
  on public.cart_items for insert to authenticated
  with check (
    (select public.auth_role()) = 'customer'
    and exists (
      select 1 from public.carts c
       where c.id = cart_id and c.profile_id = (select auth.uid())
    )
  );
create policy "cart_items: retail customer changes"
  on public.cart_items for update to authenticated
  using (exists (
    select 1 from public.carts c
     where c.id = cart_id and c.profile_id = (select auth.uid())
  ))
  with check (
    (select public.auth_role()) = 'customer'
    and exists (
      select 1 from public.carts c
       where c.id = cart_id and c.profile_id = (select auth.uid())
    )
  );
create policy "cart_items: remove own"
  on public.cart_items for delete to authenticated
  using (exists (
    select 1 from public.carts c
     where c.id = cart_id and c.profile_id = (select auth.uid())
  ));

create policy "wishlists: own"
  on public.wishlists for all to authenticated
  using (profile_id = (select auth.uid()))
  with check (profile_id = (select auth.uid()));

-- ---------------------------------------------------------------------------
-- Orders and money (read-only for clients)
-- ---------------------------------------------------------------------------

create policy "orders: own, assigned rider, sales/support"
  on public.orders for select to authenticated
  using (
    profile_id = (select auth.uid())
    or (select public.is_staff('sales', 'support'))
    or public.rider_has_order(id)
  );

create policy "order_items: of visible orders"
  on public.order_items for select to authenticated
  using (exists (select 1 from public.orders o where o.id = order_id));

create policy "payments: own order or sales/support"
  on public.payments for select to authenticated
  using (
    public.owns_order(order_id)
    or (select public.is_staff('sales', 'support'))
  );

create policy "refunds: own order or sales/support"
  on public.refunds for select to authenticated
  using (
    public.owns_order(order_id)
    or (select public.is_staff('sales', 'support'))
  );

-- ---------------------------------------------------------------------------
-- Riders and deliveries
-- ---------------------------------------------------------------------------

create policy "riders: own, related customer or staff"
  on public.riders for select to authenticated
  using (
    profile_id = (select auth.uid())
    or (select public.is_staff())
    or public.is_related_profile(profile_id)
  );
create policy "riders: set own duty"
  on public.riders for update to authenticated
  using (profile_id = (select auth.uid()))
  with check (profile_id = (select auth.uid()));
create policy "riders: super admin manages"
  on public.riders for all to authenticated
  using ((select public.is_staff('super_admin')))
  with check ((select public.is_staff('super_admin')));
create trigger guard_columns_super
  before update on public.riders
  for each row execute function public.guard_columns('super_admin', 'profile_id', 'plate', 'active');

create policy "rider_zones: own or staff"
  on public.rider_zones for select to authenticated
  using (rider_id = (select auth.uid()) or (select public.is_staff()));
create policy "rider_zones: super admin manages"
  on public.rider_zones for all to authenticated
  using ((select public.is_staff('super_admin')))
  with check ((select public.is_staff('super_admin')));

create policy "deliveries: assigned rider, own order or sales/support"
  on public.deliveries for select to authenticated
  using (
    rider_id = (select auth.uid())
    or public.owns_order(order_id)
    or (select public.is_staff('sales', 'support'))
  );

create policy "rider_locations: rider, tracking customer or staff"
  on public.rider_locations for select to authenticated
  using (
    rider_id = (select auth.uid())
    or (select public.is_staff())
    or public.can_track_delivery(delivery_id)
  );
create policy "rider_locations: rider on an active delivery"
  on public.rider_locations for insert to authenticated
  with check (
    rider_id = (select auth.uid())
    and (select public.is_rider())
    and exists (
      select 1 from public.deliveries d
       where d.id = delivery_id
         and d.rider_id = (select auth.uid())
         and d.status = 'picked_up'
    )
  );

-- ---------------------------------------------------------------------------
-- B2B: RFQs and quotes
-- ---------------------------------------------------------------------------

create policy "rfqs: own or sales"
  on public.rfqs for select to authenticated
  using (profile_id = (select auth.uid()) or (select public.is_staff('sales')));
create policy "rfqs: verified business submits"
  on public.rfqs for insert to authenticated
  with check (
    profile_id = (select auth.uid())
    and (select public.is_verified_business())
    and status = 'submitted'
    and assigned_to is null
  );
create policy "rfqs: buyer cancels while submitted"
  on public.rfqs for update to authenticated
  using (profile_id = (select auth.uid()) and status = 'submitted')
  with check (profile_id = (select auth.uid()) and status in ('submitted', 'cancelled'));
create policy "rfqs: sales manage"
  on public.rfqs for update to authenticated
  using ((select public.is_staff('sales')))
  with check ((select public.is_staff('sales')));
create trigger guard_columns_service
  before update on public.rfqs
  for each row execute function public.guard_columns('', 'id', 'number', 'profile_id');
create trigger guard_columns_sales
  before update on public.rfqs
  for each row execute function public.guard_columns('sales', 'assigned_to');

create policy "rfq_items: of visible rfqs"
  on public.rfq_items for select to authenticated
  using (exists (select 1 from public.rfqs r where r.id = rfq_id));
create policy "rfq_items: buyer edits while submitted"
  on public.rfq_items for all to authenticated
  using (exists (
    select 1 from public.rfqs r
     where r.id = rfq_id
       and r.profile_id = (select auth.uid())
       and r.status = 'submitted'
  ))
  with check (exists (
    select 1 from public.rfqs r
     where r.id = rfq_id
       and r.profile_id = (select auth.uid())
       and r.status = 'submitted'
  ));

create policy "quotes: sales, or the buyer once sent"
  on public.quotes for select to authenticated
  using (
    (select public.is_staff('sales'))
    or (
      status <> 'draft'
      and exists (
        select 1 from public.rfqs r
         where r.id = rfq_id and r.profile_id = (select auth.uid())
      )
    )
  );
create policy "quotes: sales draft"
  on public.quotes for insert to authenticated
  with check ((select public.is_staff('sales')) and status = 'draft');
create policy "quotes: sales edit drafts"
  on public.quotes for update to authenticated
  using ((select public.is_staff('sales')) and status = 'draft')
  with check ((select public.is_staff('sales')));
create policy "quotes: sales delete drafts"
  on public.quotes for delete to authenticated
  using ((select public.is_staff('sales')) and status = 'draft');
-- Sending, accepting and expiring a quote are Edge Function transitions.
create trigger guard_columns_service
  before update on public.quotes
  for each row execute function public.guard_columns(
    '', 'rfq_id', 'version', 'status', 'sent_at', 'responded_at'
  );

create policy "quote_items: of visible quotes"
  on public.quote_items for select to authenticated
  using (exists (select 1 from public.quotes q where q.id = quote_id));
create policy "quote_items: sales edit drafts"
  on public.quote_items for all to authenticated
  using (
    (select public.is_staff('sales'))
    and exists (select 1 from public.quotes q where q.id = quote_id and q.status = 'draft')
  )
  with check (
    (select public.is_staff('sales'))
    and exists (select 1 from public.quotes q where q.id = quote_id and q.status = 'draft')
  );

-- ---------------------------------------------------------------------------
-- Returns and reviews
-- ---------------------------------------------------------------------------

create policy "returns: own or support"
  on public.returns for select to authenticated
  using (profile_id = (select auth.uid()) or (select public.is_staff('support')));

create policy "return_items: of visible returns"
  on public.return_items for select to authenticated
  using (exists (select 1 from public.returns r where r.id = return_id));

create policy "reviews: published, own or support"
  on public.reviews for select to anon, authenticated
  using (
    status = 'published'
    or profile_id = (select auth.uid())
    or (select public.is_staff('support'))
  );
create policy "reviews: after a delivered order"
  on public.reviews for insert to authenticated
  with check (
    profile_id = (select auth.uid())
    and status = 'pending'
    and admin_reply is null
    and replied_by is null
    and public.has_received_product(order_id, product_id)
  );
create policy "reviews: edit own while pending"
  on public.reviews for update to authenticated
  using (profile_id = (select auth.uid()) and status = 'pending')
  with check (profile_id = (select auth.uid()));
create policy "reviews: support moderates"
  on public.reviews for update to authenticated
  using ((select public.is_staff('support')))
  with check ((select public.is_staff('support')));
create policy "reviews: support removes"
  on public.reviews for delete to authenticated
  using ((select public.is_staff('support')));
create trigger guard_columns_service
  before update on public.reviews
  for each row execute function public.guard_columns('', 'profile_id', 'order_id', 'product_id');
create trigger guard_columns_support
  before update on public.reviews
  for each row execute function public.guard_columns(
    'support', 'status', 'admin_reply', 'replied_by', 'replied_at'
  );

-- ---------------------------------------------------------------------------
-- Chat and notifications
-- ---------------------------------------------------------------------------

create policy "conversations: participants"
  on public.conversations for select to authenticated
  using (
    customer_id = (select auth.uid())
    or (kind = 'support' and (select public.is_staff('support')))
    or (kind = 'rfq' and (select public.is_staff('sales')))
    or (kind = 'delivery' and exists (
      select 1 from public.deliveries d
       where d.id = delivery_id and d.rider_id = (select auth.uid())
    ))
  );
create policy "conversations: customer starts support chat"
  on public.conversations for insert to authenticated
  with check (
    customer_id = (select auth.uid())
    and kind = 'support'
    and status = 'open'
    and assigned_agent_id is null
    and (order_id is null or public.owns_order(order_id))
  );
create policy "conversations: agents manage"
  on public.conversations for update to authenticated
  using (
    (kind = 'support' and (select public.is_staff('support')))
    or (kind = 'rfq' and (select public.is_staff('sales')))
  )
  with check (
    (kind = 'support' and (select public.is_staff('support')))
    or (kind = 'rfq' and (select public.is_staff('sales')))
  );

create policy "messages: in visible conversations"
  on public.messages for select to authenticated
  using (exists (select 1 from public.conversations c where c.id = conversation_id));
create policy "messages: send as self to an open conversation"
  on public.messages for insert to authenticated
  with check (
    sender_id = (select auth.uid())
    and read_at is null
    and exists (
      select 1 from public.conversations c
       where c.id = conversation_id and c.status <> 'resolved'
    )
  );
create policy "messages: recipient marks read"
  on public.messages for update to authenticated
  using (
    sender_id is distinct from (select auth.uid())
    and exists (select 1 from public.conversations c where c.id = conversation_id)
  )
  with check (sender_id is distinct from (select auth.uid()));
create trigger guard_columns_service
  before update on public.messages
  for each row execute function public.guard_columns(
    '', 'conversation_id', 'sender_id', 'body', 'attachments', 'created_at'
  );

create policy "notifications: own"
  on public.notifications for select to authenticated
  using (profile_id = (select auth.uid()));
create policy "notifications: mark own read"
  on public.notifications for update to authenticated
  using (profile_id = (select auth.uid()))
  with check (profile_id = (select auth.uid()));
create policy "notifications: delete own"
  on public.notifications for delete to authenticated
  using (profile_id = (select auth.uid()));
create trigger guard_columns_service
  before update on public.notifications
  for each row execute function public.guard_columns(
    '', 'profile_id', 'type', 'title', 'body', 'payload', 'created_at'
  );

-- ---------------------------------------------------------------------------
-- Settings and audit
-- ---------------------------------------------------------------------------

create policy "app_settings: public read"
  on public.app_settings for select to anon, authenticated
  using (true);
create policy "app_settings: super admin manages"
  on public.app_settings for all to authenticated
  using ((select public.is_staff('super_admin')))
  with check ((select public.is_staff('super_admin')));

create policy "audit_logs: super admin reads"
  on public.audit_logs for select to authenticated
  using ((select public.is_staff('super_admin')));

-- ADM-10: audited tables.
create trigger audit after insert or update or delete on public.orders
  for each row execute function public.audit_row();
create trigger audit after insert or update or delete on public.payments
  for each row execute function public.audit_row();
create trigger audit after insert or update or delete on public.refunds
  for each row execute function public.audit_row();
create trigger audit after insert or update or delete on public.products
  for each row execute function public.audit_row();
create trigger audit after insert or update or delete on public.prices
  for each row execute function public.audit_row();
create trigger audit after insert or update or delete on public.stock
  for each row execute function public.audit_row();
create trigger audit after insert or update or delete on public.business_profiles
  for each row execute function public.audit_row();
create trigger audit after insert or update or delete on public.staff_members
  for each row execute function public.audit_row('profile_id');
create trigger audit after insert or update or delete on public.delivery_zones
  for each row execute function public.audit_row();
create trigger audit after insert or update or delete on public.deliveries
  for each row execute function public.audit_row();
create trigger audit after insert or update or delete on public.app_settings
  for each row execute function public.audit_row('key');
