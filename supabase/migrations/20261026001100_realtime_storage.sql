-- F04 · Realtime and storage.

-- Live order status, rider tracking, chat and the in-app inbox. Realtime
-- applies the same RLS, so subscribers only receive rows they may read.
alter publication supabase_realtime add table
  public.orders,
  public.deliveries,
  public.rider_locations,
  public.conversations,
  public.messages,
  public.notifications;

-- Buckets. Users upload into a folder named after their user id:
--   <bucket>/<auth.uid()>/<file>
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('product-images', 'product-images', true, 5242880, array['image/jpeg', 'image/png', 'image/webp']),
  ('banners', 'banners', true, 5242880, array['image/jpeg', 'image/png', 'image/webp']),
  ('review-photos', 'review-photos', true, 5242880, array['image/jpeg', 'image/png', 'image/webp']),
  ('pod-photos', 'pod-photos', false, 5242880, array['image/jpeg', 'image/png', 'image/webp']),
  ('bank-slips', 'bank-slips', false, 10485760, array['image/jpeg', 'image/png', 'image/webp', 'application/pdf']),
  ('business-docs', 'business-docs', false, 10485760, array['image/jpeg', 'image/png', 'image/webp', 'application/pdf']),
  ('chat-attachments', 'chat-attachments', false, 10485760, array['image/jpeg', 'image/png', 'image/webp', 'application/pdf'])
on conflict (id) do nothing;

-- Catalog images and banners: public read (public buckets), catalog staff write.
create policy "catalog images: catalog staff write"
  on storage.objects for insert to authenticated
  with check (
    bucket_id in ('product-images', 'banners')
    and (select public.is_staff('catalog'))
  );
create policy "catalog images: catalog staff change"
  on storage.objects for update to authenticated
  using (
    bucket_id in ('product-images', 'banners')
    and (select public.is_staff('catalog'))
  );
create policy "catalog images: catalog staff delete"
  on storage.objects for delete to authenticated
  using (
    bucket_id in ('product-images', 'banners')
    and (select public.is_staff('catalog'))
  );

-- User uploads go to their own folder.
create policy "user uploads: own folder"
  on storage.objects for insert to authenticated
  with check (
    bucket_id in ('review-photos', 'bank-slips', 'business-docs', 'chat-attachments')
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );
create policy "pod photos: rider's own folder"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'pod-photos'
    and (select public.is_rider())
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

-- Private files: the owner, plus the staff who need them.
create policy "private files: owner or staff read"
  on storage.objects for select to authenticated
  using (
    (
      bucket_id in ('pod-photos', 'bank-slips', 'business-docs', 'chat-attachments')
      and (storage.foldername(name))[1] = (select auth.uid())::text
    )
    or (bucket_id = 'pod-photos' and (select public.is_staff('sales', 'support')))
    or (bucket_id = 'bank-slips' and (select public.is_staff('sales')))
    or (bucket_id = 'business-docs' and (select public.is_staff('sales', 'support')))
    or (bucket_id = 'chat-attachments' and (select public.is_staff('support', 'sales')))
  );
create policy "user uploads: delete own"
  on storage.objects for delete to authenticated
  using (
    bucket_id in ('review-photos', 'chat-attachments')
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );
