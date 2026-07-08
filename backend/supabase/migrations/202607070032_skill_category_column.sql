-- Phase 1 Feature I: tag each question with the IELTS skill it tests, so the
-- Overall Assessment and Band Upgrade Exam result screens can report
-- per-skill scores. listening_fill counts as listening (the primary skill
-- tested), not spelling, matching the masterplan's Feature I mapping.

begin;

alter table public.questions
  add column if not exists skill_category text
  check (skill_category in ('listening', 'reading', 'speaking', 'spelling'));

update public.questions q
set skill_category = case q.question_type_key
  when 'listening_choice'      then 'listening'
  when 'listening_fill'        then 'listening'
  when 'speaking_repeat'       then 'speaking'
  when 'open_speaking'         then 'speaking'
  when 'meaning_choice'        then 'reading'
  when 'reading_comprehension' then 'reading'
  when 'sentence_cloze_typing' then 'spelling'
  when 'word_form'             then 'spelling'
  else q.skill_category
end
where q.skill_category is null
  and q.question_type_key is not null;

commit;
