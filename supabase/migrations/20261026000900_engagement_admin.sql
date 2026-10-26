-- F04 · Chat, notifications and app settings.

-- CHT-01..03. `support` = customer ↔ support agents (optionally about an
-- order); `rfq` = buyer ↔ sales on an RFQ thread; `delivery` = customer ↔
-- rider for an active delivery.
create table public.conversations (
  id uuid primary key default gen_random_uuid(),
  kind text not null default 'support' check (kind in ('support', 'rfq', 'delivery')),
  customer_id uuid not null references public.profiles (id) on delete cascade,
  order_id uuid references public.orders (id) on delete set null,
  rfq_id uuid references public.rfqs (id) on delete cascade,
  delivery_id uuid references public.deliveries (id) on delete cascade,
  assigned_agent_id uuid references public.profiles (id) on delete set null,
  status public.conversation_status not null default 'open',
  subject text,
  last_message_at timestamptz,
  resolved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (kind <> 'rfq' or rfq_id is not null),
  check (kind <> 'delivery' or delivery_id is not null)
);
create index conversations_customer_idx on public.conversations (customer_id);
create index conversations_queue_idx on public.conversations (kind, status, last_message_at desc);

create table public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations (id) on delete cascade,
  sender_id uuid references public.profiles (id) on delete set null,
  body text,
  attachments text[] not null default '{}',  -- storage: chat-attachments/<uid>/...
  read_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (body is not null or cardinality(attachments) > 0)
);
create index messages_conversation_idx on public.messages (conversation_id, created_at);

create function public.touch_conversation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.conversations
     set last_message_at = new.created_at
   where id = new.conversation_id;
  return null;
end;
$$;
create trigger touch_conversation
  after insert on public.messages
  for each row execute function public.touch_conversation();

-- NOT-02: in-app inbox. Rows are written by Edge Functions.
create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles (id) on delete cascade,
  type text not null,  -- order_status, payment, rfq, chat, return, business, ...
  title jsonb not null default '{}',
  body jsonb not null default '{}',
  payload jsonb not null default '{}',  -- e.g. {"route": "/customer/orders/<id>"}
  read_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index notifications_profile_idx on public.notifications (profile_id, created_at desc);

-- Key/value settings (A-14): cut-off, rates, limits. Contract with F03:
--   select value from app_settings where key = 'khr_per_usd';  -- 4100
-- Readable by everyone, written by super admins, every change audited.
create table public.app_settings (
  key text primary key check (key ~ '^[a-z][a-z0-9_]*$'),
  value jsonb not null,
  description text,
  updated_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
