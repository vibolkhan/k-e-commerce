-- Business buyers: never retail prices; RFQs only once verified.
begin;
select plan(17);

select tests.login_as('sokha@kstore.example');

select is((select count(*)::int from public.prices), 0, 'business buyers see no retail prices');
select ok((select count(*) from public.products) > 0, 'business buyers still browse products');
select throws_ok(
  $$ insert into public.carts (profile_id) values (auth.uid()) $$,
  '42501', null, 'business buyers have no retail cart'
);

-- RFQs.
select lives_ok(
  $$ insert into public.rfqs (id, profile_id, required_date, notes)
     values ('b0000000-0000-4000-8000-0000000009a1', auth.uid(), current_date + 7, 'Test') $$,
  'a verified business buyer can submit an RFQ'
);
select matches(
  (select number from public.rfqs where id = 'b0000000-0000-4000-8000-0000000009a1'),
  '^RFQ-\d{4}$',
  'RFQ numbers look like RFQ-0316'
);
select throws_ok(
  $$ insert into public.rfq_items (rfq_id, product_id, qty)
     select 'b0000000-0000-4000-8000-0000000009a1', id, 5
       from public.products where slug = 'a4-copy-paper-80gsm' $$,
  '23514', null, 'RFQ items respect the minimum quote quantity'
);
select lives_ok(
  $$ insert into public.rfq_items (rfq_id, product_id, qty)
     select 'b0000000-0000-4000-8000-0000000009a1', id, 50
       from public.products where slug = 'a4-copy-paper-80gsm' $$,
  'RFQ item at or above the minimum is accepted'
);
select throws_ok(
  $$ insert into public.rfqs (profile_id, status) values (auth.uid(), 'quoted') $$,
  '42501', null, 'buyers cannot create an RFQ in another status'
);
select is((select count(*)::int from public.rfqs), 3, 'Sokha sees his own RFQs');
select is((select count(*)::int from public.quotes), 2, 'Sokha sees his sent quotes');
select is((select count(*)::int from public.quote_items), 5, 'Sokha sees his quote lines');
select is(
  tests.rows($$ update public.quotes set status = 'accepted' $$),
  0,
  'buyers cannot accept a quote by writing to it'
);
select is((select count(*)::int from public.conversations), 1, 'Sokha sees his RFQ thread');

-- A pending applicant is still a customer.
select tests.login_as('lina@kstore.example');
select throws_ok(
  $$ insert into public.rfqs (profile_id) values (auth.uid()) $$,
  '42501', null, 'an unverified applicant cannot submit an RFQ'
);
select throws_ok(
  $$ update public.business_profiles set verification_status = 'approved' where profile_id = auth.uid() $$,
  '42501', null, 'applicants cannot approve themselves'
);

-- Sales approves Lina: she becomes a business buyer and loses retail prices.
select tests.login_as('dalin@kstore.example');
select is(
  tests.rows($$ update public.business_profiles set verification_status = 'approved',
                  verified_by = auth.uid(), verified_at = now()
                where profile_id = tests.uid('lina@kstore.example') $$),
  1,
  'sales can approve a business'
);
select tests.login_as('lina@kstore.example');
select is((select count(*)::int from public.prices), 0, 'once approved, retail prices disappear');

select * from finish();
rollback;
