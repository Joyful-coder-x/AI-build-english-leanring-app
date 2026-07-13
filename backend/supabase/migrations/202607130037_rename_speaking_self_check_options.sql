-- Rename speaking self-check choices to clearer learner actions.

begin;

update public.question_options
set option_text = 'I need hint'
where option_text = 'I need more practice.';

update public.question_options
set option_text = 'I know how to use'
where option_text = 'I used it clearly.';

update public.questions
set correct_answer = 'I know how to use'
where correct_answer = 'I used it clearly.';

delete from public.question_options option_row
using public.questions question_row
where question_row.id = option_row.question_id
  and (
    question_row.question_type_key in ('open_speaking', 'speaking_repeat')
    or question_row.type_code in (105, 106)
  )
  and option_row.option_text in ('I am not sure.', 'I skipped it.');

commit;
