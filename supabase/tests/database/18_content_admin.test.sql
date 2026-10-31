begin;
select plan(5);

select tests.login_as('dara@kstore.example');
select is((select count(*) from public.banners where title->>'en' = 'Back to school'), 0::bigint,
  'customer cannot read a future banner');
select is((select count(*) from public.banners where title->>'en' = 'Rainy season essentials'), 0::bigint,
  'customer cannot read an ended banner');

select tests.login_as('visal@kstore.example');
select ok((select count(*) >= 4 from public.banners), 'catalog staff reads every banner');
select lives_ok($$update public.banners set active = false where title->>'en' = 'Back to school'$$,
  'catalog staff manages banners');

select tests.login_as('sophea@kstore.example');
select is(tests.rows($$update public.banners set active = false$$), 0,
  'support cannot manage banners');

select * from finish();
rollback;
