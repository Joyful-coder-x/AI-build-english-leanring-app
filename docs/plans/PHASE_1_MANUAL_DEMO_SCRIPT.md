# Phase 1 Manual Demo Script

Purpose: repeatable manual evidence for the combo prototype: Band 4 Levels
1-33 as the backend data source, deep Levels 1-5, lightweight Levels 6-33,
Band 4 -> 4.5 upgrade exam, logging, unlocks, and persistence.

## Preconditions

- Target Supabase DB has all migrations through
  `202607060028_due_review_new_word_gate.sql`.
- Band 4 package from
  `backend/content-pipeline/constructed_data/band_4_0_v1/supabase_import/`
  is imported in README order.
- SQL tests include:
  - combo practice type selection;
  - Band upgrade exam core;
  - Band 4 unlock chain;
  - Band 4 runtime content;
  - staged cloze grading;
  - spaced-review/new-word gate;
  - Phase 1 practice logging evidence.
- Android debug build installs cleanly.
- Fill `PHASE_1_TARGET_EVIDENCE_TEMPLATE.md` while running this script so the
  final target proof has command output and manual PASS/FAIL notes in one
  place.

Target database setup/verification command:

```powershell
# Requires PostgreSQL client tools (`psql`) on PATH.
$env:DATABASE_URL = "postgresql://..."
powershell -ExecutionPolicy Bypass -File backend/supabase/manual/run_phase1_target_verification.ps1 -ApplyMigrations -ResetVocabulary -ImportBand4
```

Use this only after backing up the target Supabase project. For a non-mutating
verification pass on an already loaded DB, run the same script without
`-ApplyMigrations`, `-ResetVocabulary`, or `-ImportBand4`.

## Fresh Learner Flow

1. Create a new test account.
2. Complete onboarding.
3. Confirm Home opens at `IELTS Band 4` with Level 1 unlocked and later levels
   locked.
4. Open Level 1 progress.
5. Start practice.
6. Answer a mix of option and typed questions.
7. Confirm review feedback appears after each answer.
8. Finish the round.
9. Confirm result shows score, stars, and practice points.
10. Return Home.
11. Confirm Home refreshes without restart and shows the next unlocked state.

## Deep Level 1-5 Check

For Levels 1-5, sample at least one round per level and record the question
types seen. Expected active set:

- `meaning_choice`
- `sentence_cloze_typing`
- `listening_choice`
- `listening_fill`
- `speaking_repeat`
- `open_speaking`
- `word_form`
- `reading_comprehension`

Pass condition: no Level 1-5 round opens empty, answer saving works, completion
updates result state, and level progression can continue.

## Lightweight Level 6-33 Check

Unlock or seed a user to a Level 6+ state, then start one round from Level 6
and one later Band 4 level such as Level 30 or Level 33.

Allowed question types:

- `meaning_choice`
- `listening_choice`
- `listening_fill`
- `sentence_cloze_typing`
- `speaking_repeat`

Fail condition: Level 6+ requires `open_speaking`, `word_form`, or
`reading_comprehension` to complete a round.

## Band 4 Upgrade Exam Check

1. Navigate to locked Band 4.5.
2. Start the Band exam.
3. Confirm the exam has 40 questions.
4. Confirm category mix is approximately:
   - 10 meaning
   - 10 listening
   - 10 spelling/writing
   - 10 speaking self-check
5. Submit 36 correct and 4 wrong answers.
6. Complete the exam.
7. Confirm result is failed and Band 4.5 remains locked.
8. Start or resume a new attempt.
9. Submit at least 37 correct answers.
10. Complete the exam.
11. Confirm result is passed and first Band 4.5 level unlocks.

## Persistence Check

After practice and exam checks:

1. Force-close the app.
2. Reopen it.
3. Confirm current user session restores.
4. Confirm Home still shows the latest unlocked/completed state.
5. Sign out.
6. Sign back in.
7. Confirm progress, streak/profile counters, practice history, and Band
   unlock state still match the previous state.

## Operator SQL Evidence

After one completed practice round, query the target DB for the test user and
save row-count evidence for:

- `practice_sessions`
- `practice_rounds`
- `practice_round_questions`
- answer rows used by the current round schema
- `user_sense_mastery`
- `user_level_progress`
- `mistake_senses` after at least one wrong answer
- streak/profile reward rows

The automated version of this check is
`backend/supabase/tests/202607060029_phase1_practice_logging_evidence_test.sql`.

After Band exam pass/fail, save row-count and state evidence for:

- `band_upgrade_attempts`
- `band_upgrade_attempt_questions`
- `user_level_progress` for Level 34 unlock after pass
