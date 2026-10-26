-- F07: inbox categories, mark all read, device tokens and prefs (NOT-01/02).
begin;
select plan(17);

-- Only the notify Edge Function (service role) writes inbox rows.
select tests.login_as('dara@kstore.example');
select throws_ok(
  $$ insert into public.notifications (profile_id, type, title, body)
     values (auth.uid(), 'test', '{"en": "x"}', '{"en": "x"}') $$,
  '42501', null, 'a user cannot write their own notification'
);
select throws_ok(
  $$ update public.notifications set category = 'chat' $$,
  '42501', null, 'a user cannot move a notification to another tab'
);

-- Mark all read, one tab at a time or everything; own rows only.
select is(
  public.mark_all_notifications_read('chat'),
  1,
  'Dara marks her one unread chat notification read'
);
select is(
  (select count(*)::int from public.notifications where read_at is null and category = 'orders'),
  2,
  'her unread order notifications are untouched'
);
select is(public.mark_all_notifications_read(), 2, 'then everything else');
select is(public.mark_all_notifications_read(), 0, 'nothing is left unread');
select tests.as_owner();
select is(
  (select count(*)::int from public.notifications
    where profile_id = tests.uid('sokha@kstore.example') and read_at is null),
  1,
  'Sokha''s quote notification is still unread'
);

select tests.logout();
select throws_ok(
  $$ select public.mark_all_notifications_read() $$,
  '42501', null, 'visitors cannot mark anything read'
);

-- Device tokens: register, refresh, and move with the device.
select tests.login_as('dara@kstore.example');
select lives_ok(
  $$ select public.register_device_token('fcm-device-1', 'android') $$,
  'Dara registers her phone'
);
select lives_ok(
  $$ select public.register_device_token('fcm-device-1', 'android') $$,
  'registering again only refreshes it'
);
select is(
  (select count(*)::int from public.device_tokens),
  1,
  'Dara sees one token'
);
select throws_ok(
  $$ select public.register_device_token('fcm-device-2', 'windows') $$,
  '22023', null, 'an unknown platform is refused'
);

select tests.login_as('bopha@kstore.example');
select lives_ok(
  $$ select public.register_device_token('fcm-device-1', 'android') $$,
  'Bopha signs in on the same phone'
);
select tests.as_owner();
select is(
  (select profile_id from public.device_tokens where token = 'fcm-device-1'),
  tests.uid('bopha@kstore.example'),
  'the token now belongs to Bopha, so Dara''s pushes stop reaching it'
);

select tests.login_as('bopha@kstore.example');
select is(
  tests.rows($$ delete from public.device_tokens where token = 'fcm-device-1' $$),
  1,
  'Bopha removes it on sign-out'
);

select tests.logout();
select throws_ok(
  $$ select public.register_device_token('fcm-device-3', 'web') $$,
  '42501', null, 'visitors cannot register a token'
);

-- Preferences stay a JSON object.
select tests.login_as('dara@kstore.example');
select throws_ok(
  $$ update public.profiles set notification_prefs = '[]' where id = auth.uid() $$,
  '23514', null, 'notification_prefs must be an object'
);

select * from finish();
rollback;
