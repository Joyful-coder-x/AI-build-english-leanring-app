-- Corrects the stale Level 1 sense for "old" that was imported before the
-- reviewed content export was regenerated.

begin;

update public.word_senses sense_row
set definition_en = 'having lived for many years; no longer young',
    definition_zh = '年老的',
    difficulty_band = 4.0,
    cefr_level = 'A1',
    review_status = 'approved'
from public.words word_row
where word_row.id = sense_row.word_id
  and word_row.headword = 'old'
  and sense_row.part_of_speech = 'adj.'
  and sense_row.sense_number = 1;

update public.questions question_row
set stem = 'Which word means: having lived for many years; no longer young?',
    translation_zh = '年老的'
from public.word_senses sense_row
join public.words word_row on word_row.id = sense_row.word_id
where question_row.sense_id = sense_row.id
  and word_row.headword = 'old'
  and question_row.type_code = 2
  and question_row.example_id is null;

commit;
