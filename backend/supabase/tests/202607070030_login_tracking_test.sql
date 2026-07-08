\set ON_ERROR_STOP on

-- Proves record_login() logs an event, increments login_count idempotently
-- across calls, and sets first_login_at once. All mutations are rolled back.

begin;

insert into auth.users (id, email, raw_user_meta_data)
values (
  '10000000-0000-0000-0000-000000000030',
  'login-tracking@example.com',
  '{"username":"login_tracking","nickname":"Login Tracking"}'::jsonb
);

do $$
declare
  v_user_id uuid := '10000000-0000-0000-0000-000000000030';
  v_result_1 jsonb;
  v_result_2 jsonb;
  v_log_count integer;
  v_first_login_1 timestamptz;
  v_first_login_2 timestamptz;
begin
  perform set_config('request.jwt.claim.sub', v_user_id::text, true);

  v_result_1 := public.record_login();
  v_result_2 := public.record_login();

  if (v_result_1 ->> 'login_count')::integer <> 1 then
    raise exception 'Expected login_count=1 after first call, got %', v_result_1;
  end if;

  if (v_result_2 ->> 'login_count')::integer <> 2 then
    raise exception 'Expected login_count=2 after second call, got %', v_result_2;
  end if;

  v_first_login_1 := (v_result_1 ->> 'first_login_at')::timestamptz;
  v_first_login_2 := (v_result_2 ->> 'first_login_at')::timestamptz;

  if v_first_login_1 is null or v_first_login_1 <> v_first_login_2 then
    raise exception 'first_login_at should be set once and stay stable: % vs %', v_first_login_1, v_first_login_2;
  end if;

  select count(*) into v_log_count
  from public.user_login_log
  where user_id = v_user_id;

  if v_log_count <> 2 then
    raise exception 'Expected 2 user_login_log rows, got %', v_log_count;
  end if;

  if not exists (
    select 1 from public.profiles
    where id = v_user_id
      and login_count = 2
      and last_login_at is not null
      and first_login_at is not null
  ) then
    raise exception 'profiles.login_count/last_login_at/first_login_at not updated correctly';
  end if;
end;
$$;

rollback;
