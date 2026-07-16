\set ON_ERROR_STOP on

begin;

insert into auth.users (id, email, raw_user_meta_data)
values (
  '10000000-0000-0000-0000-000000000007',
  'level-one@example.com',
  '{"username":"level_one_user","nickname":"Level One User"}'::jsonb
);

select set_config(
  'request.jwt.claim.sub',
  '10000000-0000-0000-0000-000000000007',
  true
);
set local role authenticated;

select public.save_onboarding_answer('1', 'occupation', 'student', 0);
select public.save_onboarding_answer('1', 'ielts_reason', 'study_abroad', 1);
select public.save_onboarding_answer('1', 'self_reported_level', 'cet4', 2);
select public.save_onboarding_answer('1', 'target_band', '6_5', 3);
select public.save_onboarding_answer('1', 'prep_timeline', '3_to_6_months', 4);

do $$
begin
  if not exists (
    select 1
    from public.onboarding_profiles
    where user_id = auth.uid()
      and flow_state = 'home_ready'
      and current_question_index = 5
      and completed_at is not null
  ) then
    raise exception 'Fifth answer did not complete onboarding';
  end if;

  if (
    select onboarding_status
    from public.profiles
    where id = auth.uid()
  ) <> 'completed' then
    raise exception 'Profile onboarding status was not completed';
  end if;

  if not exists (
    select 1
    from public.user_level_progress
    where user_id = auth.uid()
      and level_number = 1
      and is_unlocked
  ) then
    raise exception 'Level 1 was not unlocked';
  end if;
end;
$$;

-- Exact retry must remain safe after onboarding is home_ready.
select public.save_onboarding_answer('1', 'prep_timeline', '3_to_6_months', 4);

do $$
begin
  if (
    select count(*)
    from public.user_level_progress
    where user_id = auth.uid()
      and level_number = 1
  ) <> 1 then
    raise exception 'Retry created duplicate Level 1 progress';
  end if;
end;
$$;

rollback;
