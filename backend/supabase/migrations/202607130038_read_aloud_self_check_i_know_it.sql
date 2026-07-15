-- Rename read-aloud self-check success action to the shorter learner label.

begin;

update public.question_options option_row
set option_text = 'I know it'
from public.questions question_row
where question_row.id = option_row.question_id
  and (
    question_row.question_type_key = 'speaking_repeat'
    or question_row.type_code = 105
  )
  and option_row.option_text in (
    'I know how to read',
    'I know how to use',
    'I used it clearly.'
  );

update public.questions
set correct_answer = 'I know it'
where (
    question_type_key = 'speaking_repeat'
    or type_code = 105
  )
  and correct_answer in (
    'I know how to read',
    'I know how to use',
    'I used it clearly.'
  );

commit;
