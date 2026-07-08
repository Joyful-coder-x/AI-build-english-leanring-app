-- Compatibility columns required by both the pilot and normalized question importer.

begin;

alter table public.questions
  add column if not exists category public.question_category,
  add column if not exists answer_form public.answer_form,
  add column if not exists word_id uuid references public.words(id);

update public.questions q
set category = qt.category,
    answer_form = qt.answer_form
from public.question_types qt
where qt.type_code = coalesce(q.question_type_id, q.type_code)
  and (
    q.category is null
    or q.answer_form is null
  );

update public.questions q
set word_id = ws.word_id
from public.word_senses ws
where ws.id = q.sense_id
  and q.word_id is null;

commit;
