\set ON_ERROR_STOP on

-- Proves check_and_grant_awards grants login-count and level-complete badges
-- exactly once each, and stops returning them once seen. All mutations roll
-- back.

begin;

insert into auth.users (id, email, raw_user_meta_data)
values (
  '10000000-0000-0000-0000-000000000031',
  'awards-system@example.com',
  '{"username":"awards_system","nickname":"Awards System"}'::jsonb
);

do $$
declare
  v_user_id uuid := '10000000-0000-0000-0000-000000000031';
  v_new_count_1 integer;
  v_new_count_2 integer;
  v_has_bronze boolean;
  v_has_first_level boolean;
begin
  perform set_config('request.jwt.claim.sub', v_user_id::text, true);

  update public.profiles set login_count = 1 where id = v_user_id;

  insert into public.user_level_progress (user_id, level_number, is_unlocked, is_completed, unlocked_at)
  values (v_user_id, 1, true, true, now())
  on conflict (user_id, level_number) do update
  set is_unlocked = true, is_completed = true;

  select count(*) into v_new_count_1 from public.check_and_grant_awards(v_user_id);

  if v_new_count_1 <> 2 then
    raise exception 'Expected 2 newly granted awards (bronze_duck + first_level), got %', v_new_count_1;
  end if;

  select count(*) into v_new_count_2 from public.check_and_grant_awards(v_user_id);

  if v_new_count_2 <> 0 then
    raise exception 'Expected 0 newly granted awards on second call (already seen), got %', v_new_count_2;
  end if;

  select exists (
    select 1 from public.user_awards where user_id = v_user_id and award_id = 'bronze_duck'
  ) into v_has_bronze;

  select exists (
    select 1 from public.user_awards where user_id = v_user_id and award_id = 'first_level'
  ) into v_has_first_level;

  if not v_has_bronze or not v_has_first_level then
    raise exception 'Expected both bronze_duck and first_level rows in user_awards';
  end if;

  if exists (
    select 1 from public.user_awards
    where user_id = v_user_id and award_id = 'silver_duck'
  ) then
    raise exception 'silver_duck should not be granted at login_count=1';
  end if;
end;
$$;

rollback;
