# Database Table Cleanup and 8-Type Question Data Map

Status: working database organization note.

Goal: keep the current schema usable with minimal changes, avoid adding new
tables for the 8 reduced question types, and make it clear which existing
tables are core, supporting, optional, or candidates for deletion.

## 1. Main Decision

Do not create a separate table for each question type.

The clean minimum-change organization is:

```text
question_types       = catalog of the 8 allowed question types
questions            = actual prompts for each word/sense/type
question_options     = options for choice/self-check questions

practice_rounds      = one started/completed practice round
practice_round_questions = frozen random question snapshot for that round
practice_answers     = answer history after submit
user_sense_mastery   = learning/review schedule and mastery state
mistake_senses       = wrong-word display index
```

This keeps the existing Android model and server review logic. The new data for
the 8 Level 1 people/family question types should be inserted into the existing
`question_types`, `questions`, and `question_options` tables.

## 2. Where the 8-Type Level 1 Data Goes

The migration that currently adds this data is:

```text
backend/supabase/migrations/202606260019_eight_question_type_level_one_support.sql
```

It should insert data like this:

| Data | Table | Why |
|---|---|---|
| The 8 type definitions | `question_types` | One row per question type key/code |
| Level 1 people/family prompts | `questions` | One row per word/sense/question type |
| MCQ options and speaking self-check options | `question_options` | Choice answers for option-based questions |
| Random selected questions for one learner round | `practice_round_questions` | Created by `start_practice_round`, not manually inserted |
| Learner answers | `practice_answers` | Created by `save_practice_answer`, not manually inserted |
| Review/learning state | `user_sense_mastery` | Updated by answer RPCs, not manually edited |
| Mistake notebook rows | `mistake_senses` | Updated by answer RPCs, not manually edited |

The 8 reduced type keys are:

```text
meaning_choice
sentence_cloze_typing
listening_choice
listening_fill
speaking_repeat
open_speaking
word_form
reading_comprehension
```

## 3. Keep: Core Content Tables

These are still needed.

| Table | Purpose |
|---|---|
| `bands` | Difficulty bands used by levels and content metadata |
| `topic_clusters` | Topic/category grouping for levels and content |
| `levels` | Level metadata and difficulty/topic placement |
| `level_sense_assignments` | Which senses belong to each level |
| `content_sources` | Attribution and license/source tracking |
| `words` | Headwords |
| `word_senses` | Meaning-level vocabulary records; main learning unit |
| `examples` | Example sentences |
| `usage_evidence` | Source/evidence snippets for content quality |
| `pronunciations` | IPA/audio-path metadata; keep for later listening/audio |

## 4. Keep: Question System Tables

These are the correct home for the 8 question types.

| Table | Purpose |
|---|---|
| `question_types` | Catalog/metadata for allowed question types |
| `questions` | Actual question prompts and correct answers |
| `question_options` | Options for option-answer questions |

Minimum cleanup recommendation:

- Keep `type_code` for compatibility, but treat `question_type_key` as the
  clearer runtime identifier.
- Do not add `meaning_choice_questions`, `listening_questions`, etc.
- Keep `answer_form` as the rendering/grading mode: `option`, `keyboard`, or
  later true `voice`.

## 5. Keep: Practice Runtime Tables

These are needed for random rounds, resume, scoring, and audit history.

| Table | Purpose |
|---|---|
| `practice_sessions` | Legacy/session-level practice container; still referenced |
| `practice_rounds` | Current fixed server-created round |
| `practice_round_questions` | Frozen random snapshot of questions for a round |
| `practice_answers` | Historical answers |

Minimum cleanup recommendation:

- Keep all four for now.
- Long term, decide whether `practice_sessions` remains a parent of
  `practice_rounds` or gets merged conceptually into `practice_rounds`.
- Do not remove it now because existing RPCs reference it.

## 6. Keep: User Learning State Tables

These are needed for review/learning logic.

| Table | Purpose |
|---|---|
| `profiles` | App-visible user profile and counters |
| `user_settings` | User preferences |
| `user_consents` | Legal/consent records |
| `onboarding_profiles` | Onboarding answers/status |
| `user_level_progress` | Level unlock/completion progress |
| `user_sense_mastery` | Source of truth for review stage, due time, wrong count, learning state |
| `mistake_senses` | Mistake notebook display index |

Minimum cleanup recommendation:

- Keep `user_sense_mastery` as the only review scheduler.
- Keep `mistake_senses` as display/history only; do not add scheduling fields
  there.

## 7. Keep but Not MVP-Critical

These tables are useful, but not required for the first 8-type Level 1 test.

| Table | Why keep |
|---|---|
| `collocations` | Needed for future collocation/form reinforcement |
| `word_forms` | Needed for the `word_form` question type to become real morphology practice |
| `lexical_relations` | Useful for future synonym/antonym distractors |

Minimum cleanup recommendation:

- Keep them, but do not let them create extra question types.
- Use them as data sources for `questions`, not as runtime practice tables.

## 8. Views, Not Tables

These show up in Supabase with a view icon. Do not treat them like normal data
tables.

| View | Recommendation |
|---|---|
| `content_validation_issues` | Keep if useful for content QA; delete only if nobody uses it |
| `user_band_summary` | Candidate to remove or replace later because upgrade-exam flow supersedes old band summary assumptions |

## 9. Candidate to Delete or Deprecate

Do not delete these immediately if migrations/RPCs still reference them. Use a
new forward migration after verifying references.

| Object | Recommendation | Reason |
|---|---|---|
| `user_sense_skill_progress` | Deprecate first; delete later | Current review logic uses `user_sense_mastery`; skill-specific progress is not wired into the active Android path |
| `user_band_summary` view | Deprecate or replace | Band progression should come from upgrade exams, not old aggregate assumptions |
| `content_validation_issues` view | Optional | Useful during content QA, but not needed by Android runtime |

Minimal deletion path:

1. Search app, migrations, tests, and docs for references.
2. If no active code uses the object, add a forward migration:
   - revoke grants;
   - drop dependent policies/triggers if needed;
   - drop view/table.
3. Update docs and tests.

Do not edit old applied migrations.

## 10. Do Not Delete Now

These may look extra, but should stay for now:

| Table | Why not delete |
|---|---|
| `practice_sessions` | Existing RPCs still use it as the session parent |
| `pronunciations` | Future listening/speaking needs audio/IPA metadata |
| `word_forms` | Needed to make `word_form` more than a simple typing prompt |
| `lexical_relations` | Useful for better distractors and semantic questions |
| `bands` | Levels and word_senses reference it |

## 11. Clean Table Organization After Minimal Changes

Recommended mental model:

```text
Reference / curriculum:
  bands, topic_clusters, levels, level_sense_assignments

Vocabulary content:
  content_sources, words, word_senses, examples, usage_evidence,
  pronunciations, word_forms, collocations, lexical_relations

Question bank:
  question_types, questions, question_options

Practice runtime:
  practice_sessions, practice_rounds, practice_round_questions, practice_answers

User learning:
  profiles, user_settings, user_consents, onboarding_profiles,
  user_level_progress, user_sense_mastery, mistake_senses

QA / derived views:
  content_validation_issues, user_band_summary
```

This is cleaner without a large schema rewrite.

## 12. Next Steps (updated 2026-06-28)

### Android — DONE
- [x] `LevelPracticeScreen.kt` renders type-specific UI for all 8 question types (audio panel for listening, self-assess card for speaking, passage card for reading).
- [x] `FakeVocabRepository` generates all 8 types for offline testing.
- [x] `VocabRepository.getPracticeSessionDates()` added — profile heatmap reads live `practice_sessions` data.
- [x] `AssessmentIntroScreen.kt` + `MeaningChoiceScreen.kt` + `MeaningChoiceViewModel.kt` deleted as legacy.

### Backend — Still needed
1. Apply `202606260019_eight_question_type_level_one_support.sql` to hosted Supabase.
2. Verify `question_types` has the 8 rows:

```sql
select question_type_key, count(*)
from public.questions
where generation_version = 'eight_type_level1_seed_v1'
group by question_type_key
order by question_type_key;
```

3. Verify option-based rows have options:

```sql
select q.question_type_key, count(qo.id) as option_count
from public.questions q
left join public.question_options qo on qo.question_id = q.id
where q.generation_version = 'eight_type_level1_seed_v1'
group by q.question_type_key
order by q.question_type_key;
```

4. Apply migrations 015 + 016 to hosted Supabase and verify RLS policies allow authenticated reads on `practice_sessions`.
