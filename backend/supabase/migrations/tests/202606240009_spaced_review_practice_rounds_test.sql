\set ON_ERROR_STOP on

-- Requires migrations through 202606240009 and the reviewed Levels 1-5 import.
-- All mutations are rolled back.

begin;

insert into auth.users (id, email, raw_user_meta_data)
values
  (
    '10000000-0000-0000-0000-000000000009',
    'spaced-review-a@example.com',
    '{"username":"spaced_review_a","nickname":"Spaced Review A"}'::jsonb
  ),
  (
    '10000000-0000-0000-0000-000000000010',
    'spaced-review-b@example.com',
    '{"username":"spaced_review_b","nickname":"Spaced Review B"}'::jsonb
  );

insert into public.user_level_progress (
  user_id,
  level_number,
  is_unlocked,
  unlocked_at
)
values
  ('10000000-0000-0000-0000-000000000009', 1, true, now()),
  ('10000000-0000-0000-0000-000000000010', 1, true, now());

-- Test helper: create a one-question immutable round around a chosen sense.
create or replace function pg_temp.make_test_round(
  p_user_id uuid,
  p_level_number integer,
  p_sense_id uuid
)
returns uuid
language plpgsql
as $$
declare
  v_session_id uuid;
  v_round_id uuid;
  v_question_id uuid;
  v_correct_option_id uuid;
  v_option_ids uuid[];
begin
  update public.practice_rounds
  set status = 'abandoned',
      completed_at = coalesce(completed_at, now())
  where user_id = p_user_id
    and level_number = p_level_number
    and status = 'started';

  update public.practice_sessions
  set status = 'abandoned',
      completed_at = coalesce(completed_at, now())
  where user_id = p_user_id
    and level_number = p_level_number
    and status = 'started';

  select
    q.id,
    (array_agg(qo.id) filter (where qo.is_correct))[1],
    array_agg(qo.id order by qo.sort_order)
  into v_question_id, v_correct_option_id, v_option_ids
  from public.questions q
  join public.question_options qo on qo.question_id = q.id
  where q.sense_id = p_sense_id
    and q.answer_form = 'option'
    and q.is_active
  group by q.id
  having count(*) >= 2
     and count(*) filter (where qo.is_correct) = 1
  order by q.id
  limit 1;

  if v_question_id is null then
    raise exception 'No option question for test sense %', p_sense_id;
  end if;

  insert into public.practice_sessions (
    user_id,
    level_number,
    session_type,
    status
  )
  values (p_user_id, p_level_number, 'daily', 'started')
  returning id into v_session_id;

  insert into public.practice_rounds (
    user_id,
    level_number,
    session_id,
    question_count
  )
  values (p_user_id, p_level_number, v_session_id, 1)
  returning id into v_round_id;

  insert into public.practice_round_questions (
    round_id,
    position,
    question_id,
    sense_id,
    option_ids,
    correct_option_id
  )
  values (
    v_round_id,
    1,
    v_question_id,
    p_sense_id,
    v_option_ids,
    v_correct_option_id
  );

  return v_round_id;
end;
$$;

-- Schema and exact function signatures.
do $$
begin
  if to_regclass('public.practice_rounds') is null
     or to_regclass('public.practice_round_questions') is null then
    raise exception 'Practice round tables are missing';
  end if;

  if to_regprocedure('public.start_practice_round(integer)') is null
     or to_regprocedure(
       'public.save_practice_answer(uuid,integer,text,integer)'
     ) is null
     or to_regprocedure('public.complete_practice_round(uuid)') is null
     or to_regprocedure('public.get_level_learning_status(integer)') is null then
    raise exception 'One or more practice-round RPCs are missing';
  end if;
end;
$$;

-- start_practice_round creates/resumes a fixed round without exposing answers.
select set_config(
  'request.jwt.claim.sub',
  '10000000-0000-0000-0000-000000000009',
  true
);
set local role authenticated;

create temporary table first_round_result as
select public.start_practice_round(1) as payload;

do $$
declare
  v_payload jsonb;
  v_round_id uuid;
begin
  select payload into v_payload from first_round_result;
  v_round_id := (v_payload ->> 'round_id')::uuid;

  if (v_payload ->> 'question_count')::integer not between 1 and 20 then
    raise exception 'Round size is outside 1..20';
  end if;

  if v_payload::text like '%correct_option_id%'
     or v_payload::text like '%"is_correct"%' then
    raise exception 'Round payload exposed answer correctness';
  end if;

  if (
    select count(*)
    from jsonb_array_elements(v_payload -> 'questions')
  ) <> (
    select count(distinct question ->> 'sense_id')
    from jsonb_array_elements(v_payload -> 'questions') question
  ) then
    raise exception 'Round contains duplicate senses';
  end if;

  if (public.start_practice_round(1) ->> 'round_id')::uuid <> v_round_id then
    raise exception 'Starting again did not resume the active round';
  end if;
end;
$$;

reset role;

-- User B must not see User A's round, and direct snapshot access is denied.
select set_config(
  'request.jwt.claim.sub',
  '10000000-0000-0000-0000-000000000010',
  true
);
set local role authenticated;

do $$
begin
  if exists (
    select 1
    from public.practice_rounds
    where user_id = '10000000-0000-0000-0000-000000000009'
  ) then
    raise exception 'Cross-user round was visible';
  end if;

  begin
    perform count(*) from public.practice_round_questions;
    raise exception 'Direct snapshot read unexpectedly succeeded';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

reset role;

-- Choose a stable Level 1 sense for transition tests.
create temporary table selected_test_sense as
select lsa.sense_id
from public.level_sense_assignments lsa
where lsa.level_number = 1
  and lsa.placement_type = 'new'
  and exists (
    select 1
    from public.questions q
    join public.question_options qo on qo.question_id = q.id
    where q.sense_id = lsa.sense_id
      and q.answer_form = 'option'
      and q.is_active
    group by q.id
    having count(*) >= 2
       and count(*) filter (where qo.is_correct) = 1
  )
order by lsa.order_in_level
limit 1;

-- First correct answer now counts as the first spaced success and schedules
-- the one-day review.
delete from public.practice_rounds
where user_id = '10000000-0000-0000-0000-000000000009'
  and status = 'started';

create temporary table transition_rounds (
  label text primary key,
  round_id uuid not null
);

insert into transition_rounds
select
  'first_correct',
  pg_temp.make_test_round(
    '10000000-0000-0000-0000-000000000009',
    1,
    sense_id
  )
from selected_test_sense;

select set_config(
  'request.jwt.claim.sub',
  '10000000-0000-0000-0000-000000000009',
  true
);

do $$
declare
  v_round_id uuid;
  v_answer text;
begin
  select round_id into v_round_id
  from transition_rounds where label = 'first_correct';

  select correct_option_id::text into v_answer
  from public.practice_round_questions
  where round_id = v_round_id and position = 1;

  perform public.save_practice_answer(v_round_id, 1, v_answer, 1000);
end;
$$;

do $$
declare
  v_sense_id uuid;
  v_due timestamptz;
begin
  select sense_id into v_sense_id from selected_test_sense;

  select next_due_at into v_due
  from public.user_sense_mastery
  where user_id = '10000000-0000-0000-0000-000000000009'
    and sense_id = v_sense_id;

  if not exists (
    select 1
    from public.user_sense_mastery
    where user_id = '10000000-0000-0000-0000-000000000009'
      and sense_id = v_sense_id
      and learning_state = 'learning'
      and review_stage = 1
      and spaced_success_count = 1
      and mastered_at is null
  ) then
    raise exception 'First correct answer produced the wrong memory state';
  end if;

  if v_due < now() + interval '23 hours 59 minutes'
     or v_due > now() + interval '24 hours 1 minute' then
    raise exception 'First correct answer did not schedule about one day';
  end if;
end;
$$;

-- An early second correct answer must not advance the stage.
insert into transition_rounds
select
  'early_correct',
  pg_temp.make_test_round(
    '10000000-0000-0000-0000-000000000009',
    1,
    sense_id
  )
from selected_test_sense;

do $$
declare
  v_round_id uuid;
  v_answer text;
begin
  select round_id into v_round_id
  from transition_rounds where label = 'early_correct';

  select correct_option_id::text into v_answer
  from public.practice_round_questions
  where round_id = v_round_id and position = 1;

  perform public.save_practice_answer(v_round_id, 1, v_answer, 900);
end;
$$;

do $$
begin
  if not exists (
    select 1
    from public.user_sense_mastery usm
    join selected_test_sense sts on sts.sense_id = usm.sense_id
    where usm.user_id = '10000000-0000-0000-0000-000000000009'
      and usm.review_stage = 1
      and usm.spaced_success_count = 1
      and usm.learning_state = 'learning'
  ) then
    raise exception 'Early correct answer incorrectly advanced review';
  end if;
end;
$$;

-- Make the one-day review due, then verify it advances to seven-day review.
update public.user_sense_mastery
set next_due_at = now() - interval '1 second'
where user_id = '10000000-0000-0000-0000-000000000009'
  and sense_id = (select sense_id from selected_test_sense);

insert into transition_rounds
select
  'due_correct',
  pg_temp.make_test_round(
    '10000000-0000-0000-0000-000000000009',
    1,
    sense_id
  )
from selected_test_sense;

do $$
declare
  v_round_id uuid;
  v_answer text;
begin
  select round_id into v_round_id
  from transition_rounds where label = 'due_correct';

  select correct_option_id::text into v_answer
  from public.practice_round_questions
  where round_id = v_round_id and position = 1;

  perform public.save_practice_answer(v_round_id, 1, v_answer, 800);
end;
$$;

do $$
begin
  if not exists (
    select 1
    from public.user_sense_mastery usm
    join selected_test_sense sts on sts.sense_id = usm.sense_id
    where usm.user_id = '10000000-0000-0000-0000-000000000009'
      and usm.review_stage = 2
      and usm.spaced_success_count = 2
      and usm.learning_state = 'reviewing'
      and usm.mastered_at is null
  ) then
    raise exception 'Due one-day review did not enter reviewing';
  end if;
end;
$$;

-- recent_results retains only the latest six formal answers.
do $$
begin
  if public.append_recent_formal_result(
    array[true, false, true, false, true, false],
    true
  ) <> array[false, true, false, true, false, true] then
    raise exception 'Recent-result window did not retain the latest six';
  end if;
end;
$$;

-- A wrong answer at thirty-day regresses only to seven-day and reactivates the
-- mistake index without deleting historical counts.
update public.user_sense_mastery
set learning_state = 'reviewing',
    review_stage = 4,
    correct_count = 5,
    seen_count = 5,
    consecutive_correct_count = 3,
    recent_results = array[true, true, true, true, true],
    spaced_success_count = 4,
    next_due_at = now() - interval '1 second',
    mastered_at = null
where user_id = '10000000-0000-0000-0000-000000000009'
  and sense_id = (select sense_id from selected_test_sense);

insert into public.mistake_senses (
  user_id,
  sense_id,
  wrong_count,
  first_wrong_at,
  last_wrong_at,
  is_active,
  resolved_at
)
select
  '10000000-0000-0000-0000-000000000009',
  sense_id,
  1,
  now() - interval '2 days',
  now() - interval '2 days',
  false,
  now() - interval '1 day'
from selected_test_sense
on conflict (user_id, sense_id) do update
set is_active = false,
    resolved_at = now() - interval '1 day';

insert into transition_rounds
select
  'wrong_at_thirty_day',
  pg_temp.make_test_round(
    '10000000-0000-0000-0000-000000000009',
    1,
    sense_id
  )
from selected_test_sense;

do $$
declare
  v_round_id uuid;
  v_wrong_answer text;
begin
  select round_id into v_round_id
  from transition_rounds where label = 'wrong_at_thirty_day';

  select option_id::text into v_wrong_answer
  from (
    select unnest(option_ids) as option_id, correct_option_id
    from public.practice_round_questions
    where round_id = v_round_id and position = 1
  ) options
  where option_id <> correct_option_id
  limit 1;

  perform public.save_practice_answer(v_round_id, 1, v_wrong_answer, 1200);
end;
$$;

do $$
begin
  if not exists (
    select 1
    from public.user_sense_mastery usm
    join selected_test_sense sts on sts.sense_id = usm.sense_id
    where usm.user_id = '10000000-0000-0000-0000-000000000009'
      and usm.review_stage = 3
      and usm.learning_state = 'reviewing'
      and usm.correct_count = 5
      and usm.consecutive_correct_count = 0
      and usm.wrong_count >= 1
      and usm.mastered_at is null
  ) then
    raise exception 'Thirty-day wrong-answer regression was incorrect';
  end if;

  if not exists (
    select 1
    from public.mistake_senses ms
    join selected_test_sense sts on sts.sense_id = ms.sense_id
    where ms.user_id = '10000000-0000-0000-0000-000000000009'
      and ms.is_active
      and ms.resolved_at is null
  ) then
    raise exception 'Resolved mistake was not reactivated';
  end if;
end;
$$;

-- Level 1 completion uses 41/45 target new senses and unlocks Level 2.
delete from public.user_sense_mastery
where user_id = '10000000-0000-0000-0000-000000000009';

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
  '10000000-0000-0000-0000-000000000009',
  lsa.sense_id,
  case
    when lsa.order_in_level <= 41
      then 'reviewing'::public.sense_learning_state_enum
    else 'learning'::public.sense_learning_state_enum
  end,
  case when lsa.order_in_level <= 41 then 2 else 1 end,
  2,
  case when lsa.order_in_level <= 41 then 2 else 1 end,
  case when lsa.order_in_level <= 41 then 1 else 0 end,
  now() - interval '20 minutes',
  now() - interval '20 minutes',
  now(),
  now(),
  now() + interval '1 day'
from public.level_sense_assignments lsa
where lsa.level_number = 1
  and lsa.placement_type = 'new';

do $$
begin
  if (
    select count(*)
    from public.level_sense_assignments
    where level_number = 1
      and placement_type = 'new'
  ) <> 45 then
    raise exception 'This test requires exactly 45 Level 1 target new senses';
  end if;

  if not public.refresh_level_completion(
    '10000000-0000-0000-0000-000000000009',
    1
  ) then
    raise exception '41/45 qualifying senses did not complete Level 1';
  end if;

  if not exists (
    select 1
    from public.user_level_progress
    where user_id = '10000000-0000-0000-0000-000000000009'
      and level_number = 2
      and is_unlocked
  ) then
    raise exception 'Completing Level 1 did not unlock Level 2';
  end if;
end;
$$;

-- Reducing the qualifying count to 40 must fail for another user.
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
  '10000000-0000-0000-0000-000000000010',
  lsa.sense_id,
  case
    when lsa.order_in_level <= 40
      then 'reviewing'::public.sense_learning_state_enum
    else 'learning'::public.sense_learning_state_enum
  end,
  case when lsa.order_in_level <= 40 then 2 else 1 end,
  2,
  case when lsa.order_in_level <= 40 then 2 else 1 end,
  case when lsa.order_in_level <= 40 then 1 else 0 end,
  now() - interval '20 minutes',
  now() - interval '20 minutes',
  now(),
  now(),
  now() + interval '1 day'
from public.level_sense_assignments lsa
where lsa.level_number = 1
  and lsa.placement_type = 'new';

do $$
begin
  if public.refresh_level_completion(
    '10000000-0000-0000-0000-000000000010',
    1
  ) then
    raise exception '40/45 qualifying senses incorrectly completed Level 1';
  end if;
end;
$$;

-- More than 20 overdue reviews suppresses all new content.
delete from public.user_sense_mastery
where user_id = '10000000-0000-0000-0000-000000000010'
  and sense_id in (
    select sense_id
    from public.level_sense_assignments
    where level_number = 1
      and placement_type = 'new'
    order by order_in_level
    offset 21
  );

update public.user_sense_mastery
set next_due_at = now() - interval '1 minute',
    learning_state = 'reviewing',
    review_stage = 2
where user_id = '10000000-0000-0000-0000-000000000010'
  and sense_id in (
    select sense_id
    from public.level_sense_assignments
    where level_number = 1
      and placement_type = 'new'
    order by order_in_level
    limit 21
  );

delete from public.practice_rounds
where user_id = '10000000-0000-0000-0000-000000000010'
  and status = 'started';

select set_config(
  'request.jwt.claim.sub',
  '10000000-0000-0000-0000-000000000010',
  true
);
set local role authenticated;

do $$
declare
  v_payload jsonb;
begin
  v_payload := public.start_practice_round(1);

  if (v_payload ->> 'new_sense_count')::integer <> 0 then
    raise exception 'New senses were included despite more than 20 due reviews';
  end if;

  if (v_payload ->> 'question_count')::integer > 20 then
    raise exception 'Due-review round exceeded 20 questions';
  end if;
end;
$$;

reset role;

-- Completion is idempotent: reward and session count change only once.
delete from public.practice_rounds
where user_id = '10000000-0000-0000-0000-000000000009'
  and status = 'started';

create temporary table idempotency_round as
select pg_temp.make_test_round(
  '10000000-0000-0000-0000-000000000009',
  1,
  sense_id
) as round_id
from selected_test_sense;

create temporary table before_completion as
select
  duck_power,
  (
    select completed_session_count
    from public.user_level_progress
    where user_id = '10000000-0000-0000-0000-000000000009'
      and level_number = 1
  ) as completed_session_count
from public.profiles
where id = '10000000-0000-0000-0000-000000000009';

select set_config(
  'request.jwt.claim.sub',
  '10000000-0000-0000-0000-000000000009',
  true
);

do $$
declare
  v_round_id uuid;
  v_answer text;
begin
  select round_id into v_round_id from idempotency_round;
  select correct_option_id::text into v_answer
  from public.practice_round_questions
  where round_id = v_round_id and position = 1;

  perform public.save_practice_answer(v_round_id, 1, v_answer, 700);
  perform public.complete_practice_round(v_round_id);
  perform public.complete_practice_round(v_round_id);
end;
$$;

do $$
declare
  v_before_power integer;
  v_before_sessions integer;
  v_after_power integer;
  v_after_sessions integer;
begin
  select duck_power, completed_session_count
  into v_before_power, v_before_sessions
  from before_completion;

  select
    p.duck_power,
    ulp.completed_session_count
  into v_after_power, v_after_sessions
  from public.profiles p
  join public.user_level_progress ulp
    on ulp.user_id = p.id
   and ulp.level_number = 1
  where p.id = '10000000-0000-0000-0000-000000000009';

  if v_after_power <> v_before_power + 1 then
    raise exception 'Round reward was duplicated or missing';
  end if;

  if v_after_sessions <> v_before_sessions + 1 then
    raise exception 'Completed-session count was duplicated or missing';
  end if;
end;
$$;

rollback;
