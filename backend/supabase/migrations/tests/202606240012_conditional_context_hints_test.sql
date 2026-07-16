\set ON_ERROR_STOP on

begin;

insert into auth.users (id, email, raw_user_meta_data)
values (
  '10000000-0000-0000-0000-000000000012',
  'conditional-hints@example.com',
  '{"username":"conditional_hints","nickname":"Conditional Hints"}'::jsonb
);

select set_config(
  'request.jwt.claim.sub',
  '10000000-0000-0000-0000-000000000012',
  true
);

create temporary table test_senses as
select
  (array_agg(sense_row.id) filter (where word_row.headword = 'old'))[1]
    as ordinary_sense_id,
  (array_agg(sense_row.id) filter (
    where exists (
      select 1
      from public.questions question_row
      where question_row.sense_id = sense_row.id
        and question_row.context_for_multiple_meaning
    )
  ))[1] as multiple_sense_id
from public.word_senses sense_row
join public.words word_row on word_row.id = sense_row.word_id;

do $$
begin
  if (
    select ordinary_sense_id is null or multiple_sense_id is null
    from test_senses
  ) then
    raise exception 'Required ordinary/multiple test senses are missing';
  end if;
end;
$$;

create or replace function pg_temp.insert_test_round(
  p_target_sense_id uuid,
  p_target_level integer
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
  insert into public.practice_sessions (
    user_id,
    level_number,
    session_type,
    status
  )
  values (
    '10000000-0000-0000-0000-000000000012',
    p_target_level,
    'daily',
    'started'
  )
  returning id into v_session_id;

  insert into public.practice_rounds (
    user_id,
    level_number,
    session_id,
    question_count
  )
  values (
    '10000000-0000-0000-0000-000000000012',
    p_target_level,
    v_session_id,
    1
  )
  returning id into v_round_id;

  select
    question_row.id,
    (array_agg(option_row.id) filter (where option_row.is_correct))[1],
    array_agg(option_row.id)
  into v_question_id, v_correct_option_id, v_option_ids
  from public.questions question_row
  join public.question_options option_row
    on option_row.question_id = question_row.id
  where question_row.sense_id = p_target_sense_id
    and question_row.answer_form = 'option'
  group by question_row.id
  limit 1;

  insert into public.practice_round_questions (
    round_id,
    position,
    question_id,
    sense_id,
    question_skill,
    option_ids,
    correct_option_id
  )
  values (
    v_round_id,
    1,
    v_question_id,
    p_target_sense_id,
    'recognition',
    v_option_ids,
    v_correct_option_id
  );

  return v_round_id;
end;
$$;

-- An ordinary word with no mistake history must receive a direct question.
create temporary table ordinary_round as
select pg_temp.insert_test_round(
  ordinary_sense_id,
  (
    select min(level_number)
    from public.level_sense_assignments
    where sense_id = ordinary_sense_id
  )
) as round_id
from test_senses;

do $$
begin
  if exists (
    select 1
    from ordinary_round test_round
    join public.practice_round_questions round_question
      on round_question.round_id = test_round.round_id
    join public.questions question_row
      on question_row.id = round_question.question_id
    where question_row.is_context_hint
  ) then
    raise exception 'Ordinary word incorrectly received a context hint';
  end if;
end;
$$;

update public.practice_rounds
set status = 'abandoned', completed_at = now()
where id = (select round_id from ordinary_round);

-- Three formal wrong answers make the same ordinary word receive its hint.
insert into public.user_sense_mastery (
  user_id,
  sense_id,
  learning_state,
  review_stage,
  seen_count,
  wrong_count,
  difficulty_level
)
select
  '10000000-0000-0000-0000-000000000012',
  ordinary_sense_id,
  'learning',
  0,
  3,
  3,
  3
from test_senses;

create temporary table difficult_round as
select pg_temp.insert_test_round(
  ordinary_sense_id,
  (
    select min(level_number)
    from public.level_sense_assignments
    where sense_id = ordinary_sense_id
  )
) as round_id
from test_senses;

do $$
declare
  v_has_authored_context boolean;
begin
  select exists (
    select 1
    from public.questions question_row
    join test_senses on test_senses.ordinary_sense_id = question_row.sense_id
    where question_row.is_context_hint
      and question_row.is_active
      and question_row.answer_form = 'option'
      and not question_row.human_review
  ) into v_has_authored_context;

  if v_has_authored_context and not exists (
      select 1
      from difficult_round test_round
      join public.practice_round_questions round_question
        on round_question.round_id = test_round.round_id
      join public.questions question_row
        on question_row.id = round_question.question_id
      where question_row.is_context_hint
    ) then
    raise exception 'Repeatedly missed word did not receive a context hint';
  end if;

  if not v_has_authored_context and exists (
      select 1
      from difficult_round test_round
      join public.practice_round_questions round_question
        on round_question.round_id = test_round.round_id
      join public.questions question_row
        on question_row.id = round_question.question_id
      where question_row.is_context_hint
    ) then
    raise exception 'Repeatedly missed word used a context hint even though none was authored';
  end if;
end;
$$;

update public.practice_rounds
set status = 'abandoned', completed_at = now()
where id = (select round_id from difficult_round);

-- A marked multiple-meaning word receives context before any mistakes.
create temporary table multiple_round as
select pg_temp.insert_test_round(
  multiple_sense_id,
  (
    select min(level_number)
    from public.level_sense_assignments
    where sense_id = multiple_sense_id
  )
) as round_id
from test_senses;

do $$
begin
  if not exists (
    select 1
    from multiple_round test_round
    join public.practice_round_questions round_question
      on round_question.round_id = test_round.round_id
    join public.questions question_row
      on question_row.id = round_question.question_id
    where question_row.is_context_hint
      and question_row.context_for_multiple_meaning
  ) then
    raise exception 'Multiple-meaning word did not receive its context question';
  end if;
end;
$$;

rollback;
