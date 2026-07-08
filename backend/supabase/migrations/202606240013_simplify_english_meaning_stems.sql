-- The prompt already says "Choose the word that matches the meaning."
-- Keep the large question text to the definition only.

begin;

update public.questions
set stem = regexp_replace(
  stem,
  '^Which word means:\s*(.*?)\?$',
  '\1',
  'i'
)
where stem ~* '^Which word means:\s*.*\?$';

commit;

select
  count(*) filter (
    where stem ~* '^Which word means:'
  ) as remaining_redundant_stems,
  count(*) filter (
    where prompt_hint in (
      'Choose the word that matches the meaning.',
      'Choose the word that matches the English meaning.'
    )
  ) as direct_english_meaning_questions
from public.questions;
