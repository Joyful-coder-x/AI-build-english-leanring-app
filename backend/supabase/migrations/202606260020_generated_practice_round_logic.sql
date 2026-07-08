begin;

-- KuaKua Duck: generated 20-slot practice rounds.
--
-- This migration keeps the Android RPC contract stable:
--   start_practice_round(level) -> round JSON
--   save_practice_answer(round, position, answer, ms) -> grading JSON
--   complete_practice_round(round) -> result JSON
--
-- The implementation changes the backend model to:
--   1. pick vocabulary by priority per slot;
--   2. pick a question type after the vocabulary is known;
--   3. generate and snapshot the delivered question at round start;
--   4. log formal attempts and update both sense and skill progress.

-- ---------------------------------------------------------------------------
-- Schema additions

alter table public.practice_round_questions
  add column if not exists source_bucket text,
  add column if not exists generated_payload jsonb not null default '{}'::jsonb,
  add column if not exists correct_answer_payload jsonb not null default '{}'::jsonb;

comment on column public.practice_round_questions.source_bucket is
  'Round-selection source: mistake, new, review, or fallback.';
comment on column public.practice_round_questions.generated_payload is
  'Immutable frontend payload generated for this round item.';
comment on column public.practice_round_questions.correct_answer_payload is
  'Immutable answer/options payload used for scoring/debugging.';

alter table public.user_sense_mastery
  add column if not exists last_wrong_at timestamptz,
  add column if not exists priority_boost integer not null default 0;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.user_sense_mastery'::regclass
      and conname = 'user_sense_priority_boost_non_negative'
  ) then
    alter table public.user_sense_mastery
      add constraint user_sense_priority_boost_non_negative
      check (priority_boost >= 0);
  end if;
end $$;

create table if not exists public.question_attempts (
  id                  uuid primary key default gen_random_uuid(),
  user_id             uuid not null references public.profiles(id) on delete cascade,
  round_id            uuid not null references public.practice_rounds(id) on delete cascade,
  session_id          uuid not null references public.practice_sessions(id) on delete cascade,
  position            smallint not null,
  question_id         uuid not null references public.questions(id),
  sense_id            uuid not null references public.word_senses(id) on delete cascade,
  word_id             uuid references public.words(id) on delete set null,
  question_type_key   text not null,
  skill_key           text not null,
  answer_form         text not null,
  presented_at        timestamptz not null,
  answered_at         timestamptz not null default now(),
  response_time_ms    integer not null,
  was_correct         boolean,
  answer_outcome      text not null,
  presented_payload   jsonb not null default '{}'::jsonb,
  answer_payload      jsonb not null default '{}'::jsonb,
  generator_version   text not null default 'generated_round_v1',
  scoring_version     text not null default 'sense_review_v2',

  unique (round_id, position),
  constraint question_attempts_response_time_non_negative check (response_time_ms >= 0),
  constraint question_attempts_skill_valid check (
    skill_key in ('meaning', 'spelling', 'listening', 'speaking', 'reading')
  )
);

create table if not exists public.user_skill_progress (
  user_id           uuid not null references public.profiles(id) on delete cascade,
  skill_key         text not null,
  total_attempts    integer not null default 0,
  correct_attempts  integer not null default 0,
  wrong_attempts    integer not null default 0,
  last_attempt_at   timestamptz,
  weakness_score    numeric(5,4) not null default 0,
  updated_at        timestamptz not null default now(),

  primary key (user_id, skill_key),
  constraint user_skill_progress_skill_valid check (
    skill_key in ('meaning', 'spelling', 'listening', 'speaking', 'reading')
  ),
  constraint user_skill_progress_counts_valid check (
    total_attempts >= 0
    and correct_attempts >= 0
    and wrong_attempts >= 0
    and correct_attempts + wrong_attempts <= total_attempts
  ),
  constraint user_skill_progress_weakness_range check (weakness_score between 0 and 1)
);

alter table public.question_attempts enable row level security;
alter table public.user_skill_progress enable row level security;

drop policy if exists question_attempts_own on public.question_attempts;
create policy question_attempts_own
on public.question_attempts for select to authenticated
using (user_id = auth.uid());

drop policy if exists user_skill_progress_own_select on public.user_skill_progress;
create policy user_skill_progress_own_select
on public.user_skill_progress for select to authenticated
using (user_id = auth.uid());

revoke all on public.question_attempts from anon, authenticated;
revoke all on public.user_skill_progress from anon, authenticated;
grant select on public.question_attempts, public.user_skill_progress to authenticated;

create index if not exists question_attempts_user_answered_idx
  on public.question_attempts (user_id, answered_at desc);
create index if not exists question_attempts_user_sense_answered_idx
  on public.question_attempts (user_id, sense_id, answered_at desc);
create index if not exists user_skill_progress_user_idx
  on public.user_skill_progress (user_id, skill_key);
create index if not exists user_sense_mastery_priority_boost_idx
  on public.user_sense_mastery (user_id, priority_boost desc, next_due_at);

-- Ensure the reduced 8 question type catalog exists for generated rows.
insert into public.question_types (
  type_code, category, name, name_zh, answer_form, skill_type, notes
)
values
  (101, 'new_word',  'meaning_choice',          'meaning choice',          'option',   'meaning',   'Choose the English word that matches the meaning'),
  (102, 'new_word',  'sentence_cloze_typing',   'sentence cloze typing',   'keyboard', 'spelling',  'Type the target word in a sentence blank'),
  (103, 'listening', 'listening_choice',        'listening choice',        'option',   'listening', 'Choose the word heard in the prompt'),
  (104, 'listening', 'listening_fill',          'listening fill',          'keyboard', 'listening', 'Type the word heard in the prompt'),
  (105, 'speaking',  'speaking_repeat',         'speaking repeat',         'option',   'speaking',  'Repeat the word and self-check'),
  (106, 'speaking',  'open_speaking',           'open speaking',           'option',   'speaking',  'Use the word aloud and self-check'),
  (107, 'reading',   'word_form',               'word form',               'keyboard', 'spelling',  'Type the target word/form'),
  (108, 'reading',   'reading_comprehension',   'reading comprehension',   'option',   'reading',   'Choose the word that completes the context')
on conflict (type_code) do update
set category = excluded.category,
    name = excluded.name,
    name_zh = excluded.name_zh,
    answer_form = excluded.answer_form,
    skill_type = excluded.skill_type,
    notes = excluded.notes;

-- ---------------------------------------------------------------------------
-- Helper methods

create or replace function public.practice_skill_for_type(
  p_question_type_key text
)
returns text
language sql
immutable
set search_path = ''
as $$
  select case p_question_type_key
    when 'meaning_choice' then 'meaning'
    when 'sentence_cloze_typing' then 'spelling'
    when 'listening_choice' then 'listening'
    when 'listening_fill' then 'listening'
    when 'speaking_repeat' then 'speaking'
    when 'open_speaking' then 'speaking'
    when 'word_form' then 'spelling'
    when 'reading_comprehension' then 'reading'
    else 'meaning'
  end;
$$;

create or replace function public.practice_skill_type_for_key(
  p_skill_key text
)
returns public.learning_skill_enum
language sql
immutable
set search_path = ''
as $$
  select case p_skill_key
    when 'meaning' then 'meaning'::public.learning_skill_enum
    when 'spelling' then 'spelling'::public.learning_skill_enum
    when 'listening' then 'listening'::public.learning_skill_enum
    when 'speaking' then 'speaking'::public.learning_skill_enum
    when 'reading' then 'reading'::public.learning_skill_enum
    else 'meaning'::public.learning_skill_enum
  end;
$$;

create or replace function public.practice_type_code_for_key(
  p_question_type_key text
)
returns integer
language sql
immutable
set search_path = ''
as $$
  select case p_question_type_key
    when 'meaning_choice' then 101
    when 'sentence_cloze_typing' then 102
    when 'listening_choice' then 103
    when 'listening_fill' then 104
    when 'speaking_repeat' then 105
    when 'open_speaking' then 106
    when 'word_form' then 107
    when 'reading_comprehension' then 108
    else 101
  end;
$$;

create or replace function public.practice_answer_form_for_type(
  p_question_type_key text
)
returns text
language sql
immutable
set search_path = ''
as $$
  select case p_question_type_key
    when 'sentence_cloze_typing' then 'keyboard'
    when 'listening_fill' then 'keyboard'
    when 'word_form' then 'keyboard'
    else 'option'
  end;
$$;

create or replace function public.practice_question_skill_for_type(
  p_question_type_key text
)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when p_question_type_key like 'listening_%' then 'listening'
    when p_question_type_key like 'speaking_%' then 'speaking'
    when p_question_type_key in ('sentence_cloze_typing', 'word_form', 'listening_fill')
      then 'active_recall'
    else 'recognition'
  end;
$$;

create or replace function public.pick_practice_question_type(
  p_sense_id uuid,
  p_is_new boolean
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_word_id uuid;
  v_types text[] := array['meaning_choice'];
begin
  if p_is_new then
    return 'meaning_choice';
  end if;

  select word_id into v_word_id
  from public.word_senses
  where id = p_sense_id;

  -- Meaning choice always works from word_senses + words.
  v_types := array['meaning_choice', 'speaking_repeat', 'open_speaking'];

  if exists (
    select 1 from public.examples
    where sense_id = p_sense_id
      and not human_review
      and char_length(btrim(sentence_en)) > 0
      and char_length(btrim(target_span)) > 0
  ) then
    v_types := v_types || array['sentence_cloze_typing', 'reading_comprehension'];
  end if;

  -- Android currently has no audio player in this flow. These generated
  -- listening prompts remain runnable by a family/tester reading the word aloud.
  if v_word_id is not null then
    v_types := v_types || array['listening_choice', 'listening_fill'];
  end if;

  if exists (
    select 1 from public.word_forms
    where word_id = v_word_id
      and not human_review
      and char_length(btrim(form_text)) > 0
  ) then
    v_types := v_types || array['word_form'];
  end if;

  return v_types[1 + floor(random() * array_length(v_types, 1))::integer];
end;
$$;

create or replace function public.pick_practice_distractor_senses(
  p_target_sense_id uuid,
  p_level_number integer,
  p_limit integer default 3
)
returns table(sense_id uuid, headword text)
language sql
stable
set search_path = ''
as $$
  with target as (
    select ws.id, ws.word_id, ws.part_of_speech
    from public.word_senses ws
    where ws.id = p_target_sense_id
  ),
  same_level as (
    select
      ws.id as sense_id,
      w.headword,
      1 as source_rank
    from public.level_sense_assignments lsa
    join public.word_senses ws on ws.id = lsa.sense_id
    join public.words w on w.id = ws.word_id
    cross join target t
    where lsa.level_number = p_level_number
      and lsa.placement_type = 'new'
      and ws.id <> t.id
      and ws.word_id <> t.word_id
      and ws.part_of_speech = t.part_of_speech
  ),
  nearby as (
    select
      ws.id as sense_id,
      w.headword,
      2 as source_rank
    from public.level_sense_assignments lsa
    join public.word_senses ws on ws.id = lsa.sense_id
    join public.words w on w.id = ws.word_id
    cross join target t
    where lsa.level_number between greatest(1, p_level_number - 2) and p_level_number + 2
      and lsa.placement_type = 'new'
      and ws.id <> t.id
      and ws.word_id <> t.word_id
  ),
  any_level as (
    select
      ws.id as sense_id,
      w.headword,
      3 as source_rank
    from public.word_senses ws
    join public.words w on w.id = ws.word_id
    cross join target t
    where ws.id <> t.id
      and ws.word_id <> t.word_id
  ),
  unioned as (
    select * from same_level
    union all
    select * from nearby
    union all
    select * from any_level
  ),
  deduped as (
    select distinct on (sense_id) sense_id, headword, source_rank
    from unioned
    order by sense_id, source_rank
  )
  select sense_id, headword
  from deduped
  order by source_rank, random()
  limit p_limit;
$$;

create or replace function public.generate_practice_question(
  p_sense_id uuid,
  p_level_number integer,
  p_question_type_key text
)
returns table(
  question_id uuid,
  option_ids uuid[],
  correct_option_id uuid,
  answer_form text,
  question_skill text,
  generated_payload jsonb,
  correct_answer_payload jsonb
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_word_id uuid;
  v_headword text;
  v_definition_en text;
  v_definition_zh text;
  v_type_code integer := public.practice_type_code_for_key(p_question_type_key);
  v_answer_form text := public.practice_answer_form_for_type(p_question_type_key);
  v_skill_key text := public.practice_skill_for_type(p_question_type_key);
  v_question_skill text := public.practice_question_skill_for_type(p_question_type_key);
  v_stem text;
  v_prompt_hint text;
  v_correct_answer text;
  v_translation_zh text;
  v_example public.examples%rowtype;
  v_form_text text;
  v_correct_option_id uuid;
  v_option_ids uuid[] := '{}';
  v_option_id uuid;
  v_option_sort integer := 1;
  v_distractor record;
  v_question_id uuid;
  v_generated_payload jsonb;
  v_correct_payload jsonb;
begin
  select ws.word_id, w.headword, ws.definition_en, ws.definition_zh
  into v_word_id, v_headword, v_definition_en, v_definition_zh
  from public.word_senses ws
  join public.words w on w.id = ws.word_id
  where ws.id = p_sense_id;

  if v_word_id is null then
    raise exception 'Sense % not found', p_sense_id;
  end if;

  v_translation_zh := coalesce(v_definition_zh, '');
  v_correct_answer := v_headword;

  if p_question_type_key in ('sentence_cloze_typing', 'reading_comprehension') then
    select * into v_example
    from public.examples e
    where e.sense_id = p_sense_id
      and not e.human_review
      and char_length(btrim(e.sentence_en)) > 0
    order by e.sort_order, e.created_at
    limit 1;
  end if;

  if p_question_type_key = 'word_form' then
    select form_text into v_form_text
    from public.word_forms
    where word_id = v_word_id
      and (sense_id = p_sense_id or sense_id is null)
      and not human_review
      and lower(form_text) <> lower(v_headword)
    order by case when sense_id = p_sense_id then 0 else 1 end, form_type, form_text
    limit 1;

    v_correct_answer := coalesce(v_form_text, v_headword);
  end if;

  v_prompt_hint := case p_question_type_key
    when 'meaning_choice' then 'Choose the correct word.'
    when 'sentence_cloze_typing' then 'Fill the blank by typing the word.'
    when 'listening_choice' then 'Listen to the tester and choose.'
    when 'listening_fill' then 'Listen to the tester and type.'
    when 'speaking_repeat' then 'Repeat aloud, then self-check.'
    when 'open_speaking' then 'Speak aloud, then self-check.'
    when 'word_form' then 'Type the correct word form.'
    when 'reading_comprehension' then 'Read the context and choose.'
    else 'Answer the question.'
  end;

  v_stem := case p_question_type_key
    when 'meaning_choice' then
      'Which word means: ' || coalesce(nullif(v_definition_zh, ''), v_definition_en) || '?'
    when 'sentence_cloze_typing' then
      case when v_example.id is not null then
        replace(v_example.sentence_en, v_example.target_span, '___')
      else
        'Type the word that means: ' || v_definition_en || '.'
      end
    when 'listening_choice' then
      'Listening demo: your tester says "' || v_headword || '". Which word did you hear?'
    when 'listening_fill' then
      'Listening demo: your tester says the target word. Type the word you heard.'
    when 'speaking_repeat' then
      'Say this word aloud: "' || v_headword || '". Then self-check your pronunciation.'
    when 'open_speaking' then
      'Say one short sentence aloud using "' || v_headword || '". Then self-check.'
    when 'word_form' then
      'Type the requested word form for "' || v_headword || '". Meaning: ' || v_definition_en || '.'
    when 'reading_comprehension' then
      case when v_example.id is not null then
        'Choose the word that completes this sentence: ' ||
        replace(v_example.sentence_en, v_example.target_span, '___')
      else
        'Choose the word that best fits this context: This word means "' || v_definition_en || '".'
      end
    else
      v_headword
  end;

  insert into public.questions (
    sense_id,
    question_type_id,
    type_code,
    category,
    answer_form,
    word_id,
    stem,
    correct_answer,
    difficulty,
    is_active,
    generation_version,
    human_review,
    prompt_hint,
    translation_zh,
    expected_time_ms,
    question_type_key,
    is_context_hint,
    context_for_multiple_meaning
  )
  values (
    p_sense_id,
    v_type_code,
    v_type_code,
    case
      when p_question_type_key like 'listening_%' then 'listening'::public.question_category
      when p_question_type_key like 'speaking_%' then 'speaking'::public.question_category
      when p_question_type_key in ('word_form', 'reading_comprehension') then 'reading'::public.question_category
      else 'new_word'::public.question_category
    end,
    v_answer_form::public.answer_form,
    v_word_id,
    v_stem,
    v_correct_answer,
    4.0,
    true,
    'generated_round_v1',
    false,
    v_prompt_hint,
    v_translation_zh,
    case v_answer_form when 'keyboard' then 18000 else 12000 end,
    p_question_type_key,
    false,
    false
  )
  returning id into v_question_id;

  if v_answer_form = 'option' then
    if p_question_type_key in ('speaking_repeat', 'open_speaking') then
      for v_distractor in
        select * from (values
          ('I said it clearly.', true),
          ('I need more practice.', false),
          ('I skipped speaking.', false),
          ('I am not sure.', false)
        ) as opt(option_text, is_correct)
      loop
        insert into public.question_options (
          question_id, option_text, target_sense_id, is_correct, sort_order, human_review
        )
        values (
          v_question_id,
          v_distractor.option_text,
          null,
          v_distractor.is_correct,
          v_option_sort,
          false
        )
        returning id into v_option_id;

        if v_distractor.is_correct then
          v_correct_option_id := v_option_id;
        end if;

        v_option_ids := v_option_ids || v_option_id;
        v_option_sort := v_option_sort + 1;
      end loop;
    else
      insert into public.question_options (
        question_id, option_text, target_sense_id, is_correct, sort_order, human_review
      )
      values (v_question_id, v_headword, p_sense_id, true, 1, false)
      returning id into v_correct_option_id;

      v_option_ids := v_option_ids || v_correct_option_id;
      v_option_sort := 2;

      for v_distractor in
        select * from public.pick_practice_distractor_senses(p_sense_id, p_level_number, 3)
      loop
        insert into public.question_options (
          question_id, option_text, target_sense_id, is_correct, sort_order, human_review
        )
        values (
          v_question_id,
          v_distractor.headword,
          v_distractor.sense_id,
          false,
          v_option_sort,
          false
        )
        returning id into v_option_id;

        v_option_ids := v_option_ids || v_option_id;
        v_option_sort := v_option_sort + 1;
      end loop;

      if array_length(v_option_ids, 1) < 4 then
        raise exception 'Not enough distractors for sense %', p_sense_id;
      end if;

      select array_agg(option_id order by random())
      into v_option_ids
      from unnest(v_option_ids) as option_id;
    end if;
  end if;

  v_generated_payload := jsonb_build_object(
    'question_type_key', p_question_type_key,
    'answer_form', v_answer_form,
    'skill_key', v_skill_key,
    'word_id', v_word_id,
    'sense_id', p_sense_id,
    'headword', v_headword,
    'stem', v_stem,
    'prompt_hint', v_prompt_hint,
    'translation_zh', v_translation_zh,
    'example_id', case when v_example.id is null then null else to_jsonb(v_example.id) end
  );

  v_correct_payload := jsonb_build_object(
    'correct_answer', v_correct_answer,
    'correct_option_id', v_correct_option_id,
    'option_ids', v_option_ids
  );

  return query select
    v_question_id,
    v_option_ids,
    v_correct_option_id,
    v_answer_form,
    v_question_skill,
    v_generated_payload,
    v_correct_payload;
end;
$$;

-- ---------------------------------------------------------------------------
-- Public RPC: generated 20-slot round

create or replace function public.start_practice_round(
  p_level_number integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_round_id uuid;
  v_session_id uuid;
  v_result jsonb;
  v_target_count integer := 20;
  v_position integer := 1;
  v_mistake_count integer := 0;
  v_new_count integer := 0;
  v_review_count integer := 0;
  v_fallback_count integer := 0;
  v_picked_senses uuid[] := '{}';
  v_candidate_sense_id uuid;
  v_candidate_source_bucket text;
  v_candidate_is_new boolean;
  v_generated record;
  v_question_type_key text;
  v_question_count integer;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  if not exists (
    select 1 from public.user_level_progress
    where user_id = v_user_id
      and level_number = p_level_number
      and is_unlocked
  ) then
    raise exception 'Level % is not unlocked', p_level_number;
  end if;

  select id into v_round_id
  from public.practice_rounds
  where user_id = v_user_id
    and level_number = p_level_number
    and status = 'started'
  order by started_at desc
  limit 1;

  if v_round_id is null then
    insert into public.practice_sessions (user_id, level_number, session_type, status)
    values (v_user_id, p_level_number, 'daily', 'started')
    returning id into v_session_id;

    insert into public.practice_rounds (
      user_id, level_number, session_id, question_count
    )
    values (v_user_id, p_level_number, v_session_id, 1)
    returning id into v_round_id;

    while v_position <= v_target_count loop
      v_candidate_sense_id := null;
      v_candidate_source_bucket := null;
      v_candidate_is_new := false;

      if v_mistake_count < 10 then
        select
          usm.sense_id,
          'mistake'::text as source_bucket,
          false as is_new
        into v_candidate_sense_id, v_candidate_source_bucket, v_candidate_is_new
        from public.user_sense_mastery usm
        join public.mistake_senses ms
          on ms.user_id = usm.user_id
         and ms.sense_id = usm.sense_id
        where usm.user_id = v_user_id
          and ms.is_active
          and usm.learning_state <> 'mastered'
          and not (usm.sense_id = any(v_picked_senses))
          and (
            usm.next_due_at is null
            or usm.next_due_at <= now()
            or ms.next_due_at is null
            or ms.next_due_at <= now()
          )
        order by ms.last_wrong_at desc, ms.wrong_count desc, usm.next_due_at nulls first
        limit 1;
      end if;

      if v_candidate_sense_id is null and v_new_count < 7 then
        select
          lsa.sense_id,
          'new'::text as source_bucket,
          true as is_new
        into v_candidate_sense_id, v_candidate_source_bucket, v_candidate_is_new
        from public.level_sense_assignments lsa
        left join public.user_sense_mastery usm
          on usm.user_id = v_user_id
         and usm.sense_id = lsa.sense_id
        where lsa.level_number = p_level_number
          and lsa.placement_type = 'new'
          and usm.user_id is null
          and not (lsa.sense_id = any(v_picked_senses))
        order by lsa.order_in_level
        limit 1;
      end if;

      if v_candidate_sense_id is null then
        select
          usm.sense_id,
          'review'::text as source_bucket,
          false as is_new
        into v_candidate_sense_id, v_candidate_source_bucket, v_candidate_is_new
        from public.user_sense_mastery usm
        left join public.level_sense_assignments lsa
          on lsa.sense_id = usm.sense_id
         and lsa.placement_type = 'new'
        where usm.user_id = v_user_id
          and usm.next_due_at is not null
          and usm.next_due_at <= now()
          and usm.learning_state <> 'mastered'
          and not (usm.sense_id = any(v_picked_senses))
          and (lsa.level_number is null or lsa.level_number <= p_level_number)
        order by usm.next_due_at, usm.priority_boost desc, usm.difficulty_level desc, random()
        limit 1;
      end if;

      if v_candidate_sense_id is null then
        select
          lsa.sense_id,
          'fallback'::text as source_bucket,
          (usm.user_id is null) as is_new
        into v_candidate_sense_id, v_candidate_source_bucket, v_candidate_is_new
        from public.level_sense_assignments lsa
        left join public.user_sense_mastery usm
          on usm.user_id = v_user_id
         and usm.sense_id = lsa.sense_id
        where lsa.level_number = p_level_number
          and lsa.placement_type = 'new'
          and not (lsa.sense_id = any(v_picked_senses))
        order by
          case when usm.user_id is null then 1 else 0 end,
          coalesce(usm.priority_boost, 0) desc,
          coalesce(usm.difficulty_level, 0) desc,
          random()
        limit 1;
      end if;

      exit when v_candidate_sense_id is null;

      v_question_type_key := public.pick_practice_question_type(
        v_candidate_sense_id,
        v_candidate_is_new
      );

      begin
        select * into v_generated
        from public.generate_practice_question(
          v_candidate_sense_id,
          p_level_number,
          v_question_type_key
        );
      exception when others then
        -- If a richer generated type fails due to sparse assets, fall back to
        -- meaning choice for the same selected vocabulary.
        v_question_type_key := 'meaning_choice';
        select * into v_generated
        from public.generate_practice_question(
          v_candidate_sense_id,
          p_level_number,
          v_question_type_key
        );
      end;

      insert into public.practice_round_questions (
        round_id,
        position,
        question_id,
        sense_id,
        question_skill,
        answer_form,
        question_type_key,
        option_ids,
        correct_option_id,
        source_bucket,
        generated_payload,
        correct_answer_payload
      )
      values (
        v_round_id,
        v_position,
        v_generated.question_id,
        v_candidate_sense_id,
        v_generated.question_skill,
        v_generated.answer_form,
        v_question_type_key,
        coalesce(v_generated.option_ids, '{}'::uuid[]),
        v_generated.correct_option_id,
        v_candidate_source_bucket,
        v_generated.generated_payload,
        v_generated.correct_answer_payload
      );

      v_picked_senses := v_picked_senses || v_candidate_sense_id;
      v_position := v_position + 1;

      case v_candidate_source_bucket
        when 'mistake' then v_mistake_count := v_mistake_count + 1;
        when 'new' then v_new_count := v_new_count + 1;
        when 'review' then v_review_count := v_review_count + 1;
        else v_fallback_count := v_fallback_count + 1;
      end case;
    end loop;

    select count(*) into v_question_count
    from public.practice_round_questions
    where round_id = v_round_id;

    if v_question_count = 0 then
      delete from public.practice_rounds where id = v_round_id;
      delete from public.practice_sessions where id = v_session_id;
      raise exception 'No eligible practice vocabulary for Level %', p_level_number;
    end if;

    update public.practice_rounds
    set question_count = v_question_count,
        new_sense_count = v_new_count,
        review_sense_count = v_mistake_count + v_review_count + v_fallback_count
    where id = v_round_id;
  end if;

  select jsonb_build_object(
    'round_id', r.id,
    'level_number', r.level_number,
    'status', r.status,
    'question_count', r.question_count,
    'new_sense_count', r.new_sense_count,
    'review_sense_count', r.review_sense_count,
    'questions', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'position', rq.position,
          'question_id', q.id,
          'sense_id', rq.sense_id,
          'stem', q.stem,
          'prompt_hint', q.prompt_hint,
          'translation_zh', q.translation_zh,
          'question_skill', rq.question_skill,
          'type_code', q.type_code,
          'answer_form', rq.answer_form,
          'question_type_key', rq.question_type_key,
          'expected_time_ms', q.expected_time_ms,
          'attempt_count', rq.attempt_count,
          'hint_used', rq.hint_used,
          'letter_count', case
            when rq.hint_used then char_length(q.correct_answer)
            else null
          end,
          'revealed_answer', case
            when rq.revealed_answer_at is not null then q.correct_answer
            else null
          end,
          'options',
            case when rq.answer_form = 'option' then (
              select jsonb_agg(
                jsonb_build_object(
                  'option_id', opt.id,
                  'option_text', opt.option_text
                )
                order by ord.ordinality
              )
              from unnest(rq.option_ids) with ordinality ord(option_id, ordinality)
              join public.question_options opt on opt.id = ord.option_id
            ) else '[]'::jsonb end,
          'answer_given', rq.answer_given,
          'is_answered', rq.answered_at is not null
        )
        order by rq.position
      )
      from public.practice_round_questions rq
      join public.questions q on q.id = rq.question_id
      where rq.round_id = r.id
    ), '[]'::jsonb)
  )
  into v_result
  from public.practice_rounds r
  where r.id = v_round_id and r.user_id = v_user_id;

  return v_result;
end;
$$;

-- ---------------------------------------------------------------------------
-- Public answer flow: keep staged cloze behavior, but update the terminal
-- persistence function to log attempts and skill progress.

create or replace function public.finalize_practice_answer(
  p_round_id         uuid,
  p_position         integer,
  p_answer           text,
  p_response_time_ms integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id             uuid := auth.uid();
  v_round               public.practice_rounds%rowtype;
  v_item                public.practice_round_questions%rowtype;
  v_q_answer_form       text;
  v_q_correct_answer    text;
  v_q_type_key          text;
  v_q_word_id           uuid;
  v_skill_key           text;
  v_skill_type          public.learning_skill_enum;
  v_is_correct          boolean;
  v_outcome             public.answer_outcome_enum;
  v_score_points        numeric(4,2);
  v_normalized_answer   text;
  v_set_active_recall   boolean := false;
  v_now                 timestamptz := clock_timestamp();
  v_mastery             public.user_sense_mastery%rowtype;
  v_old_stage           smallint;
  v_new_stage           smallint;
  v_new_state           public.sense_learning_state_enum;
  v_due_advance         boolean := false;
  v_next_due            timestamptz;
  v_spaced_increment    integer := 0;
  v_recent              boolean[];
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  if p_response_time_ms < 0 then
    raise exception 'response_time_ms must be non-negative';
  end if;

  select * into v_round
  from public.practice_rounds
  where id = p_round_id and user_id = v_user_id
  for update;

  if not found or v_round.status <> 'started' then
    raise exception 'Practice round is not active';
  end if;

  select * into v_item
  from public.practice_round_questions
  where round_id = p_round_id and position = p_position
  for update;

  if not found then
    raise exception 'Question position not found';
  end if;

  if v_item.answered_at is not null then
    return jsonb_build_object(
      'position', p_position,
      'answer_outcome', v_item.answer_outcome,
      'is_correct', v_item.is_correct,
      'correct_option_id', v_item.correct_option_id,
      'correct_answer', null,
      'already_saved', true
    );
  end if;

  select
    q.answer_form::text,
    q.correct_answer,
    coalesce(q.question_type_key, v_item.question_type_key),
    q.word_id
  into v_q_answer_form, v_q_correct_answer, v_q_type_key, v_q_word_id
  from public.questions q
  where q.id = v_item.question_id;

  v_q_answer_form := coalesce(v_item.answer_form, v_q_answer_form);
  v_q_type_key := coalesce(v_item.question_type_key, v_q_type_key, 'meaning_choice');
  v_skill_key := public.practice_skill_for_type(v_q_type_key);
  v_skill_type := public.practice_skill_type_for_key(v_skill_key);

  if v_q_answer_form = 'option' then
    if v_item.correct_option_id is null then
      raise exception 'Option question missing correct_option_id';
    end if;
    if not (p_answer ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$') then
      raise exception 'Answer must be an option UUID';
    end if;
    if not (p_answer::uuid = any(v_item.option_ids)) then
      raise exception 'Answer option does not belong to this question';
    end if;
    v_is_correct := p_answer::uuid = v_item.correct_option_id;
  elsif v_q_answer_form = 'keyboard' then
    v_normalized_answer := public.normalize_cloze_answer(p_answer);
    v_is_correct := v_normalized_answer = public.normalize_cloze_answer(v_q_correct_answer);
    v_set_active_recall := v_is_correct and v_item.attempt_count = 0;
  else
    raise exception 'Unsupported answer_form: %', v_q_answer_form;
  end if;

  v_outcome := case when v_is_correct
    then 'full_correct'::public.answer_outcome_enum
    else 'wrong'::public.answer_outcome_enum end;
  v_score_points := case when v_is_correct then 1.0 else 0.0 end;

  update public.practice_round_questions
  set answer_given = p_answer,
      normalized_answer = v_normalized_answer,
      is_correct = v_is_correct,
      answer_outcome = v_outcome,
      question_type_key = v_q_type_key,
      answer_form = v_q_answer_form,
      score_points = v_score_points,
      attempt_count = attempt_count + 1,
      response_time_ms = p_response_time_ms,
      answered_at = v_now
  where round_id = p_round_id and position = p_position;

  insert into public.user_sense_mastery (
    user_id, sense_id, learning_state, seen_count, correct_count, wrong_count,
    consecutive_correct_count, recent_results, review_stage,
    first_seen_at, first_correct_at, last_seen_at, last_correct_at,
    next_due_at, updated_at
  )
  values (
    v_user_id, v_item.sense_id, 'new', 0, 0, 0, 0, '{}', 0,
    v_now, null, null, null, null, v_now
  )
  on conflict (user_id, sense_id) do nothing;

  select * into v_mastery
  from public.user_sense_mastery
  where user_id = v_user_id and sense_id = v_item.sense_id
  for update;

  v_old_stage := v_mastery.review_stage;
  v_recent := public.append_recent_formal_result(v_mastery.recent_results, v_is_correct);

  if v_is_correct then
    if v_mastery.first_correct_at is null then
      v_new_stage := 1;
      v_new_state := 'learning';
      v_next_due := v_now + interval '1 day';
      v_spaced_increment := 1;
    elsif v_mastery.next_due_at is not null and v_now >= v_mastery.next_due_at then
      v_due_advance := true;
      v_new_stage := least(4, v_old_stage + 1);
      v_new_state := case when v_new_stage >= 4 then 'mastered' else 'reviewing' end;
      v_spaced_increment := 1;
      v_next_due := case v_new_stage
        when 1 then v_now + interval '1 day'
        when 2 then v_now + interval '7 days'
        when 3 then v_now + interval '30 days'
        when 4 then v_now + interval '90 days'
        else v_now + interval '1 day'
      end;
    else
      v_new_stage := greatest(v_old_stage, 1);
      v_new_state := case
        when v_mastery.learning_state = 'mastered' then 'reviewing'
        when v_mastery.learning_state = 'new' then 'learning'
        else v_mastery.learning_state
      end;
      v_next_due := coalesce(v_mastery.next_due_at, v_now + interval '1 day');
    end if;

    update public.user_sense_mastery
    set learning_state = v_new_state,
        seen_count = seen_count + 1,
        correct_count = correct_count + 1,
        consecutive_correct_count = consecutive_correct_count + 1,
        recent_results = v_recent,
        spaced_success_count = spaced_success_count + v_spaced_increment,
        review_stage = v_new_stage,
        mastery_score = least(0.99, greatest(v_new_stage, 1)::numeric / 4),
        has_active_recall_success = has_active_recall_success or v_set_active_recall,
        priority_boost = greatest(0, priority_boost - 1),
        first_seen_at = coalesce(first_seen_at, v_now),
        first_correct_at = coalesce(first_correct_at, v_now),
        last_seen_at = v_now,
        last_correct_at = v_now,
        next_due_at = v_next_due,
        mastered_at = case when v_new_state = 'mastered' then v_now else null end,
        updated_at = v_now
    where user_id = v_user_id and sense_id = v_item.sense_id;

    if v_due_advance then
      update public.mistake_senses
      set is_active = false,
          resolved_at = v_now,
          last_reviewed_at = v_now,
          correct_review_count = correct_review_count + 1,
          updated_at = v_now
      where user_id = v_user_id and sense_id = v_item.sense_id and is_active;
    end if;
  else
    v_new_stage := case
      when v_old_stage <= 1 then 0
      when v_old_stage = 2 then 1
      when v_old_stage = 3 then 2
      else 3
    end;
    v_new_state := case when v_new_stage = 0 then 'learning' else 'reviewing' end;
    v_next_due := v_now + interval '10 minutes';

    update public.user_sense_mastery
    set learning_state = v_new_state,
        seen_count = seen_count + 1,
        wrong_count = wrong_count + 1,
        consecutive_correct_count = 0,
        recent_results = v_recent,
        review_stage = v_new_stage,
        mastery_score = least(0.99, v_new_stage::numeric / 4),
        difficulty_level = difficulty_level + 1,
        priority_boost = priority_boost + 2,
        first_seen_at = coalesce(first_seen_at, v_now),
        last_seen_at = v_now,
        last_wrong_at = v_now,
        next_due_at = v_next_due,
        mastered_at = null,
        updated_at = v_now
    where user_id = v_user_id and sense_id = v_item.sense_id;

    insert into public.mistake_senses (
      user_id, sense_id, wrong_count, first_wrong_at, last_wrong_at,
      is_active, resolved_at, next_due_at, created_at, updated_at
    )
    values (
      v_user_id, v_item.sense_id, 1, v_now, v_now, true, null,
      v_next_due, v_now, v_now
    )
    on conflict (user_id, sense_id) do update
    set wrong_count = public.mistake_senses.wrong_count + 1,
        last_wrong_at = v_now,
        next_due_at = v_next_due,
        is_active = true,
        resolved_at = null,
        updated_at = v_now;
  end if;

  insert into public.practice_answers (
    user_id, session_id, question_id, sense_id, skill_type,
    answer_given, is_correct, response_time_ms, answered_at
  )
  values (
    v_user_id, v_round.session_id, v_item.question_id, v_item.sense_id,
    v_skill_type, p_answer, v_is_correct, p_response_time_ms, v_now
  )
  on conflict (session_id, question_id) do nothing;

  insert into public.question_attempts (
    user_id, round_id, session_id, position, question_id, sense_id, word_id,
    question_type_key, skill_key, answer_form, presented_at, answered_at,
    response_time_ms, was_correct, answer_outcome, presented_payload,
    answer_payload
  )
  values (
    v_user_id, p_round_id, v_round.session_id, p_position, v_item.question_id,
    v_item.sense_id, v_q_word_id, v_q_type_key, v_skill_key, v_q_answer_form,
    v_round.started_at, v_now, p_response_time_ms, v_is_correct,
    v_outcome::text, v_item.generated_payload,
    v_item.correct_answer_payload || jsonb_build_object(
      'answer_given', p_answer,
      'normalized_answer', v_normalized_answer
    )
  )
  on conflict (round_id, position) do nothing;

  insert into public.user_skill_progress (
    user_id, skill_key, total_attempts, correct_attempts, wrong_attempts,
    last_attempt_at, weakness_score, updated_at
  )
  values (
    v_user_id, v_skill_key, 1,
    case when v_is_correct then 1 else 0 end,
    case when v_is_correct then 0 else 1 end,
    v_now,
    case when v_is_correct then 0 else 1 end,
    v_now
  )
  on conflict (user_id, skill_key) do update
  set total_attempts = public.user_skill_progress.total_attempts + 1,
      correct_attempts = public.user_skill_progress.correct_attempts
        + case when v_is_correct then 1 else 0 end,
      wrong_attempts = public.user_skill_progress.wrong_attempts
        + case when v_is_correct then 0 else 1 end,
      last_attempt_at = v_now,
      weakness_score = case
        when public.user_skill_progress.total_attempts + 1 = 0 then 0
        else (
          public.user_skill_progress.wrong_attempts
          + case when v_is_correct then 0 else 1 end
        )::numeric / (public.user_skill_progress.total_attempts + 1)
      end,
      updated_at = v_now;

  insert into public.user_sense_skill_progress (
    user_id, sense_id, skill_type, attempt_count, correct_count,
    last_attempt_at, mastery_score, updated_at
  )
  values (
    v_user_id, v_item.sense_id, v_skill_type, 1,
    case when v_is_correct then 1 else 0 end,
    v_now,
    case when v_is_correct then 1.0 else 0.0 end,
    v_now
  )
  on conflict (user_id, sense_id, skill_type) do update
  set attempt_count = public.user_sense_skill_progress.attempt_count + 1,
      correct_count = public.user_sense_skill_progress.correct_count
        + case when v_is_correct then 1 else 0 end,
      last_attempt_at = v_now,
      mastery_score = (
        public.user_sense_skill_progress.correct_count
        + case when v_is_correct then 1 else 0 end
      )::numeric / (public.user_sense_skill_progress.attempt_count + 1),
      updated_at = v_now;

  return jsonb_build_object(
    'position', p_position,
    'answer_outcome', v_outcome,
    'is_correct', v_is_correct,
    'correct_option_id', v_item.correct_option_id,
    'correct_answer', case when v_q_answer_form = 'keyboard' then v_q_correct_answer else null end,
    'already_saved', false,
    'learning_state', v_new_state,
    'review_stage', v_new_stage,
    'next_due_at', v_next_due
  );
end;
$$;

revoke all on function public.practice_skill_for_type(text) from public, anon, authenticated;
revoke all on function public.practice_skill_type_for_key(text) from public, anon, authenticated;
revoke all on function public.practice_type_code_for_key(text) from public, anon, authenticated;
revoke all on function public.practice_answer_form_for_type(text) from public, anon, authenticated;
revoke all on function public.practice_question_skill_for_type(text) from public, anon, authenticated;
revoke all on function public.pick_practice_question_type(uuid, boolean) from public, anon, authenticated;
revoke all on function public.pick_practice_distractor_senses(uuid, integer, integer) from public, anon, authenticated;
revoke all on function public.generate_practice_question(uuid, integer, text) from public, anon, authenticated;
revoke all on function public.finalize_practice_answer(uuid, integer, text, integer)
  from public, anon, authenticated;

grant execute on function public.start_practice_round(integer) to authenticated;
grant execute on function public.save_practice_answer(uuid, integer, text, integer)
  to authenticated;
grant execute on function public.complete_practice_round(uuid) to authenticated;

commit;
