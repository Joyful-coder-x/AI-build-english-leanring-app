-- KuaKua Duck: repair stale practice_round_questions.question_type_key values.
--
-- Problem: migration 017 (run before migrations 019/020 introduced real
-- per-type keys like 'listening_choice') backfilled any null
-- question_type_key to the literal string 'option_recognition' and made the
-- column NOT NULL. Any round still in status='started' from that era is
-- stuck with that literal wrong value -- not null, so a "fill nulls" repair
-- does not touch it. start_practice_round resumes an existing started round
-- rather than regenerating it, so the Android client keeps rendering these
-- as plain "单词选义" MCQ with no listening/speaking/word_form panel or TTS
-- replay button, no matter what the generator or the Android resolver does
-- for *new* rounds.
--
-- Fix: overwrite practice_round_questions.question_type_key (and
-- answer_form) whenever it disagrees with the parent questions row, not just
-- when it's null. Safe to re-run.

begin;

update public.practice_round_questions rq
set question_type_key = q.question_type_key,
    answer_form        = q.answer_form::text
from public.questions q
where rq.question_id = q.id
  and q.question_type_key is not null
  and rq.question_type_key is distinct from q.question_type_key;

commit;
