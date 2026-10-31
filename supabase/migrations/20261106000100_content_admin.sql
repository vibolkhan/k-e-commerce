-- F14: speed the server-evaluated live/scheduled query and let Home refresh
-- when an administrator changes banner content.
create index banners_live_schedule_idx
  on public.banners (audience, sort, starts_at, ends_at)
  where active;

alter publication supabase_realtime add table public.banners;
