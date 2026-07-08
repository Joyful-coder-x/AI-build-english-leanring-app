-- Repair legacy started-round snapshots created before answer_form and
-- question_type_key were populated on practice_round_questions.
--
-- start_practice_round resumes an existing started round. Without this repair,
-- its JSON contains explicit null values that cannot be decoded into the
-- Android client's non-null practice question model.

begin;

update public.practice_round_questions snapshot
set
  answer_form = coalesce(
    snapshot.answer_form,
    question_row.answer_form::text,
    case when question_row.type_code = 3 then 'keyboard' else 'option' end
  ),
  question_type_key = coalesce(
    snapshot.question_type_key,
    question_row.question_type_key,
    case
      when question_row.type_code = 3 then 'sentence_cloze_typing'
      when question_row.answer_form::text = 'keyboard' then 'keyboard_recall'
      else 'option_recognition'
    end
  )
from public.questions question_row
where question_row.id = snapshot.question_id
  and (
    snapshot.answer_form is null
    or snapshot.question_type_key is null
  );

alter table public.practice_round_questions
  alter column answer_form set default 'option',
  alter column answer_form set not null,
  alter column question_type_key set default 'option_recognition',
  alter column question_type_key set not null;

commit;
