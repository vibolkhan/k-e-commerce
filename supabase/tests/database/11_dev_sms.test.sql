-- F05: local Send SMS hook keeps the code instead of sending it.
begin;
select plan(6);

select has_table('private', 'dev_sms_outbox', 'the outbox lives in the private schema');
select ok(
  not has_function_privilege('anon', 'private.dev_send_sms(jsonb)', 'execute')
    and not has_function_privilege('authenticated', 'private.dev_send_sms(jsonb)', 'execute'),
  'the API roles cannot call the hook'
);
select ok(
  not has_table_privilege('anon', 'private.dev_sms_outbox', 'select')
    and not has_table_privilege('authenticated', 'private.dev_sms_outbox', 'select'),
  'the API roles cannot read the codes'
);
select ok(
  has_function_privilege('supabase_auth_admin', 'private.dev_send_sms(jsonb)', 'execute'),
  'Auth can call the hook'
);

select is(
  private.dev_send_sms('{"user": {"phone": "855971112222"}, "sms": {"otp": "424242"}}'::jsonb),
  '{}'::jsonb,
  'the hook returns {} (sent)'
);
select is(
  (select otp from private.dev_sms_outbox where phone = '855971112222' order by id desc limit 1),
  '424242',
  'the code is kept in the outbox'
);

select * from finish();
rollback;
