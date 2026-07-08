\set ON_ERROR_STOP on

-- Phase 1 evidence test: one real generated round must persist the learning
-- audit trail the app claims in the demo.
--
-- Requires the complete Band 4.0 content package. All mutations roll back.

begin;

insert into auth.users (id, email, raw_user_meta_data)
values (
  '10000000-0000-0000-0000-000000000029',
  'phase1-logging-evidence@example.com',
  '{"username":"phase1_logging","nickname":"Phase 1 Logging"}'::jsonb
);

insert into public.user_level_progress (
  user_id,
  level_number,
  is_unlocked,
  unlocked_at
)
values (
  '10000000-0000-0000-0000-000000000029',
  1,
  true,
  now()
)
on conflict (user_id, level_number) do update
set is_unlocked = true,
    unlocked_at = coalesce(public.user_level_progress.unlocked_at, now());

select set_config(
  'request.jwt.claim.sub',
  '10000000-0000-0000-0000-000000000029',
  true
);

create temporary table before_profile as
select
  duck_power,
  current_streak_days,
  longest_streak_days,
  last_practice_date
from public.profiles
where id = '10000000-0000-0000-0000-000000000029';

create temporary table before_level_progress as
select completed_session_count
from public.user_level_progress
where user_id = '10000000-0000-0000-0000-000000000029'
  and level_number = 1;

create temporary table started_round as
select public.start_practice_round(1) as payload;

create temporary table selected_round as
select (payload ->> 'round_id')::uuid as round_id
from started_round;

create temporary table answer_plan as
select
  rq.position,
  rq.sense_id,
  rq.question_id,
  rq.answer_form,
  case
    when rq.position = 1 and rq.answer_form = 'option' then (
      select option_id::text
      from unnest(rq.option_ids) option_id
      where option_id <> rq.correct_option_id
      limit 1
    )
    when rq.answer_form = 'option' then rq.correct_option_id::text
    when rq.position = 1 then '__wrong__'
    else coalesce(
      rq.correct_answer_payload ->> 'correct_answer',
      rq.generated_payload ->> 'correct_answer',
      rq.generated_payload ->> 'headword'
    )
  end as answer_text,
  rq.position = 1 as should_be_wrong
from public.practice_round_questions rq
join selected_round sr on sr.round_id = rq.round_id
order by rq.position;

do $$
declare
  v_row record;
  v_result jsonb;
  v_completion jsonb;
  v_round_id uuid;
  v_question_count integer;
  v_correct_count integer;
  v_wrong_sense_id uuid;
begin
  select round_id into v_round_id from selected_round;

  select count(*) into v_question_count
  from answer_plan;

  if v_question_count not between 1 and 20 then
    raise exception 'Generated round has invalid question count: %', v_question_count;
  end if;

  for v_row in
    select * from answer_plan order by position
  loop
    if v_row.answer_text is null then
      raise exception 'No answer text planned for position %', v_row.position;
    end if;

    v_result := public.save_practice_answer(
      v_round_id,
      v_row.position,
      v_row.answer_text,
      1000 + v_row.position
    );

    if v_row.should_be_wrong and (v_result ->> 'is_correct')::boolean is true then
      raise exception 'Position 1 should have been wrong: %', v_result;
    end if;
  end loop;

  v_completion := public.complete_practice_round(v_round_id);
  v_correct_count := (v_completion ->> 'correct_count')::integer;

  if (v_completion ->> 'question_count')::integer <> v_question_count then
    raise exception 'Completion question count mismatch: %', v_completion;
  end if;

  if v_correct_count <> v_question_count - 1 then
    raise exception 'Expected exactly one wrong answer, got completion %', v_completion;
  end if;

  select sense_id into v_wrong_sense_id
  from answer_plan
  where should_be_wrong;

  if not exists (
    select 1
    from public.practice_sessions ps
    join public.practice_rounds pr on pr.session_id = ps.id
    where pr.id = v_round_id
      and ps.user_id = '10000000-0000-0000-0000-000000000029'
      and ps.status = 'completed'
      and ps.total_count = v_question_count
      and ps.correct_count = v_correct_count
      and ps.duck_power_earned = v_correct_count
      and pr.status = 'completed'
      and pr.correct_count = v_correct_count
  ) then
    raise exception 'Completed session/round logging is missing or wrong';
  end if;

  if (
    select count(*)
    from public.practice_round_questions
    where round_id = v_round_id
      and answered_at is not null
  ) <> v_question_count then
    raise exception 'Not all round question snapshots were answered';
  end if;

  if (
    select count(*)
    from public.practice_answers
    where user_id = '10000000-0000-0000-0000-000000000029'
  ) <> v_question_count then
    raise exception 'practice_answers did not log one row per answer';
  end if;

  if (
    select count(*)
    from public.question_attempts
    where user_id = '10000000-0000-0000-0000-000000000029'
      and round_id = v_round_id
  ) <> v_question_count then
    raise exception 'question_attempts did not log one row per answer';
  end if;

  if (
    select count(*)
    from public.user_sense_mastery
    where user_id = '10000000-0000-0000-0000-000000000029'
      and sense_id in (select sense_id from answer_plan)
  ) <> v_question_count then
    raise exception 'user_sense_mastery does not cover all practiced senses';
  end if;

  if not exists (
    select 1
    from public.mistake_senses
    where user_id = '10000000-0000-0000-0000-000000000029'
      and sense_id = v_wrong_sense_id
      and is_active
      and wrong_count >= 1
  ) then
    raise exception 'Wrong answer did not create an active mistake_senses row';
  end if;

  if not exists (
    select 1
    from public.profiles p
    cross join before_profile bp
    where p.id = '10000000-0000-0000-0000-000000000029'
      and p.duck_power = bp.duck_power + v_correct_count
      and p.current_streak_days >= 1
      and p.longest_streak_days >= p.current_streak_days
      and p.last_practice_date is not null
  ) then
    raise exception 'Profile reward/streak fields were not updated';
  end if;

  if not exists (
    select 1
    from public.user_level_progress ulp
    cross join before_level_progress blp
    where ulp.user_id = '10000000-0000-0000-0000-000000000029'
      and ulp.level_number = 1
      and ulp.completed_session_count = blp.completed_session_count + 1
      and ulp.progress > 0
  ) then
    raise exception 'Level progress was not updated after completion';
  end if;
end;
$$;

rollback;

