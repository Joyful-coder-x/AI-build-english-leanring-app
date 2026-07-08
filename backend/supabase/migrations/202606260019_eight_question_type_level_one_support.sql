begin;

-- KuaKua Duck: reduced 8-question-type practice support.
--
-- This migration keeps the existing mastery/review pipeline intact. It adds a
-- Level 1 test package for the people/family words and broadens practice-round
-- assembly so reviewed words can be tested with all 8 reduced types.

insert into public.question_types (
  type_code, category, name, name_zh, answer_form, skill_type, notes
)
values
  (101, 'new_word',  'meaning_choice',          'meaning choice',          'option',   'meaning',         'Choose the English word that matches the meaning'),
  (102, 'new_word',  'sentence_cloze_typing',   'sentence cloze typing',   'keyboard', 'spelling',        'Type the target word in a sentence blank'),
  (103, 'listening', 'listening_choice',        'listening choice',        'option',   'listening',       'Choose the word heard in the prompt'),
  (104, 'listening', 'listening_fill',          'listening fill',          'keyboard', 'listening',       'Type the word heard in the prompt'),
  (105, 'speaking',  'speaking_repeat',         'speaking repeat',         'option',   'speaking',        'Repeat the word and self-check'),
  (106, 'speaking',  'open_speaking',           'open speaking',           'option',   'speaking',        'Use the word aloud and self-check'),
  (107, 'reading',   'word_form',               'word form',               'keyboard', 'reading',         'Type the target word/form'),
  (108, 'reading',   'reading_comprehension',   'reading comprehension',   'option',   'reading',         'Choose the word that completes the context')
on conflict (type_code) do update
set category = excluded.category,
    name = excluded.name,
    name_zh = excluded.name_zh,
    answer_form = excluded.answer_form,
    skill_type = excluded.skill_type,
    notes = excluded.notes;

-- Keep the newer key-based contract populated for seeded rows.
alter table public.questions
  add column if not exists question_type_key text;

with level_one_words as (
  select
    lsa.sense_id,
    ws.word_id,
    w.headword,
    ws.definition_en,
    ws.definition_zh,
    row_number() over (order by lsa.order_in_level, w.headword) as rn
  from public.level_sense_assignments lsa
  join public.word_senses ws on ws.id = lsa.sense_id
  join public.words w on w.id = ws.word_id
  where lsa.level_number = 1
    and lsa.placement_type = 'new'
),
seed_specs as (
  select * from (values
    (101, 'meaning_choice',        'option'::public.answer_form,   'new_word'::public.question_category,  'meaning'::public.learning_skill_enum,         12000),
    (102, 'sentence_cloze_typing', 'keyboard'::public.answer_form, 'new_word'::public.question_category,  'spelling'::public.learning_skill_enum,        18000),
    (103, 'listening_choice',      'option'::public.answer_form,   'listening'::public.question_category, 'listening'::public.learning_skill_enum,       12000),
    (104, 'listening_fill',        'keyboard'::public.answer_form, 'listening'::public.question_category, 'listening'::public.learning_skill_enum,       18000),
    (105, 'speaking_repeat',       'option'::public.answer_form,   'speaking'::public.question_category,  'speaking'::public.learning_skill_enum,        15000),
    (106, 'open_speaking',         'option'::public.answer_form,   'speaking'::public.question_category,  'speaking'::public.learning_skill_enum,        20000),
    (107, 'word_form',             'keyboard'::public.answer_form, 'reading'::public.question_category,   'reading'::public.learning_skill_enum,         18000),
    (108, 'reading_comprehension', 'option'::public.answer_form,   'reading'::public.question_category,   'reading'::public.learning_skill_enum,         15000)
  ) as spec(type_code, question_type_key, answer_form, category, skill_type, expected_time_ms)
),
seed_questions as (
  select
    lw.sense_id,
    lw.word_id,
    lw.headword,
    lw.definition_en,
    lw.definition_zh,
    spec.type_code,
    spec.question_type_key,
    spec.answer_form,
    spec.category,
    spec.skill_type,
    spec.expected_time_ms,
    case spec.question_type_key
      when 'meaning_choice' then
        'Which word means: ' || coalesce(nullif(lw.definition_zh, ''), lw.definition_en) || '?'
      when 'sentence_cloze_typing' then
        'Type the missing family word: ' || upper(substr(lw.headword, 1, 1)) ||
        repeat('_', greatest(char_length(lw.headword) - 1, 1)) || ' means "' || lw.definition_en || '".'
      when 'listening_choice' then
        'Listening demo: your tester says "' || lw.headword || '". Which word did you hear?'
      when 'listening_fill' then
        'Listening demo: your tester says the target word. Type the word you heard.'
      when 'speaking_repeat' then
        'Say this word aloud: "' || lw.headword || '". Then self-check your pronunciation.'
      when 'open_speaking' then
        'Say one short sentence aloud using "' || lw.headword || '". Then self-check.'
      when 'word_form' then
        'Type the family/people word that matches this meaning: ' || lw.definition_en || '.'
      when 'reading_comprehension' then
        'Choose the word that best fits this context: This people-and-family word means "' ||
        lw.definition_en || '".'
      else lw.headword
    end as stem,
    case spec.question_type_key
      when 'meaning_choice' then 'Choose the correct word.'
      when 'sentence_cloze_typing' then 'Fill the blank by typing the word.'
      when 'listening_choice' then 'Listen to the tester and choose.'
      when 'listening_fill' then 'Listen to the tester and type.'
      when 'speaking_repeat' then 'Repeat aloud, then self-check.'
      when 'open_speaking' then 'Speak aloud, then self-check.'
      when 'word_form' then 'Type the correct word/form.'
      when 'reading_comprehension' then 'Read the context and choose.'
      else 'Answer the question.'
    end as prompt_hint
  from level_one_words lw
  cross join seed_specs spec
)
insert into public.questions (
  sense_id, question_type_id, type_code, category, answer_form, word_id,
  stem, correct_answer, difficulty, is_active, generation_version, human_review,
  prompt_hint, translation_zh, expected_time_ms, question_type_key,
  is_context_hint, context_for_multiple_meaning
)
select
  sq.sense_id,
  sq.type_code,
  sq.type_code,
  sq.category,
  sq.answer_form,
  sq.word_id,
  sq.stem,
  sq.headword,
  4.0,
  true,
  'eight_type_level1_seed_v1',
  false,
  sq.prompt_hint,
  sq.definition_zh,
  sq.expected_time_ms,
  sq.question_type_key,
  false,
  false
from seed_questions sq
where not exists (
  select 1
  from public.questions existing
  where existing.sense_id = sq.sense_id
    and existing.question_type_key = sq.question_type_key
    and existing.generation_version = 'eight_type_level1_seed_v1'
);

-- Multiple-choice options for recognition/listening/speaking/reading types.
with level_one_words as (
  select
    lsa.sense_id,
    w.headword,
    row_number() over (order by lsa.order_in_level, w.headword) as rn
  from public.level_sense_assignments lsa
  join public.word_senses ws on ws.id = lsa.sense_id
  join public.words w on w.id = ws.word_id
  where lsa.level_number = 1
    and lsa.placement_type = 'new'
),
option_questions as (
  select
    q.id as question_id,
    q.sense_id,
    q.question_type_key,
    lw.headword,
    lw.rn
  from public.questions q
  join level_one_words lw on lw.sense_id = q.sense_id
  where q.generation_version = 'eight_type_level1_seed_v1'
    and q.answer_form = 'option'
)
insert into public.question_options (
  question_id, option_text, target_sense_id, is_correct, sort_order, human_review
)
select
  oq.question_id,
  oq.headword,
  oq.sense_id,
  true,
  1,
  false
from option_questions oq
where oq.question_type_key not in ('speaking_repeat', 'open_speaking')
  and not exists (
    select 1 from public.question_options existing
    where existing.question_id = oq.question_id and existing.sort_order = 1
  );

with level_one_words as (
  select
    lsa.sense_id,
    w.headword,
    row_number() over (order by lsa.order_in_level, w.headword) as rn
  from public.level_sense_assignments lsa
  join public.word_senses ws on ws.id = lsa.sense_id
  join public.words w on w.id = ws.word_id
  where lsa.level_number = 1
    and lsa.placement_type = 'new'
),
option_questions as (
  select
    q.id as question_id,
    q.sense_id,
    q.question_type_key,
    lw.rn
  from public.questions q
  join level_one_words lw on lw.sense_id = q.sense_id
  where q.generation_version = 'eight_type_level1_seed_v1'
    and q.answer_form = 'option'
    and q.question_type_key not in ('speaking_repeat', 'open_speaking')
),
distractors as (
  select
    oq.question_id,
    lw.sense_id,
    lw.headword,
    row_number() over (
      partition by oq.question_id
      order by ((lw.rn - oq.rn + 1000) % 1000), lw.rn
    ) as option_rank
  from option_questions oq
  join level_one_words lw on lw.sense_id <> oq.sense_id
)
insert into public.question_options (
  question_id, option_text, target_sense_id, is_correct, sort_order, human_review
)
select
  question_id,
  headword,
  sense_id,
  false,
  option_rank + 1,
  false
from distractors
where option_rank <= 3
  and not exists (
    select 1 from public.question_options existing
    where existing.question_id = distractors.question_id
      and existing.sort_order = distractors.option_rank + 1
  );

-- Speaking self-check options. The correct option is a tester/learner
-- confirmation so the question is runnable without speech-recognition infra.
with speaking_options as (
  select
    q.id as question_id,
    opt.option_text,
    opt.is_correct,
    opt.sort_order
  from public.questions q
  cross join (values
    ('I said it clearly.', true, 1),
    ('I need more practice.', false, 2),
    ('I skipped speaking.', false, 3),
    ('I am not sure.', false, 4)
  ) as opt(option_text, is_correct, sort_order)
  where q.generation_version = 'eight_type_level1_seed_v1'
    and q.question_type_key in ('speaking_repeat', 'open_speaking')
)
insert into public.question_options (
  question_id, option_text, is_correct, sort_order, human_review
)
select question_id, option_text, is_correct, sort_order, false
from speaking_options so
where not exists (
  select 1 from public.question_options existing
  where existing.question_id = so.question_id
    and existing.sort_order = so.sort_order
);

create or replace function public.start_practice_round(
  p_level_number integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id        uuid := auth.uid();
  v_round_id       uuid;
  v_session_id     uuid;
  v_due_count      integer;
  v_max_new        integer;
  v_question_count integer;
  v_new_count      integer;
  v_review_count   integer;
  v_result         jsonb;
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
    select count(*)
    into v_due_count
    from public.user_sense_mastery
    where user_id = v_user_id
      and next_due_at is not null
      and next_due_at <= now()
      and learning_state <> 'mastered';

    v_max_new := case
      when v_due_count > 20 then 0
      when v_due_count > 0  then 12
      else 20
    end;

    insert into public.practice_sessions (user_id, level_number, session_type, status)
    values (v_user_id, p_level_number, 'daily', 'started')
    returning id into v_session_id;

    insert into public.practice_rounds (user_id, level_number, session_id, question_count)
    values (v_user_id, p_level_number, v_session_id, 1)
    returning id into v_round_id;

    with eligible_option_questions as (
      select
        q.id as question_id,
        q.sense_id,
        'option' as answer_form,
        coalesce(q.question_type_key, 'option_recognition') as question_type_key,
        coalesce(q.is_context_hint, false) as is_context_hint,
        coalesce(q.context_for_multiple_meaning, false) as context_for_multiple_meaning,
        (array_agg(qo.id) filter (where qo.is_correct))[1] as correct_option_id,
        array_agg(qo.id order by random()) as option_ids
      from public.questions q
      join public.question_options qo on qo.question_id = q.id
      where q.is_active
        and q.answer_form = 'option'
        and q.sense_id is not null
        and not q.human_review
        and not qo.human_review
      group by q.id, q.sense_id, q.question_type_key, q.is_context_hint,
               q.context_for_multiple_meaning
      having count(*) >= 2 and count(*) filter (where qo.is_correct) = 1
    ),
    eligible_keyboard_questions as (
      select
        q.id as question_id,
        q.sense_id,
        'keyboard' as answer_form,
        coalesce(q.question_type_key, 'keyboard_recall') as question_type_key,
        coalesce(q.is_context_hint, false) as is_context_hint,
        coalesce(q.context_for_multiple_meaning, false) as context_for_multiple_meaning,
        null::uuid as correct_option_id,
        '{}'::uuid[] as option_ids
      from public.questions q
      where q.is_active
        and q.answer_form = 'keyboard'
        and q.sense_id is not null
        and not q.human_review
    ),
    eligible_questions as (
      select * from eligible_option_questions
      union all
      select * from eligible_keyboard_questions
    ),
    candidate_sources as (
      select
        usm.sense_id,
        case
          when ms.is_active and usm.next_due_at is not null
               and usm.next_due_at <= now() then 1
          else 2
        end as priority,
        usm.difficulty_level,
        usm.wrong_count,
        usm.next_due_at,
        false as is_new,
        usm.seen_count as seen_count
      from public.user_sense_mastery usm
      left join public.mistake_senses ms
        on ms.user_id = v_user_id and ms.sense_id = usm.sense_id
      where usm.user_id = v_user_id
        and usm.next_due_at is not null
        and usm.next_due_at <= now()
        and usm.learning_state <> 'mastered'

      union all

      select
        lsa.sense_id,
        case
          when usm.user_id is null then 3
          when usm.next_due_at is not null
               and usm.next_due_at <= now() + interval '24 hours' then 4
          else 5
        end,
        coalesce(usm.difficulty_level, 0),
        coalesce(usm.wrong_count, 0),
        coalesce(usm.next_due_at, 'infinity'::timestamptz),
        (usm.user_id is null),
        coalesce(usm.seen_count, 0)
      from public.level_sense_assignments lsa
      left join public.user_sense_mastery usm
        on usm.user_id = v_user_id and usm.sense_id = lsa.sense_id
      where lsa.level_number = p_level_number
        and lsa.placement_type = 'new'
    ),
    candidate_senses as (
      select distinct on (sense_id)
        sense_id, priority, difficulty_level, wrong_count, next_due_at,
        is_new, seen_count
      from candidate_sources
      order by sense_id, priority, next_due_at
    ),
    ranked as (
      select
        cs.sense_id,
        cs.priority,
        cs.difficulty_level,
        cs.wrong_count,
        cs.next_due_at,
        cs.is_new,
        cs.seen_count,
        row_number() over (
          partition by cs.is_new
          order by cs.priority, cs.next_due_at, cs.difficulty_level desc, random()
        ) as type_rank
      from candidate_senses cs
      where exists (
        select 1 from eligible_questions eq
        where eq.sense_id = cs.sense_id
      )
    ),
    limited as (
      select *
      from ranked
      where not is_new or type_rank <= v_max_new
      order by priority, next_due_at, difficulty_level desc, random()
      limit 20
    ),
    chosen_raw as (
      select
        l.sense_id,
        l.priority,
        l.is_new,
        l.seen_count,
        eq.question_id,
        eq.answer_form,
        eq.question_type_key,
        eq.correct_option_id,
        eq.option_ids,
        row_number() over (
          order by l.priority, l.next_due_at, l.difficulty_level desc, random()
        )::smallint as raw_position
      from limited l
      join lateral (
        select *
        from eligible_questions candidate
        where candidate.sense_id = l.sense_id
          and (
            not candidate.is_context_hint
            or candidate.context_for_multiple_meaning
            or l.wrong_count >= 3
          )
        order by
          case candidate.question_type_key
            when (array[
              'meaning_choice',
              'sentence_cloze_typing',
              'listening_choice',
              'listening_fill',
              'speaking_repeat',
              'open_speaking',
              'word_form',
              'reading_comprehension'
            ])[(((l.type_rank - 1) % 8) + 1)::integer] then 0
            else 1
          end,
          case when candidate.is_context_hint
               and (candidate.context_for_multiple_meaning or l.wrong_count >= 3)
               then 0 else 1 end,
          random()
        limit 1
      ) eq on true
    ),
    chosen as (
      select
        sense_id, is_new, question_id, answer_form, question_type_key,
        correct_option_id, option_ids,
        row_number() over (order by raw_position)::smallint as position
      from chosen_raw
    )
    insert into public.practice_round_questions (
      round_id, position, question_id, sense_id,
      question_skill, answer_form, question_type_key,
      option_ids, correct_option_id
    )
    select
      v_round_id,
      position,
      question_id,
      sense_id,
      case
        when question_type_key like 'listening_%' then 'listening'
        when question_type_key like 'speaking_%' then 'speaking'
        when answer_form = 'keyboard' then 'active_recall'
        else 'recognition'
      end,
      answer_form,
      question_type_key,
      option_ids,
      correct_option_id
    from chosen;

    select
      count(*),
      count(*) filter (
        where not exists (
          select 1 from public.user_sense_mastery usm
          where usm.user_id = v_user_id and usm.sense_id = prq.sense_id
        )
      )
    into v_question_count, v_new_count
    from public.practice_round_questions prq
    where prq.round_id = v_round_id;

    if v_question_count = 0 then
      delete from public.practice_rounds where id = v_round_id;
      delete from public.practice_sessions where id = v_session_id;
      raise exception 'No eligible reviewed questions for Level %', p_level_number;
    end if;

    v_review_count := v_question_count - v_new_count;

    update public.practice_rounds
    set question_count = v_question_count,
        new_sense_count = v_new_count,
        review_sense_count = v_review_count
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

grant execute on function public.start_practice_round(integer) to authenticated;

commit;
