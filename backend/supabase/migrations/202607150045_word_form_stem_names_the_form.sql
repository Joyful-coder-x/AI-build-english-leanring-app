-- word_form questions asked the learner to "Type the requested word form for
-- ..." without ever saying which form was requested (plural, past tense,
-- comparative, etc.), even though word_forms.form_type holds exactly that.
-- The stem is now specific, e.g. 'Type the plural form of "cousin". Meaning:
-- child of your aunt or uncle.'
--
-- Fix generate_practice_question so newly generated word_form questions
-- include the form type, then backfill the stem on already-generated
-- word_form questions by looking up form_type from word_forms via the
-- stored correct_answer.

begin;

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
  v_form_type text;
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
    select form_text, form_type into v_form_text, v_form_type
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
      'Type the ' || coalesce(nullif(replace(v_form_type, '_', ' '), ''), 'requested') ||
      ' form of "' || v_headword || '". Meaning: ' || v_definition_en || '.'
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

-- Backfill stems on word_form questions generated before this fix.
update public.questions q
set stem = 'Type the ' || replace(wf.form_type, '_', ' ') || ' form of "' || w.headword ||
  '". Meaning: ' || ws.definition_en || '.'
from public.word_forms wf, public.words w, public.word_senses ws
where q.question_type_key = 'word_form'
  and q.word_id = wf.word_id
  and lower(wf.form_text) = lower(q.correct_answer)
  and q.stem like 'Type the requested word form for%'
  and w.id = wf.word_id
  and ws.id = q.sense_id;

commit;
