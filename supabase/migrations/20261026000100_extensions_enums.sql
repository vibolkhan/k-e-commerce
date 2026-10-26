-- F04 · Extensions and enums.
-- Every status in the App Flow §5 diagrams is an enum, so a typo can never
-- create a new state. Display labels ("Quote ready", "Closed") live in the app.

create extension if not exists pgcrypto with schema extensions;
create extension if not exists pg_trgm with schema extensions;
create extension if not exists postgis with schema extensions;

-- Who the user is. Staff have one staff_role in staff_members.
create type public.user_role as enum ('customer', 'business', 'rider', 'staff');
create type public.staff_role as enum ('super_admin', 'sales', 'support', 'catalog');

-- App Flow §5.1. COD orders skip pending_payment; B2B bank transfer starts at
-- awaiting_bank_transfer.
create type public.order_status as enum (
  'pending_payment',
  'awaiting_bank_transfer',
  'confirmed',
  'packing',
  'ready',
  'out_for_delivery',
  'delivered',
  'failed_delivery',
  'cancelled',
  'returned'
);

-- payments.provider stays text so ABA PayWay can plug in without a migration.
create type public.payment_method as enum ('khqr', 'cod', 'bank_transfer');

-- App Flow §5.2.
create type public.payment_status as enum (
  'pending',               -- KHQR shown, waiting for the bank
  'unpaid_cod',            -- rider collects on delivery
  'awaiting_confirmation', -- bank slip uploaded, admin to confirm
  'rejected',              -- slip invalid; buyer may re-upload
  'paid',
  'expired',               -- KHQR not paid within 15 minutes
  'refunded',
  'partially_refunded'
);

create type public.refund_status as enum ('pending', 'completed', 'failed');

-- App Flow §5.3. RFQ and quote are separate: an RFQ has quote versions.
create type public.rfq_status as enum (
  'submitted',
  'in_review',
  'quoted',
  'revision_requested',
  'accepted',
  'rejected',
  'expired',
  'cancelled'
);
create type public.quote_status as enum (
  'draft',
  'sent',
  'accepted',
  'rejected',
  'expired',
  'superseded'  -- replaced by a newer version after a revision request
);

-- App Flow §5.4.
create type public.delivery_status as enum (
  'unassigned',
  'assigned',
  'picked_up',
  'delivered',
  'failed'
);

-- App Flow §5.5.
create type public.return_status as enum (
  'requested',
  'approved',
  'picked_up',
  'inspected',
  'refunded',
  'rejected'
);

create type public.verification_status as enum ('pending', 'approved', 'rejected');
create type public.review_status as enum ('pending', 'published', 'hidden');
create type public.product_status as enum ('draft', 'active', 'archived');
create type public.conversation_status as enum ('open', 'assigned', 'resolved');
create type public.banner_audience as enum ('all', 'retail', 'business');
create type public.return_fee_method as enum ('cash_at_pickup', 'from_refund');
create type public.stock_reason as enum (
  'received',
  'adjustment',
  'damaged',
  'reserved',
  'released',
  'sold',
  'returned'
);
