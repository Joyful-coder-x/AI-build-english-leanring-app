-- The conditional-context-hint trigger (202606240012) substitutes a
-- different question for the same sense to choose between a context-hint
-- variant and a direct-recognition variant, but it only matched on
-- sense_id + answer_form = 'option'. That let it swap in a question with a
-- completely different question_type_key (e.g. replacing a freshly
-- generated meaning_choice question with a legacy listening_choice one)
-- while leaving practice_round_questions.question_type_key untouched, so the
-- snapshot type no longer matched the linked question -- breaking type-gated
-- logic such as the listening audio_text projection.
--
-- Fix: prefer a same-question_type_key candidate in both lookups (falling
-- back to the prior unconstrained pick only if none exists), so the
-- substitution stays within the intended type whenever possible without
-- narrowing the candidate pool -- callers that never set question_type_key
-- (e.g. test fixtures that insert practice_round_questions directly) keep
-- working exactly as before.

begin;

create or replace function public.enforce_conditional_context_hint()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
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
  order by (question_row.question_type_key = new.question_type_key) desc nulls last, random()
  limit 1;

  -- If a contextual hint has not been authored for a difficult word, safely
  -- fall back to a direct recognition question, preferring the same type.
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
    order by (question_row.question_type_key = new.question_type_key) desc nulls last, random()
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
$function$;

-- Repair already-open rounds whose snapshot type no longer matches the
-- question they are actually linked to (re-running the same repair as
-- 202606290022_backfill_round_question_type_key.sql, documented there as
-- safe to re-run).
update public.practice_round_questions rq
set question_type_key = q.question_type_key,
    answer_form        = q.answer_form::text
from public.questions q
where rq.question_id = q.id
  and q.question_type_key is not null
  and rq.question_type_key is distinct from q.question_type_key;

commit;
