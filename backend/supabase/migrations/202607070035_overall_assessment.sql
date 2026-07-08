-- Phase 1 Feature H: home-page Overall Assessment. 100 questions stratified
-- 25 per IELTS skill (listening/reading/speaking/spelling), drawn from ALL
-- available bands/levels (Phase 1 = Band 4.0 only). Purely diagnostic: never
-- touches user_sense_mastery or level/band progression. Mirrors the
-- band_upgrade_attempts pattern in migration 202607060026 but stratifies by
-- skill_category (migration 202607070032) instead of question type rotation,
-- since the diagnostic needs to report per-IELTS-skill, not per-type.

create table public.overall_assessment_attempts (
  id                uuid primary key default gen_random_uuid(),
  user_id           uuid not null references public.profiles(id) on delete cascade,
  status            text not null default 'started',
  question_count    smallint not null default 100,
  correct_count     smallint,
  listening_correct smallint,
  listening_total   smallint,
  reading_correct   smallint,
  reading_total     smallint,
  speaking_correct  smallint,
  speaking_total    smallint,
  spelling_correct  smallint,
  spelling_total    smallint,
  listening_band    numeric(3,1),
  reading_band      numeric(3,1),
  speaking_band     numeric(3,1),
  spelling_band     numeric(3,1),
  overall_band      numeric(3,1),
  started_at        timestamptz not null default now(),
  completed_at      timestamptz,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),

  constraint overall_assessment_status_valid
    check (status in ('started', 'completed', 'abandoned')),
  constraint overall_assessment_question_count_valid
    check (question_count = 100)
);

create unique index overall_assessment_one_started_per_user
  on public.overall_assessment_attempts (user_id)
  where status = 'started';

create table public.overall_assessment_questions (
  attempt_id        uuid not null references public.overall_assessment_attempts(id) on delete cascade,
  position          smallint not null,
  question_id       uuid not null references public.questions(id),
  sense_id          uuid not null references public.word_senses(id),
  question_type_key text not null,
  skill_category    text not null,
  answer_form       text not null,
  option_ids        uuid[] not null default '{}',
  correct_option_id uuid,
  generated_payload jsonb not null default '{}'::jsonb,
  correct_answer_payload jsonb not null default '{}'::jsonb,
  answer_given      text,
  is_correct        boolean,
  response_time_ms  integer,
  answered_at       timestamptz,
  created_at        timestamptz not null default now(),

  primary key (attempt_id, position),
  constraint overall_assessment_position_valid check (position between 1 and 100),
  constraint overall_assessment_skill_valid
    check (skill_category in ('listening', 'reading', 'speaking', 'spelling'))
);

create index overall_assessment_questions_question_idx
  on public.overall_assessment_questions (question_id);

create index overall_assessment_questions_sense_idx
  on public.overall_assessment_questions (sense_id);

alter table public.overall_assessment_attempts enable row level security;
alter table public.overall_assessment_questions enable row level security;

create policy overall_assessment_attempts_own_select
on public.overall_assessment_attempts for select to authenticated
using (auth.uid() = user_id);

-- Attempt questions contain correctness payloads; RPCs return learner-safe
-- payloads only, matching practice_round_questions / band_upgrade_attempt_questions.

grant select on public.overall_assessment_attempts to authenticated;

create or replace function public.overall_assessment_public_payload(
  p_attempt_id uuid
)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'attempt_id', a.id,
    'status', a.status,
    'question_count', a.question_count,
    'correct_count', a.correct_count,
    'listening_correct', a.listening_correct, 'listening_total', a.listening_total,
    'reading_correct', a.reading_correct, 'reading_total', a.reading_total,
    'speaking_correct', a.speaking_correct, 'speaking_total', a.speaking_total,
    'spelling_correct', a.spelling_correct, 'spelling_total', a.spelling_total,
    'listening_band', a.listening_band,
    'reading_band', a.reading_band,
    'speaking_band', a.speaking_band,
    'spelling_band', a.spelling_band,
    'overall_band', a.overall_band,
    'questions', coalesce(jsonb_agg(
      jsonb_build_object(
        'position', aq.position,
        'question_id', aq.question_id,
        'question_type_key', aq.question_type_key,
        'skill_category', aq.skill_category,
        'answer_form', aq.answer_form,
        'stem', aq.generated_payload ->> 'stem',
        'prompt_hint', aq.generated_payload ->> 'prompt_hint',
        'translation_zh', aq.generated_payload ->> 'translation_zh',
        'headword', aq.generated_payload ->> 'headword',
        'option_ids', aq.option_ids,
        'options', coalesce((
          select jsonb_agg(
            jsonb_build_object(
              'id', qo.id,
              'text', qo.option_text,
              'sort_order', qo.sort_order
            )
            order by array_position(aq.option_ids, qo.id)
          )
          from public.question_options qo
          where qo.id = any(aq.option_ids)
        ), '[]'::jsonb),
        'answered', aq.answered_at is not null,
        'is_correct', aq.is_correct
      )
      order by aq.position
    ), '[]'::jsonb)
  )
  from public.overall_assessment_attempts a
  join public.overall_assessment_questions aq on aq.attempt_id = a.id
  where a.id = p_attempt_id
  group by a.id;
$$;

create or replace function public.overall_assessment_types_for_skill(
  p_skill text
)
returns text[]
language sql
immutable
set search_path = ''
as $$
  select case p_skill
    when 'listening' then array['listening_choice', 'listening_fill']
    when 'reading'   then array['meaning_choice', 'reading_comprehension']
    when 'speaking'  then array['speaking_repeat', 'open_speaking']
    when 'spelling'  then array['sentence_cloze_typing', 'word_form']
  end;
$$;

create or replace function public.start_overall_assessment()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_attempt_id uuid;
  v_skills text[] := array['listening', 'reading', 'speaking', 'spelling'];
  v_skill text;
  v_types text[];
  v_position integer := 1;
  v_generated record;
  v_item record;
  v_skill_taken integer;
  v_type_index integer;
  v_attempted_type text;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  select id into v_attempt_id
  from public.overall_assessment_attempts
  where user_id = v_user_id
    and status = 'started'
  order by started_at desc
  limit 1;

  if v_attempt_id is not null then
    return public.overall_assessment_public_payload(v_attempt_id);
  end if;

  insert into public.overall_assessment_attempts (user_id, question_count)
  values (v_user_id, 100)
  returning id into v_attempt_id;

  foreach v_skill in array v_skills loop
    v_types := public.overall_assessment_types_for_skill(v_skill);
    v_skill_taken := 0;
    v_type_index := 0;

    for v_item in
      select lsa.sense_id, lsa.level_number
      from public.level_sense_assignments lsa
      where lsa.placement_type = 'new'
      order by random()
      limit 300
    loop
      exit when v_skill_taken >= 25;

      v_type_index := v_type_index + 1;
      v_attempted_type := v_types[1 + (v_type_index % array_length(v_types, 1))];

      begin
        select * into v_generated
        from public.generate_practice_question(
          v_item.sense_id,
          v_item.level_number,
          v_attempted_type
        );
      exception when others then
        v_attempted_type := v_types[1 + ((v_type_index + 1) % array_length(v_types, 1))];
        begin
          select * into v_generated
          from public.generate_practice_question(
            v_item.sense_id,
            v_item.level_number,
            v_attempted_type
          );
        exception when others then
          continue;
        end;
      end;

      insert into public.overall_assessment_questions (
        attempt_id,
        position,
        question_id,
        sense_id,
        question_type_key,
        skill_category,
        answer_form,
        option_ids,
        correct_option_id,
        generated_payload,
        correct_answer_payload
      )
      values (
        v_attempt_id,
        v_position,
        v_generated.question_id,
        v_item.sense_id,
        v_attempted_type,
        v_skill,
        v_generated.answer_form,
        coalesce(v_generated.option_ids, '{}'::uuid[]),
        v_generated.correct_option_id,
        v_generated.generated_payload,
        v_generated.correct_answer_payload
      );

      v_position := v_position + 1;
      v_skill_taken := v_skill_taken + 1;
    end loop;
  end loop;

  update public.overall_assessment_attempts
  set question_count = v_position - 1,
      listening_total = (select count(*) from public.overall_assessment_questions where attempt_id = v_attempt_id and skill_category = 'listening'),
      reading_total   = (select count(*) from public.overall_assessment_questions where attempt_id = v_attempt_id and skill_category = 'reading'),
      speaking_total  = (select count(*) from public.overall_assessment_questions where attempt_id = v_attempt_id and skill_category = 'speaking'),
      spelling_total  = (select count(*) from public.overall_assessment_questions where attempt_id = v_attempt_id and skill_category = 'spelling'),
      updated_at = now()
  where id = v_attempt_id;

  if v_position <= 1 then
    delete from public.overall_assessment_attempts where id = v_attempt_id;
    raise exception 'No eligible vocabulary available for the overall assessment';
  end if;

  return public.overall_assessment_public_payload(v_attempt_id);
end;
$$;

revoke all on function public.start_overall_assessment() from public, anon;
grant execute on function public.start_overall_assessment() to authenticated;

create or replace function public.save_overall_assessment_answer(
  p_attempt_id uuid,
  p_position integer,
  p_answer text,
  p_response_time_ms integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_attempt public.overall_assessment_attempts%rowtype;
  v_question public.overall_assessment_questions%rowtype;
  v_answer text := btrim(coalesce(p_answer, ''));
  v_correct_answer text;
  v_is_correct boolean := false;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  select * into v_attempt
  from public.overall_assessment_attempts
  where id = p_attempt_id
    and user_id = v_user_id;

  if v_attempt.id is null then
    raise exception 'Assessment attempt not found';
  end if;

  if v_attempt.status <> 'started' then
    raise exception 'Assessment attempt is already completed';
  end if;

  select * into v_question
  from public.overall_assessment_questions
  where attempt_id = p_attempt_id
    and position = p_position;

  if v_question.attempt_id is null then
    raise exception 'Question position % not found', p_position;
  end if;

  if v_question.answered_at is not null then
    return jsonb_build_object(
      'already_saved', true,
      'position', p_position,
      'is_correct', v_question.is_correct
    );
  end if;

  v_correct_answer := v_question.correct_answer_payload ->> 'correct_answer';

  if v_question.answer_form = 'option' then
    v_is_correct :=
      v_answer = v_question.correct_option_id::text
      or exists (
        select 1
        from public.question_options qo
        where qo.id = v_question.correct_option_id
          and lower(btrim(qo.option_text)) = lower(v_answer)
      );
  else
    v_is_correct := lower(v_answer) = lower(btrim(coalesce(v_correct_answer, '')));
  end if;

  update public.overall_assessment_questions
  set answer_given = v_answer,
      is_correct = v_is_correct,
      response_time_ms = p_response_time_ms,
      answered_at = now()
  where attempt_id = p_attempt_id
    and position = p_position;

  update public.overall_assessment_attempts
  set updated_at = now()
  where id = p_attempt_id;

  return jsonb_build_object(
    'already_saved', false,
    'position', p_position,
    'is_correct', v_is_correct
  );
end;
$$;

revoke all on function public.save_overall_assessment_answer(uuid, integer, text, integer) from public, anon;
grant execute on function public.save_overall_assessment_answer(uuid, integer, text, integer) to authenticated;

create or replace function public.complete_overall_assessment(
  p_attempt_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_attempt public.overall_assessment_attempts%rowtype;
  v_answered_count integer;
  v_correct_count integer;
  v_listening_correct integer; v_listening_total integer;
  v_reading_correct integer; v_reading_total integer;
  v_speaking_correct integer; v_speaking_total integer;
  v_spelling_correct integer; v_spelling_total integer;
  v_listening_weighted_correct numeric; v_listening_weighted_max numeric;
  v_reading_weighted_correct numeric; v_reading_weighted_max numeric;
  v_speaking_weighted_correct numeric; v_speaking_weighted_max numeric;
  v_spelling_weighted_correct numeric; v_spelling_weighted_max numeric;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  select * into v_attempt
  from public.overall_assessment_attempts
  where id = p_attempt_id
    and user_id = v_user_id;

  if v_attempt.id is null then
    raise exception 'Assessment attempt not found';
  end if;

  if v_attempt.status = 'completed' then
    return public.overall_assessment_public_payload(p_attempt_id);
  end if;

  select count(*) into v_answered_count
  from public.overall_assessment_questions
  where attempt_id = p_attempt_id
    and answered_at is not null;

  if v_answered_count <> v_attempt.question_count then
    raise exception 'All % questions must be answered before completion (answered %)',
      v_attempt.question_count, v_answered_count;
  end if;

  select count(*) filter (where is_correct) into v_correct_count
  from public.overall_assessment_questions
  where attempt_id = p_attempt_id;

  select
    count(*) filter (where skill_category = 'listening' and is_correct), count(*) filter (where skill_category = 'listening'),
    count(*) filter (where skill_category = 'reading' and is_correct), count(*) filter (where skill_category = 'reading'),
    count(*) filter (where skill_category = 'speaking' and is_correct), count(*) filter (where skill_category = 'speaking'),
    count(*) filter (where skill_category = 'spelling' and is_correct), count(*) filter (where skill_category = 'spelling')
  into
    v_listening_correct, v_listening_total,
    v_reading_correct, v_reading_total,
    v_speaking_correct, v_speaking_total,
    v_spelling_correct, v_spelling_total
  from public.overall_assessment_questions
  where attempt_id = p_attempt_id;

  select
    coalesce(sum(public.sense_difficulty_weight(sense_id)) filter (where skill_category = 'listening' and is_correct), 0),
    coalesce(sum(public.sense_difficulty_weight(sense_id)) filter (where skill_category = 'listening'), 0),
    coalesce(sum(public.sense_difficulty_weight(sense_id)) filter (where skill_category = 'reading' and is_correct), 0),
    coalesce(sum(public.sense_difficulty_weight(sense_id)) filter (where skill_category = 'reading'), 0),
    coalesce(sum(public.sense_difficulty_weight(sense_id)) filter (where skill_category = 'speaking' and is_correct), 0),
    coalesce(sum(public.sense_difficulty_weight(sense_id)) filter (where skill_category = 'speaking'), 0),
    coalesce(sum(public.sense_difficulty_weight(sense_id)) filter (where skill_category = 'spelling' and is_correct), 0),
    coalesce(sum(public.sense_difficulty_weight(sense_id)) filter (where skill_category = 'spelling'), 0)
  into
    v_listening_weighted_correct, v_listening_weighted_max,
    v_reading_weighted_correct, v_reading_weighted_max,
    v_speaking_weighted_correct, v_speaking_weighted_max,
    v_spelling_weighted_correct, v_spelling_weighted_max
  from public.overall_assessment_questions
  where attempt_id = p_attempt_id;

  update public.overall_assessment_attempts
  set status = 'completed',
      correct_count = v_correct_count,
      listening_correct = v_listening_correct, listening_total = v_listening_total,
      reading_correct = v_reading_correct, reading_total = v_reading_total,
      speaking_correct = v_speaking_correct, speaking_total = v_speaking_total,
      spelling_correct = v_spelling_correct, spelling_total = v_spelling_total,
      listening_band = public.compute_skill_band(v_listening_weighted_correct, v_listening_weighted_max),
      reading_band = public.compute_skill_band(v_reading_weighted_correct, v_reading_weighted_max),
      speaking_band = public.compute_skill_band(v_speaking_weighted_correct, v_speaking_weighted_max),
      spelling_band = public.compute_skill_band(v_spelling_weighted_correct, v_spelling_weighted_max),
      completed_at = now(),
      updated_at = now()
  where id = p_attempt_id;

  update public.overall_assessment_attempts
  set overall_band = (
    select round(avg(b), 1) from unnest(array[
      listening_band, reading_band, speaking_band, spelling_band
    ]) as b
    where b is not null
  )
  where id = p_attempt_id;

  return public.overall_assessment_public_payload(p_attempt_id);
end;
$$;

revoke all on function public.complete_overall_assessment(uuid) from public, anon;
grant execute on function public.complete_overall_assessment(uuid) to authenticated;
