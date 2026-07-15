-- Ensure speaking self-check questions always have a hint option and a correct
-- "I know it" / "I know how to use" option, and repair active round snapshots.

begin;

-- Normalize hint labels.
update public.question_options option_row
set option_text = 'I need hint',
    is_correct = false,
    human_review = false
from public.questions question_row
where question_row.id = option_row.question_id
  and (
    question_row.question_type_key in ('speaking_repeat', 'open_speaking')
    or question_row.type_code in (105, 106)
  )
  and option_row.option_text in ('I need more practice.', 'I need hint');

-- Normalize known labels.
update public.question_options option_row
set option_text = case
      when question_row.question_type_key = 'speaking_repeat'
        or question_row.type_code = 105
      then 'I know it'
      else 'I know how to use'
    end,
    is_correct = true,
    human_review = false
from public.questions question_row
where question_row.id = option_row.question_id
  and (
    question_row.question_type_key in ('speaking_repeat', 'open_speaking')
    or question_row.type_code in (105, 106)
  )
  and option_row.option_text in (
    'I used it clearly.',
    'I know how to use',
    'I know how to read',
    'I know it'
  );

-- Create missing hint options.
insert into public.question_options (
  question_id,
  option_text,
  target_sense_id,
  is_correct,
  sort_order,
  human_review
)
select
  question_row.id,
  'I need hint',
  question_row.sense_id,
  false,
  coalesce((
    select max(existing_option.sort_order) + 1
    from public.question_options existing_option
    where existing_option.question_id = question_row.id
  ), 1),
  false
from public.questions question_row
where (
    question_row.question_type_key in ('speaking_repeat', 'open_speaking')
    or question_row.type_code in (105, 106)
  )
  and not exists (
    select 1
    from public.question_options existing_option
    where existing_option.question_id = question_row.id
      and existing_option.option_text = 'I need hint'
  );

-- Create missing correct options.
insert into public.question_options (
  question_id,
  option_text,
  target_sense_id,
  is_correct,
  sort_order,
  human_review
)
select
  question_row.id,
  case
    when question_row.question_type_key = 'speaking_repeat'
      or question_row.type_code = 105
    then 'I know it'
    else 'I know how to use'
  end,
  question_row.sense_id,
  true,
  coalesce((
    select max(existing_option.sort_order) + 1
    from public.question_options existing_option
    where existing_option.question_id = question_row.id
  ), 1),
  false
from public.questions question_row
where (
    question_row.question_type_key in ('speaking_repeat', 'open_speaking')
    or question_row.type_code in (105, 106)
  )
  and not exists (
    select 1
    from public.question_options existing_option
    where existing_option.question_id = question_row.id
      and existing_option.is_correct
  );

update public.questions
set correct_answer = case
      when question_type_key = 'speaking_repeat' or type_code = 105
      then 'I know it'
      else 'I know how to use'
    end
where (
    question_type_key in ('speaking_repeat', 'open_speaking')
    or type_code in (105, 106)
  );

-- Repair already-started round snapshots so resumed rounds expose both choices.
with speaking_snapshot_options as (
  select
    snapshot.round_id,
    snapshot.position,
    array_agg(option_row.id order by option_row.is_correct, option_row.sort_order) as option_ids,
    (array_agg(option_row.id) filter (where option_row.is_correct))[1] as correct_option_id
  from public.practice_round_questions snapshot
  join public.questions question_row on question_row.id = snapshot.question_id
  join public.question_options option_row on option_row.question_id = question_row.id
  where (
      question_row.question_type_key in ('speaking_repeat', 'open_speaking')
      or question_row.type_code in (105, 106)
    )
    and option_row.option_text in ('I need hint', 'I know it', 'I know how to use')
  group by snapshot.round_id, snapshot.position
)
update public.practice_round_questions snapshot
set option_ids = repaired.option_ids,
    correct_option_id = repaired.correct_option_id
from speaking_snapshot_options repaired
where repaired.round_id = snapshot.round_id
  and repaired.position = snapshot.position
  and repaired.correct_option_id is not null;

commit;
