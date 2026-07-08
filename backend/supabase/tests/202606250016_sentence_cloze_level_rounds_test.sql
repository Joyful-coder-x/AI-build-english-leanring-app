\set ON_ERROR_STOP on

begin;

insert into auth.users (id, email, raw_user_meta_data)
values
  (
    '10000000-0000-0000-0000-000000000016',
    'cloze-stage-a@example.com',
    '{"username":"cloze_stage_a","nickname":"Cloze Stage A"}'::jsonb
  ),
  (
    '10000000-0000-0000-0000-000000000017',
    'cloze-stage-b@example.com',
    '{"username":"cloze_stage_b","nickname":"Cloze Stage B"}'::jsonb
  ),
  (
    '10000000-0000-0000-0000-000000000018',
    'cloze-round-selection@example.com',
    '{"username":"cloze_round_selection","nickname":"Cloze Round Selection"}'::jsonb
  );

create temporary table cloze_fixture (
  question_id uuid not null,
  sense_id uuid not null
);

with target as (
  select ws.id as sense_id, ws.word_id
  from public.word_senses ws
  join public.level_sense_assignments lsa on lsa.sense_id = ws.id
  where lsa.level_number = 1
  order by lsa.order_in_level
  limit 1
),
inserted as (
  insert into public.questions (
    sense_id,
    word_id,
    question_type_id,
    type_code,
    category,
    answer_form,
    question_type_key,
    stem,
    correct_answer,
    prompt_hint,
    translation_zh,
    expected_time_ms,
    is_active,
    human_review,
    generation_version
  )
  select
    sense_id,
    word_id,
    3,
    3,
    'new_word',
    'keyboard',
    'sentence_cloze_typing',
    'My ______ helped me.',
    'mother',
    '母亲；妈妈',
    '我妈妈帮助了我。',
    12000,
    true,
    false,
    'cloze_runtime_test'
  from target
  returning id, sense_id
)
insert into cloze_fixture
select id, sense_id from inserted;

insert into public.question_options (
  question_id, option_text, target_sense_id, is_correct, sort_order, human_review
)
select question_id, 'mom', sense_id, false, 1, false
from cloze_fixture;

create or replace function pg_temp.make_cloze_round(p_user_id uuid)
returns uuid
language plpgsql
as $$
declare
  v_session_id uuid;
  v_round_id uuid;
  v_question_id uuid;
  v_sense_id uuid;
begin
  select question_id, sense_id into v_question_id, v_sense_id
  from cloze_fixture;

  insert into public.practice_sessions (
    user_id, level_number, session_type, status
  )
  values (p_user_id, 1, 'daily', 'started')
  returning id into v_session_id;

  insert into public.practice_rounds (
    user_id, level_number, session_id, question_count
  )
  values (p_user_id, 1, v_session_id, 1)
  returning id into v_round_id;

  insert into public.practice_round_questions (
    round_id,
    position,
    question_id,
    sense_id,
    question_skill,
    answer_form,
    question_type_key
  )
  values (
    v_round_id,
    1,
    v_question_id,
    v_sense_id,
    'active_recall',
    'keyboard',
    'sentence_cloze_typing'
  );

  return v_round_id;
end;
$$;

create temporary table cloze_round_fixture (
  user_id uuid primary key,
  round_id uuid not null
);

insert into cloze_round_fixture values
  (
    '10000000-0000-0000-0000-000000000016',
    pg_temp.make_cloze_round('10000000-0000-0000-0000-000000000016')
  ),
  (
    '10000000-0000-0000-0000-000000000017',
    pg_temp.make_cloze_round('10000000-0000-0000-0000-000000000017')
  );

grant select on cloze_round_fixture to authenticated;

do $$
declare
  v_generated record;
  v_sense_id uuid;
begin
  select sense_id into v_sense_id from cloze_fixture;

  select * into v_generated
  from public.generate_practice_question(
    v_sense_id,
    1,
    'sentence_cloze_typing'
  );

  if v_generated.answer_form <> 'keyboard'
     or v_generated.question_skill <> 'active_recall'
     or v_generated.generated_payload ->> 'question_type_key' <> 'sentence_cloze_typing'
     or (v_generated.generated_payload ->> 'type_code')::integer <> 3 then
    raise exception 'Generated cloze metadata is wrong: %', v_generated.generated_payload;
  end if;

  if v_generated.correct_answer_payload ->> 'correct_answer' is null then
    raise exception 'Generated cloze is missing a correct answer payload';
  end if;
end;
$$;

select set_config(
  'request.jwt.claim.sub',
  '10000000-0000-0000-0000-000000000016',
  true
);
set local role authenticated;

do $$
declare
  v_result jsonb;
  v_round_id uuid;
begin
  select round_id into v_round_id
  from cloze_round_fixture
  where user_id = auth.uid();

  v_result := public.save_practice_answer(
    v_round_id, 1, 'mom', 100
  );
  if v_result ->> 'action' <> 'near_meaning' then
    raise exception 'Near meaning should not consume an attempt: %', v_result;
  end if;

  v_result := public.save_practice_answer(
    v_round_id, 1, 'wrong', 100
  );
  if v_result ->> 'action' <> 'retry_with_hint'
     or (v_result ->> 'letter_count')::integer <> 6 then
    raise exception 'First wrong should return a six-letter hint: %', v_result;
  end if;

  v_result := public.save_practice_answer(
    v_round_id, 1, 'Mother', 100
  );
  if v_result ->> 'answer_outcome' <> 'assisted_correct' then
    raise exception 'Hint success should be assisted_correct: %', v_result;
  end if;
end;
$$;

reset role;
select set_config(
  'request.jwt.claim.sub',
  '10000000-0000-0000-0000-000000000017',
  true
);
set local role authenticated;

do $$
declare
  v_result jsonb;
  v_round_id uuid;
begin
  select round_id into v_round_id
  from cloze_round_fixture
  where user_id = auth.uid();

  perform public.save_practice_answer(
    v_round_id, 1, 'wrong', 100
  );
  v_result := public.save_practice_answer(
    v_round_id, 1, 'still wrong', 100
  );
  if v_result ->> 'action' <> 'reveal_answer'
     or v_result ->> 'revealed_answer' <> 'mother' then
    raise exception 'Second wrong should reveal the target: %', v_result;
  end if;

  v_result := public.save_practice_answer(
    v_round_id, 1, 'mother', 100
  );
  if v_result ->> 'answer_outcome' <> 'remediation_completed'
     or (v_result ->> 'is_correct')::boolean then
    raise exception 'Memory retype must be remediation, not formal correct: %', v_result;
  end if;
end;
$$;

reset role;

do $$
begin
  if not exists (
    select 1
    from public.practice_round_questions
    where round_id = (
        select round_id from cloze_round_fixture
        where user_id = '10000000-0000-0000-0000-000000000016'
      )
      and answer_outcome = 'assisted_correct'
      and score_points = 0.5
      and near_meaning_count = 1
  ) then
    raise exception 'Assisted outcome was not persisted with 0.5 score';
  end if;

  if not exists (
    select 1
    from public.practice_round_questions
    where round_id = (
        select round_id from cloze_round_fixture
        where user_id = '10000000-0000-0000-0000-000000000017'
      )
      and answer_outcome = 'remediation_completed'
      and is_correct = false
      and score_points = 0
  ) then
    raise exception 'Remediation outcome was not persisted correctly';
  end if;
end;
$$;

rollback;

\echo 'PASS: staged sentence cloze grading and outcome persistence'
