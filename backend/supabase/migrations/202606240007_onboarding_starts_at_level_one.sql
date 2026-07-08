-- Removes the initial placement-assessment gate.
-- Completing the fifth onboarding answer now atomically:
--   1. marks onboarding home_ready,
--   2. marks the profile completed,
--   3. unlocks Level 1,
--   4. returns the updated bootstrap state.
--
-- Existing users stopped at assessment_pending are migrated to Level 1.
-- Depends on 202606220005_user_bootstrap_and_onboarding.sql.

begin;

update public.onboarding_profiles
set flow_state = 'home_ready',
    completed_at = coalesce(completed_at, now())
where flow_state = 'assessment_pending';

update public.profiles profile
set onboarding_status = 'completed'
where exists (
  select 1
  from public.onboarding_profiles onboarding
  where onboarding.user_id = profile.id
    and onboarding.flow_state = 'home_ready'
);

insert into public.user_level_progress (
  user_id,
  level_number,
  is_unlocked,
  unlocked_at
)
select
  onboarding.user_id,
  1,
  true,
  now()
from public.onboarding_profiles onboarding
where onboarding.flow_state = 'home_ready'
on conflict (user_id, level_number) do update
set is_unlocked = true,
    unlocked_at = coalesce(
      public.user_level_progress.unlocked_at,
      excluded.unlocked_at
    );

create or replace function public.save_onboarding_answer(
  requested_questionnaire_version text,
  requested_answer_key text,
  requested_answer_value text,
  requested_expected_question_index integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  expected_key text;
  current_row public.onboarding_profiles;
  allowed_values text[];
  is_final_answer boolean := requested_expected_question_index = 4;
begin
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;

  if char_length(btrim(requested_questionnaire_version)) not between 1 and 100 then
    raise exception 'Invalid questionnaire version';
  end if;

  if requested_expected_question_index not between 0 and 4 then
    raise exception 'Invalid question index';
  end if;

  if char_length(btrim(requested_answer_value)) not between 1 and 64 then
    raise exception 'Invalid answer value';
  end if;

  expected_key := (array[
    'occupation',
    'ielts_reason',
    'self_reported_level',
    'target_band',
    'prep_timeline'
  ])[requested_expected_question_index + 1];

  if requested_answer_key <> expected_key then
    raise exception 'Answer key does not match question index';
  end if;

  allowed_values := case requested_answer_key
    when 'occupation' then
      array['student', 'employed', 'freelancer', 'full_time_parent', 'other']
    when 'ielts_reason' then
      array['study_abroad', 'work', 'self_improvement', 'migration', 'accompany_child', 'other']
    when 'self_reported_level' then
      array['weak', 'cet4', 'cet6', 'unsure']
    when 'target_band' then
      array['5_0', '5_5', '6_0', '6_5', '7_0_plus']
    when 'prep_timeline' then
      array['under_3_months', '3_to_6_months', 'over_6_months', 'unsure']
    else array[]::text[]
  end;

  if not (requested_answer_value = any(allowed_values)) then
    raise exception 'Invalid answer value for %', requested_answer_key;
  end if;

  insert into public.onboarding_profiles (
    user_id,
    questionnaire_version,
    answers,
    flow_state,
    current_question_index
  )
  values (
    current_user_id,
    btrim(requested_questionnaire_version),
    '{}'::jsonb,
    'questionnaire_pending',
    0
  )
  on conflict (user_id) do nothing;

  select *
  into current_row
  from public.onboarding_profiles
  where user_id = current_user_id
  for update;

  if current_row.questionnaire_version <> btrim(requested_questionnaire_version) then
    raise exception 'Questionnaire version mismatch';
  end if;

  -- Exact retries are idempotent, including retrying the fifth answer after
  -- the first request already finalized onboarding.
  if current_row.current_question_index > requested_expected_question_index then
    if current_row.answers ->> requested_answer_key = requested_answer_value then
      return public.build_user_bootstrap_state(current_user_id);
    end if;
    raise exception 'Answer was already submitted with a different value';
  end if;

  if current_row.flow_state in ('placement_finalized', 'home_ready') then
    raise exception 'Onboarding is already finalized';
  end if;

  if current_row.current_question_index <> requested_expected_question_index
     or current_row.flow_state <> 'questionnaire_pending' then
    raise exception 'Out-of-order onboarding answer';
  end if;

  update public.onboarding_profiles
  set answers = current_row.answers ||
        jsonb_build_object(requested_answer_key, requested_answer_value),
      current_question_index = requested_expected_question_index + 1,
      flow_state = case
        when is_final_answer then 'home_ready'::public.onboarding_flow_state_enum
        else 'questionnaire_pending'::public.onboarding_flow_state_enum
      end,
      completed_at = case when is_final_answer then now() else completed_at end
  where user_id = current_user_id;

  update public.profiles
  set onboarding_status = case
    when is_final_answer then 'completed'::public.onboarding_status_enum
    else 'in_progress'::public.onboarding_status_enum
  end
  where id = current_user_id;

  if is_final_answer then
    insert into public.user_level_progress (
      user_id,
      level_number,
      is_unlocked,
      unlocked_at
    )
    values (
      current_user_id,
      1,
      true,
      now()
    )
    on conflict (user_id, level_number) do update
    set is_unlocked = true,
        unlocked_at = coalesce(
          public.user_level_progress.unlocked_at,
          excluded.unlocked_at
        );
  end if;

  return public.build_user_bootstrap_state(current_user_id);
end;
$$;

revoke all on function public.save_onboarding_answer(
  text,
  text,
  text,
  integer
) from public;
grant execute on function public.save_onboarding_answer(
  text,
  text,
  text,
  integer
) to authenticated;

comment on function public.save_onboarding_answer(text, text, text, integer) is
  'Validates and atomically persists one ordered onboarding answer. The fifth answer completes onboarding and unlocks Level 1.';

commit;
