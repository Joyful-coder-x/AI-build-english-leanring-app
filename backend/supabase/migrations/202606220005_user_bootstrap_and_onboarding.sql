-- Server-owned authentication bootstrap and resumable onboarding flow.
-- Depends on:
--   202606210001_create_user_foundation.sql
--   202606210002_add_profile_username.sql
--   202606210003_create_ielts_vocabulary_schema.sql

begin;

create type public.onboarding_flow_state_enum as enum (
  'questionnaire_pending',
  'assessment_pending',
  'placement_finalized',
  'home_ready'
);

alter table public.onboarding_profiles
  add column flow_state public.onboarding_flow_state_enum,
  add column current_question_index smallint;

update public.onboarding_profiles op
set flow_state = case
      when p.onboarding_status in ('completed', 'skipped') then 'home_ready'
      when op.answers ?& array[
        'occupation',
        'ielts_reason',
        'self_reported_level',
        'target_band',
        'prep_timeline'
      ] then 'assessment_pending'
      else 'questionnaire_pending'
    end::public.onboarding_flow_state_enum,
    current_question_index = case
      when p.onboarding_status in ('completed', 'skipped') then 5
      when not (op.answers ? 'occupation') then 0
      when not (op.answers ? 'ielts_reason') then 1
      when not (op.answers ? 'self_reported_level') then 2
      when not (op.answers ? 'target_band') then 3
      when not (op.answers ? 'prep_timeline') then 4
      else 5
    end
from public.profiles p
where p.id = op.user_id;

insert into public.onboarding_profiles (
  user_id,
  questionnaire_version,
  answers,
  flow_state,
  current_question_index,
  completed_at,
  skipped_at
)
select
  p.id,
  '1',
  '{}'::jsonb,
  case
    when p.onboarding_status in ('completed', 'skipped') then
      'home_ready'::public.onboarding_flow_state_enum
    else 'questionnaire_pending'::public.onboarding_flow_state_enum
  end,
  case when p.onboarding_status in ('completed', 'skipped') then 5 else 0 end,
  case when p.onboarding_status = 'completed' then now() else null end,
  case when p.onboarding_status = 'skipped' then now() else null end
from public.profiles p
where not exists (
  select 1
  from public.onboarding_profiles op
  where op.user_id = p.id
);

alter table public.onboarding_profiles
  alter column flow_state set default 'questionnaire_pending',
  alter column flow_state set not null,
  alter column current_question_index set default 0,
  alter column current_question_index set not null,
  add constraint onboarding_question_index_range
    check (current_question_index between 0 and 5);

insert into public.user_level_progress (
  user_id,
  level_number,
  is_unlocked,
  unlocked_at
)
select
  op.user_id,
  1,
  true,
  now()
from public.onboarding_profiles op
where op.flow_state = 'home_ready'
on conflict (user_id, level_number) do update
set is_unlocked = true,
    unlocked_at = coalesce(public.user_level_progress.unlocked_at, excluded.unlocked_at);

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  generated_code text;
  requested_username text;
  requested_nickname text;
  requested_timezone text;
begin
  generated_code :=
    'KQ' || nextval('public.public_user_code_seq'::regclass)::text;

  requested_username :=
    lower(btrim(coalesce(new.raw_user_meta_data ->> 'username', '')));
  if requested_username !~ '^[a-z][a-z0-9_]{2,23}$' then
    raise exception 'Invalid username';
  end if;

  requested_nickname :=
    btrim(coalesce(new.raw_user_meta_data ->> 'nickname', requested_username));
  if char_length(requested_nickname) not between 1 and 36
     or requested_nickname ~ '[@<>/]' then
    requested_nickname := requested_username;
  end if;

  requested_timezone :=
    btrim(coalesce(new.raw_user_meta_data ->> 'timezone', ''));
  if char_length(requested_timezone) not between 1 and 100 then
    requested_timezone := 'UTC';
  end if;

  insert into public.profiles (
    id,
    public_user_code,
    username,
    nickname
  )
  values (
    new.id,
    generated_code,
    requested_username,
    requested_nickname
  );

  insert into public.user_settings (
    user_id,
    reminder_timezone
  )
  values (
    new.id,
    requested_timezone
  );

  insert into public.user_consents (
    user_id,
    document_type,
    document_version
  )
  values
    (
      new.id,
      'terms',
      coalesce(new.raw_user_meta_data ->> 'terms_version', '2026-06-01')
    ),
    (
      new.id,
      'privacy',
      coalesce(new.raw_user_meta_data ->> 'privacy_version', '2026-06-01')
    );

  insert into public.onboarding_profiles (
    user_id,
    questionnaire_version,
    answers,
    flow_state,
    current_question_index
  )
  values (
    new.id,
    '1',
    '{}'::jsonb,
    'questionnaire_pending',
    0
  );

  return new;
end;
$$;

revoke all on function public.handle_new_auth_user() from public;

create or replace function public.build_user_bootstrap_state(target_user_id uuid)
returns jsonb
language sql
security definer
set search_path = ''
stable
as $$
  select jsonb_build_object(
    'profile', jsonb_build_object(
      'id', p.id,
      'public_user_code', p.public_user_code,
      'username', p.username,
      'nickname', p.nickname,
      'avatar_path', p.avatar_path,
      'duck_power', p.duck_power,
      'onboarding_status', p.onboarding_status
    ),
    'flow_state', op.flow_state,
    'current_question_index', op.current_question_index,
    'onboarding_answers', op.answers,
    'placement_status', case
      when op.flow_state = 'home_ready' then 'legacy_level_1'
      when op.flow_state = 'placement_finalized' then 'finalized'
      else 'pending'
    end,
    'current_level', progress.current_level,
    'highest_unlocked_level', progress.highest_unlocked_level
  )
  from public.profiles p
  join public.onboarding_profiles op on op.user_id = p.id
  left join lateral (
    select
      max(ulp.level_number) filter (where ulp.is_unlocked) as highest_unlocked_level,
      coalesce(
        min(ulp.level_number) filter (
          where ulp.is_unlocked and not ulp.is_completed
        ),
        max(ulp.level_number) filter (where ulp.is_unlocked)
      ) as current_level
    from public.user_level_progress ulp
    where ulp.user_id = p.id
  ) progress on true
  where p.id = target_user_id;
$$;

revoke all on function public.build_user_bootstrap_state(uuid) from public;

create or replace function public.get_user_bootstrap_state()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  legacy_status public.onboarding_status_enum;
  result jsonb;
begin
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;

  select onboarding_status
  into legacy_status
  from public.profiles
  where id = current_user_id;

  if not found then
    raise exception 'Profile not found';
  end if;

  insert into public.onboarding_profiles (
    user_id,
    questionnaire_version,
    answers,
    flow_state,
    current_question_index,
    completed_at,
    skipped_at
  )
  values (
    current_user_id,
    '1',
    '{}'::jsonb,
    case
      when legacy_status in ('completed', 'skipped') then
        'home_ready'::public.onboarding_flow_state_enum
      else 'questionnaire_pending'::public.onboarding_flow_state_enum
    end,
    case when legacy_status in ('completed', 'skipped') then 5 else 0 end,
    case when legacy_status = 'completed' then now() else null end,
    case when legacy_status = 'skipped' then now() else null end
  )
  on conflict (user_id) do nothing;

  if exists (
    select 1
    from public.onboarding_profiles
    where user_id = current_user_id
      and flow_state = 'home_ready'
  ) then
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

  result := public.build_user_bootstrap_state(current_user_id);
  return result;
end;
$$;

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

  if current_row.flow_state in ('placement_finalized', 'home_ready') then
    raise exception 'Onboarding is already finalized';
  end if;

  if current_row.questionnaire_version <> btrim(requested_questionnaire_version) then
    raise exception 'Questionnaire version mismatch';
  end if;

  if current_row.current_question_index > requested_expected_question_index then
    if current_row.answers ->> requested_answer_key = requested_answer_value then
      return public.build_user_bootstrap_state(current_user_id);
    end if;
    raise exception 'Answer was already submitted with a different value';
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
        when requested_expected_question_index = 4 then
          'assessment_pending'::public.onboarding_flow_state_enum
        else 'questionnaire_pending'::public.onboarding_flow_state_enum
      end
  where user_id = current_user_id;

  update public.profiles
  set onboarding_status = 'in_progress'
  where id = current_user_id
    and onboarding_status in ('not_started', 'in_progress');

  return public.build_user_bootstrap_state(current_user_id);
end;
$$;

-- The old whole-object RPC could bypass ordered answers and finalization rules.
revoke execute on function public.save_onboarding_profile(
  text,
  jsonb,
  public.onboarding_status_enum
) from authenticated;

revoke all on function public.get_user_bootstrap_state() from public;
grant execute on function public.get_user_bootstrap_state() to authenticated;

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

comment on column public.onboarding_profiles.flow_state is
  'Server-owned routing state. Authenticated clients may only change it through approved RPCs.';
comment on column public.onboarding_profiles.current_question_index is
  'Zero-based index of the next questionnaire answer expected by the server; 5 means complete.';
comment on function public.get_user_bootstrap_state() is
  'Returns and defensively repairs the authenticated user startup state.';
comment on function public.save_onboarding_answer(text, text, text, integer) is
  'Validates and atomically persists one ordered onboarding answer.';

commit;
