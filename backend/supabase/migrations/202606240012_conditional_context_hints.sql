-- Serve contextual Chinese-definition questions only when context is useful:
--   1. the source definition explicitly contains alternative meanings; or
--   2. this learner has answered the sense incorrectly at least three times.

begin;

alter table public.questions
  add column if not exists is_context_hint boolean not null default false,
  add column if not exists context_for_multiple_meaning boolean not null default false;

comment on column public.questions.is_context_hint is
  'Contextual Chinese-definition hint; not part of ordinary random practice.';
comment on column public.questions.context_for_multiple_meaning is
  'Context is preferred even before mistakes because the definition contains explicit alternative meanings.';

-- Convert the generated Chinese-to-English option question into a reserved
-- contextual hint. The reviewed Levels 1-5 conversion already uses the target
-- prompt and is included by the same update.
with context_candidates as (
  select
    question_row.id as question_id,
    question_row.sense_id,
    sense_row.definition_en,
    sense_row.definition_zh,
    word_row.headword,
    case word_row.headword
      when 'since' then 'I have lived here since 2020.'
      when 'dry' then 'The clothes are dry now.'
      when 'hit' then 'The new song became a hit around the world.'
      when 'run' then 'She can run a small restaurant near the station.'
      when 'shoot' then 'They will shoot the video tomorrow.'
      else coalesce(
        linked_example.sentence_en,
        fallback_example.sentence_en
      )
    end as sentence_en,
    coalesce(linked_example.id, fallback_example.id) as example_id
  from public.questions question_row
  join public.word_senses sense_row
    on sense_row.id = question_row.sense_id
  join public.words word_row
    on word_row.id = sense_row.word_id
  left join public.examples linked_example
    on linked_example.id = question_row.example_id
  left join lateral (
    select example_row.id, example_row.sentence_en
    from public.examples example_row
    where example_row.sense_id = question_row.sense_id
    order by example_row.sort_order, example_row.id
    limit 1
  ) fallback_example on true
  where question_row.answer_form = 'option'
    and (
      question_row.prompt_hint = '根据句子选择目标单词的完整中文释义。'
      or question_row.prompt_hint = '选择正确的英文单词。'
      or question_row.prompt_hint =
        'Choose the word that completes the sentence.'
    )
)
update public.questions question_row
set stem =
      candidates.sentence_en
      || E'\n\n句中“'
      || candidates.headword
      || '”是什么意思？',
    prompt_hint = '根据句子选择目标单词的完整中文释义。',
    example_id = candidates.example_id,
    correct_answer = candidates.definition_zh,
    translation_zh = candidates.definition_zh,
    is_active = true,
    is_context_hint = true,
    context_for_multiple_meaning =
      candidates.definition_en ~* ';\s*or\s+'
from context_candidates candidates
where candidates.question_id = question_row.id
  and candidates.sentence_en is not null;

-- Context choices are definitions, not competing English headwords.
update public.question_options option_row
set option_text = option_sense.definition_zh
from public.questions question_row,
     public.word_senses option_sense
where question_row.id = option_row.question_id
  and question_row.is_context_hint
  and option_sense.id = option_row.target_sense_id;

-- Any round created under the previous unrestricted random-selection rule is
-- abandoned. The next Start/Review click creates a correctly selected round.
update public.practice_sessions session_row
set status = 'abandoned',
    completed_at = coalesce(session_row.completed_at, now())
where session_row.status = 'started'
  and exists (
    select 1
    from public.practice_rounds round_row
    where round_row.session_id = session_row.id
      and round_row.status = 'started'
  );

update public.practice_rounds
set status = 'abandoned',
    completed_at = coalesce(completed_at, now())
where status = 'started';

create or replace function public.enforce_conditional_context_hint()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid;
  v_wrong_count integer;
  v_use_context boolean;
  v_question_id uuid;
  v_correct_option_id uuid;
  v_option_ids uuid[];
begin
  select round_row.user_id
  into v_user_id
  from public.practice_rounds round_row
  where round_row.id = new.round_id;

  select coalesce(mastery.wrong_count, 0)
  into v_wrong_count
  from public.user_sense_mastery mastery
  where mastery.user_id = v_user_id
    and mastery.sense_id = new.sense_id;

  v_wrong_count := coalesce(v_wrong_count, 0);

  v_use_context :=
    v_wrong_count >= 3
    or exists (
      select 1
      from public.questions question_row
      where question_row.sense_id = new.sense_id
        and question_row.is_active
        and question_row.is_context_hint
        and question_row.context_for_multiple_meaning
    );

  select
    question_row.id,
    (array_agg(option_row.id) filter (where option_row.is_correct))[1],
    array_agg(option_row.id order by random())
  into
    v_question_id,
    v_correct_option_id,
    v_option_ids
  from public.questions question_row
  join public.question_options option_row
    on option_row.question_id = question_row.id
  where question_row.sense_id = new.sense_id
    and question_row.is_active
    and question_row.answer_form = 'option'
    and not question_row.human_review
    and not option_row.human_review
    and question_row.is_context_hint = v_use_context
  group by question_row.id
  having count(*) >= 2
     and count(*) filter (where option_row.is_correct) = 1
  order by random()
  limit 1;

  -- If a contextual hint has not been authored for a difficult word, safely
  -- fall back to a direct recognition question.
  if v_question_id is null and v_use_context then
    select
      question_row.id,
      (array_agg(option_row.id) filter (where option_row.is_correct))[1],
      array_agg(option_row.id order by random())
    into
      v_question_id,
      v_correct_option_id,
      v_option_ids
    from public.questions question_row
    join public.question_options option_row
      on option_row.question_id = question_row.id
    where question_row.sense_id = new.sense_id
      and question_row.is_active
      and question_row.answer_form = 'option'
      and not question_row.is_context_hint
      and not question_row.human_review
      and not option_row.human_review
    group by question_row.id
    having count(*) >= 2
       and count(*) filter (where option_row.is_correct) = 1
    order by random()
    limit 1;
  end if;

  if v_question_id is null then
    raise exception 'No eligible conditional practice question for sense %',
      new.sense_id;
  end if;

  new.question_id := v_question_id;
  new.correct_option_id := v_correct_option_id;
  new.option_ids := v_option_ids;
  return new;
end;
$$;

drop trigger if exists practice_round_question_context_hint
  on public.practice_round_questions;

create trigger practice_round_question_context_hint
before insert on public.practice_round_questions
for each row execute function public.enforce_conditional_context_hint();

revoke all on function public.enforce_conditional_context_hint()
  from public, anon, authenticated;

commit;

select
  count(*) filter (where is_context_hint) as context_hint_questions,
  count(*) filter (
    where is_context_hint and context_for_multiple_meaning
  ) as multiple_meaning_questions
from public.questions;
