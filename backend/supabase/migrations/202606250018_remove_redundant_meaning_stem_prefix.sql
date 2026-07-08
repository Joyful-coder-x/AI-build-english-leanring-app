-- Remove legacy wording duplicated by the prompt hint.
--
-- The UI already displays "Choose the word that matches the meaning." above
-- the stem, so "Which word means:" must not also appear in the stem. This is
-- intentionally idempotent because a later content import may reintroduce
-- legacy stems after the original cleanup migration has run.

begin;

update public.questions
set stem = trim(
  regexp_replace(
    stem,
    '^Which\s+word\s+means\s*:\s*',
    '',
    'i'
  )
)
where stem ~* '^Which\s+word\s+means\s*:';

commit;

select count(*) as remaining_redundant_meaning_stems
from public.questions
where stem ~* '^Which\s+word\s+means\s*:';
