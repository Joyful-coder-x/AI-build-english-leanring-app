\set ON_ERROR_STOP on

-- Requires the complete Band 4.0 content package.
-- Proves start/save/complete_overall_assessment: stratifies by skill,
-- grades server-side, never touches user_sense_mastery, and produces
-- per-skill band estimates. All mutations are rolled back.

begin;

insert into auth.users (id, email, raw_user_meta_data)
values (
  '10000000-0000-0000-0000-000000000035',
  'overall-assessment@example.com',
  '{"username":"overall_assessment","nickname":"Overall Assessment"}'::jsonb
);

select set_config(
  'request.jwt.claim.sub',
  '10000000-0000-0000-0000-000000000035',
  true
);

create temporary table before_mastery_count as
select count(*) as n from public.user_sense_mastery
where user_id = '10000000-0000-0000-0000-000000000035';

create temporary table started_attempt as
select public.start_overall_assessment() as payload;

create temporary table selected_attempt as
select (payload ->> 'attempt_id')::uuid as attempt_id
from started_attempt;

create temporary table answer_plan as
select
  aq.position,
  aq.answer_form,
  aq.skill_category,
  case
    when aq.position = 1 and aq.answer_form = 'option' then (
      select option_id::text
      from unnest(aq.option_ids) option_id
      where option_id <> aq.correct_option_id
      limit 1
    )
    when aq.answer_form = 'option' then aq.correct_option_id::text
    when aq.position = 1 then '__wrong__'
    else coalesce(
      aq.correct_answer_payload ->> 'correct_answer',
      aq.generated_payload ->> 'correct_answer',
      aq.generated_payload ->> 'headword'
    )
  end as answer_text,
  aq.position = 1 as should_be_wrong
from public.overall_assessment_questions aq
join selected_attempt sa on sa.attempt_id = aq.attempt_id
order by aq.position;

do $$
declare
  v_row record;
  v_attempt_id uuid;
  v_question_count integer;
  v_completion jsonb;
  v_correct_count integer;
  v_mastery_before integer;
  v_mastery_after integer;
  v_listening_total integer;
  v_reading_total integer;
  v_speaking_total integer;
  v_spelling_total integer;
begin
  select attempt_id into v_attempt_id from selected_attempt;
  select n into v_mastery_before from before_mastery_count;

  select count(*) into v_question_count from answer_plan;

  if v_question_count < 60 then
    raise exception 'Overall assessment generated too few questions: %', v_question_count;
  end if;

  select
    count(*) filter (where skill_category = 'listening'),
    count(*) filter (where skill_category = 'reading'),
    count(*) filter (where skill_category = 'speaking'),
    count(*) filter (where skill_category = 'spelling')
  into v_listening_total, v_reading_total, v_speaking_total, v_spelling_total
  from answer_plan;

  if v_listening_total = 0 or v_reading_total = 0 or v_speaking_total = 0 or v_spelling_total = 0 then
    raise exception 'Expected all 4 skill categories represented, got L=% R=% S=% W=%',
      v_listening_total, v_reading_total, v_speaking_total, v_spelling_total;
  end if;

  for v_row in select * from answer_plan order by position loop
    if v_row.answer_text is null then
      raise exception 'No answer text planned for position %', v_row.position;
    end if;

    perform public.save_overall_assessment_answer(
      v_attempt_id,
      v_row.position,
      v_row.answer_text,
      1000 + v_row.position
    );
  end loop;

  v_completion := public.complete_overall_assessment(v_attempt_id);
  v_correct_count := (v_completion ->> 'correct_count')::integer;

  if v_correct_count <> v_question_count - 1 then
    raise exception 'Expected exactly one wrong answer, got completion %', v_completion;
  end if;

  if (v_completion ->> 'listening_band') is null
    or (v_completion ->> 'reading_band') is null
    or (v_completion ->> 'speaking_band') is null
    or (v_completion ->> 'spelling_band') is null then
    raise exception 'Expected all 4 skill bands to be computed: %', v_completion;
  end if;

  if (v_completion ->> 'overall_band')::numeric < 7.0 then
    raise exception 'Near-perfect score should map to a high band estimate, got %', v_completion;
  end if;

  select n into v_mastery_after from (
    select count(*) as n from public.user_sense_mastery
    where user_id = '10000000-0000-0000-0000-000000000035'
  ) t;

  if v_mastery_after <> v_mastery_before then
    raise exception 'Overall assessment must not touch user_sense_mastery: before=% after=%',
      v_mastery_before, v_mastery_after;
  end if;

  if exists (
    select 1 from public.overall_assessment_attempts
    where id = v_attempt_id and status <> 'completed'
  ) then
    raise exception 'Attempt should be marked completed';
  end if;
end;
$$;

rollback;
