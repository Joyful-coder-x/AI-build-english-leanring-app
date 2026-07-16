\set ON_ERROR_STOP on

begin;

insert into auth.users (id, email, raw_user_meta_data)
values
  (
    '10000000-0000-0000-0000-000000000001',
    'new@example.com',
    '{"username":"new_user","nickname":"New User"}'::jsonb
  ),
  (
    '10000000-0000-0000-0000-000000000002',
    'other@example.com',
    '{"username":"other_user","nickname":"Other User"}'::jsonb
  );

do $$
begin
  if not exists (
    select 1
    from public.onboarding_profiles
    where user_id = '10000000-0000-0000-0000-000000000001'
      and flow_state = 'questionnaire_pending'
      and current_question_index = 0
  ) then
    raise exception 'New user did not receive questionnaire_pending state';
  end if;
end;
$$;

select set_config(
  'request.jwt.claim.sub',
  '10000000-0000-0000-0000-000000000001',
  true
);
set local role authenticated;

select public.save_onboarding_answer('1', 'occupation', 'student', 0);

do $$
begin
  if (
    select current_question_index
    from public.onboarding_profiles
    where user_id = auth.uid()
  ) <> 1 then
    raise exception 'First answer did not advance exactly one step';
  end if;
end;
$$;

-- The exact retry is idempotent and must not advance to question 2.
select public.save_onboarding_answer('1', 'occupation', 'student', 0);

do $$
begin
  if (
    select current_question_index
    from public.onboarding_profiles
    where user_id = auth.uid()
  ) <> 1 then
    raise exception 'Duplicate request advanced the questionnaire';
  end if;
end;
$$;

do $$
begin
  begin
    perform public.save_onboarding_answer(
      '1',
      'self_reported_level',
      'cet4',
      2
    );
    raise exception 'Out-of-order answer was accepted';
  exception
    when others then
      if sqlerrm = 'Out-of-order answer was accepted' then
        raise;
      end if;
  end;
end;
$$;

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
  ) then
    raise exception 'Fifth answer did not complete onboarding';
  end if;

  if not exists (
    select 1
    from public.user_level_progress
    where user_id = auth.uid()
      and level_number = 1
      and is_unlocked
  ) then
    raise exception 'Fifth answer did not unlock Level 1';
  end if;
end;
$$;

reset role;

set local role authenticated;

do $$
begin
  begin
    perform public.save_onboarding_answer('1', 'prep_timeline', 'unsure', 4);
    raise exception 'Finalized onboarding was modified';
  exception
    when others then
      if sqlerrm = 'Finalized onboarding was modified' then
        raise;
      end if;
  end;
end;
$$;

-- RLS must hide the other user's onboarding row.
do $$
begin
  if exists (
    select 1
    from public.onboarding_profiles
    where user_id = '10000000-0000-0000-0000-000000000002'
  ) then
    raise exception 'Cross-user onboarding row was visible';
  end if;
end;
$$;

reset role;

-- Simulate a legacy completed user with missing support rows.
insert into auth.users (id, email, raw_user_meta_data)
values (
  '10000000-0000-0000-0000-000000000003',
  'legacy@example.com',
  '{"username":"legacy_user","nickname":"Legacy User"}'::jsonb
);

update public.profiles
set onboarding_status = 'completed'
where id = '10000000-0000-0000-0000-000000000003';

delete from public.onboarding_profiles
where user_id = '10000000-0000-0000-0000-000000000003';

delete from public.user_level_progress
where user_id = '10000000-0000-0000-0000-000000000003';

select set_config(
  'request.jwt.claim.sub',
  '10000000-0000-0000-0000-000000000003',
  true
);
set local role authenticated;

select public.get_user_bootstrap_state();
select public.get_user_bootstrap_state();

do $$
begin
  if not exists (
    select 1
    from public.onboarding_profiles
    where user_id = auth.uid()
      and flow_state = 'home_ready'
  ) then
    raise exception 'Bootstrap did not repair legacy onboarding state';
  end if;

  if not exists (
    select 1
    from public.user_level_progress
    where user_id = auth.uid()
      and level_number = 1
      and is_unlocked
  ) then
    raise exception 'Bootstrap did not create legacy Level 1 progress';
  end if;

  if (
    select count(*)
    from public.user_level_progress
    where user_id = auth.uid()
      and level_number = 1
  ) <> 1 then
    raise exception 'Bootstrap repair was not idempotent';
  end if;
end;
$$;

rollback;
