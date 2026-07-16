\set ON_ERROR_STOP on

-- Requires the complete band_4_0_v1 import. All mutations roll back.

begin;

insert into auth.users (id, email, raw_user_meta_data)
values (
  '10000000-0000-0000-0000-000000000054',
  'band4-runtime@example.com',
  '{"username":"band4_runtime","nickname":"Band 4 Runtime"}'::jsonb
);

insert into public.user_level_progress (
  user_id,
  level_number,
  is_unlocked,
  unlocked_at
)
select
  '10000000-0000-0000-0000-000000000054',
  level_number,
  true,
  now()
from public.levels
where band_id = 1;

select set_config(
  'request.jwt.claim.sub',
  '10000000-0000-0000-0000-000000000054',
  true
);

-- Every first-band level must create a non-empty, answer-safe fixed round.
do $$
declare
  v_level integer;
  v_payload jsonb;
  v_round_id uuid;
  v_expected integer;
  v_actual integer;
begin
  for v_level in select level_number from public.levels where band_id = 1 order by level_number loop
    select new_sense_target into v_expected
    from public.levels
    where level_number = v_level;

    select count(*) into v_actual
    from public.level_sense_assignments
    where level_number = v_level
      and placement_type = 'new';

    if v_actual <> v_expected then
      raise exception 'Level % target/assignment mismatch: %/%',
        v_level, v_expected, v_actual;
    end if;

    v_payload := public.start_practice_round(v_level);
    v_round_id := (v_payload ->> 'round_id')::uuid;

    if (v_payload ->> 'question_count')::integer not between 1 and 20 then
      raise exception 'Level % generated invalid round size', v_level;
    end if;

    if jsonb_array_length(v_payload -> 'questions')
       <> (v_payload ->> 'question_count')::integer then
      raise exception 'Level % payload count mismatch', v_level;
    end if;

    if v_payload::text like '%correct_option_id%'
       or v_payload::text like '%"is_correct"%' then
      raise exception 'Level % exposed answer correctness', v_level;
    end if;

    if (
      select count(*)
      from jsonb_array_elements(v_payload -> 'questions')
    ) <> (
      select count(distinct question ->> 'sense_id')
      from jsonb_array_elements(v_payload -> 'questions') question
    ) then
      raise exception 'Level % round contains duplicate senses', v_level;
    end if;

    update public.practice_rounds
    set status = 'abandoned',
        completed_at = now()
    where id = v_round_id;

    update public.practice_sessions
    set status = 'abandoned',
        completed_at = now()
    where id = (
      select session_id from public.practice_rounds where id = v_round_id
    );
  end loop;
end;
$$;

-- Every imported sense has two examples. Deep Levels 1-5 have 12 imported
-- questions per sense; lightweight compact Band 4 Levels 6+ have 3.
do $$
begin
  if exists (
    select lsa.sense_id
    from public.level_sense_assignments lsa
    left join public.examples e on e.sense_id = lsa.sense_id
    join public.levels l on l.level_number = lsa.level_number
    where l.band_id = 1
      and lsa.placement_type = 'new'
    group by lsa.sense_id
    having count(e.id) <> 2
  ) then
    raise exception 'A Band 4 sense does not have exactly two examples';
  end if;

  if exists (
    select lsa.sense_id
    from public.level_sense_assignments lsa
    left join public.questions q on q.sense_id = lsa.sense_id
      and q.generation_version in (
        'level_1_5_reviewed_v1',
        'level_1_5_eight_type_v2',
        'band_4_0_ai_reviewed_v1'
      )
    join public.levels l on l.level_number = lsa.level_number
    where l.band_id = 1
      and lsa.placement_type = 'new'
    group by lsa.level_number, lsa.sense_id
    having count(q.id) <> case when lsa.level_number <= 5 then 12 else 3 end
  ) then
    raise exception 'A Band 4 sense has the wrong question count for its level slice';
  end if;
end;
$$;

-- Configurable completion: Level 6 has a compact 45-ish target, so 90% delayed
-- successes complete it and unlock Level 7.
delete from public.user_level_progress
where user_id = '10000000-0000-0000-0000-000000000054'
  and level_number = 7;

insert into public.user_sense_mastery (
  user_id,
  sense_id,
  learning_state,
  review_stage,
  seen_count,
  correct_count,
  spaced_success_count,
  first_seen_at,
  first_correct_at,
  last_seen_at,
  last_correct_at,
  next_due_at
)
select
  '10000000-0000-0000-0000-000000000054',
  lsa.sense_id,
  case
    when lsa.order_in_level <= ceil(l.new_sense_target * 0.90)
      then 'reviewing'::public.sense_learning_state_enum
    else 'learning'::public.sense_learning_state_enum
  end,
  case
    when lsa.order_in_level <= ceil(l.new_sense_target * 0.90) then 2
    else 1
  end,
  2,
  case
    when lsa.order_in_level <= ceil(l.new_sense_target * 0.90) then 2
    else 1
  end,
  case
    when lsa.order_in_level <= ceil(l.new_sense_target * 0.90) then 1
    else 0
  end,
  now() - interval '20 minutes',
  now() - interval '20 minutes',
  now(),
  now(),
  now() + interval '1 day'
from public.level_sense_assignments lsa
join public.levels l on l.level_number = lsa.level_number
where lsa.level_number = 6
  and lsa.placement_type = 'new';

do $$
begin
  if (
    select new_sense_target from public.levels where level_number = 6
  ) not between 40 and 50 then
    raise exception 'Expected generated Level 6 target to be 45-ish';
  end if;

  if not public.refresh_level_completion(
    '10000000-0000-0000-0000-000000000054',
    6
  ) then
    raise exception 'Configurable 90%% completion failed for Level 6';
  end if;

  if not exists (
    select 1
    from public.user_level_progress
    where user_id = '10000000-0000-0000-0000-000000000054'
      and level_number = 7
      and is_unlocked
  ) then
    raise exception 'Level 6 completion did not unlock Level 7';
  end if;
end;
$$;

-- Completing the final Band 4 level must not bypass the Band 4 -> 4.5 upgrade exam.
delete from public.user_level_progress
where user_id = '10000000-0000-0000-0000-000000000054'
  and level_number = (
    select min(level_number) from public.levels where band_id = 2
  );

insert into public.user_sense_mastery (
  user_id,
  sense_id,
  learning_state,
  review_stage,
  seen_count,
  correct_count,
  spaced_success_count,
  first_seen_at,
  first_correct_at,
  last_seen_at,
  last_correct_at,
  next_due_at
)
select
  '10000000-0000-0000-0000-000000000054',
  lsa.sense_id,
  'reviewing',
  2,
  2,
  2,
  1,
  now() - interval '20 minutes',
  now() - interval '20 minutes',
  now(),
  now(),
  now() + interval '1 day'
from public.level_sense_assignments lsa
where lsa.level_number = (
    select max(level_number) from public.levels where band_id = 1
  )
  and lsa.placement_type = 'new';

do $$
declare
  v_band4_last integer;
  v_band45_first integer;
begin
  select max(level_number) into v_band4_last from public.levels where band_id = 1;
  select min(level_number) into v_band45_first from public.levels where band_id = 2;

  if not public.refresh_level_completion(
    '10000000-0000-0000-0000-000000000054',
    v_band4_last
  ) then
    raise exception 'Final Band 4 Level % did not complete', v_band4_last;
  end if;

  if exists (
    select 1
    from public.user_level_progress
    where user_id = '10000000-0000-0000-0000-000000000054'
      and level_number = v_band45_first
      and is_unlocked
  ) then
    raise exception 'Final Band 4 Level % bypassed the required upgrade exam',
      v_band4_last;
  end if;
end;
$$;

rollback;
