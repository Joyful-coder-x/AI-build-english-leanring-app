# Phase 1 Combo Content and Band Exam Plan

Status: active scope update for Phase 1.
Created: 2026-07-06.

This plan supersedes the earlier choice between `levels_001_005` and
`band_4_0_v1`. Phase 1 uses a combo scope:

- Levels 1-5 are the polished deep-learning slice.
- Levels 6-33 are the compact lightweight Band 4 path.
- The Band 4 -> 4.5 upgrade exam is part of Phase 1.

## 1. Product Goal

Phase 1 remains a focused IELTS readiness prototype for Chinese-speaking
learners preparing for US college English. The learner-facing frame stays
IELTS/Band. "College survival" is the reason this IELTS readiness matters.

Done means a new learner can:

1. Sign in and complete onboarding.
2. Start at IELTS/Band 4 Level 1.
3. Learn through Levels 1-5 with rich question coverage across meaning,
   spelling/writing, listening, speaking, reading, examples, and word forms.
4. Continue through Levels 6-33 with a smaller but working question set.
5. Have level completion, answer logging, mistakes, streak/rewards, and unlocks
   persist through app restart and sign-out/sign-in.
6. Take a Band 4 -> 4.5 upgrade exam based on Band 4 vocabulary.
7. Unlock the first Band 4.5 level only after passing the upgrade exam.

## 2. Canonical Demo Content Package

Decision: use `backend/content-pipeline/constructed_data/band_4_0_v1` as the
canonical demo backend package.

Reason:

- It contains all current Band 4 content in compact Levels 1-33.
- Its Levels 1-5 preserve the reviewed 45-new-sense-per-level package.
- It already has import and full-installation verification notes.
- It lets the level-up mechanism be tested across the entire Band 4 path.

Important gap:

- The Band 4 CSV `12_questions.csv` is older and does not include the newer
  `question_type_key` column.
- Therefore, runtime generated-round RPCs must remain the source of truth for
  active practice question type selection.

## 3. Level 1-5 Deep Slice

Levels 1-5 must be fully functional for learning, not just recognition.

Required content per new sense:

- definition in English and Chinese;
- examples where available;
- word forms where available;
- pronunciation/audio text support where available;
- generated or imported questions covering the active eight-type model.

Required active question types:

| Skill | Existing type | Purpose |
|---|---|---|
| Meaning | `meaning_choice` | Choose the English word from Chinese/English meaning. |
| Writing/spelling | `sentence_cloze_typing` | Type the target word in a sentence or definition prompt. |
| Listening | `listening_choice` | Hear a word and choose the matching word. |
| Listening/spelling | `listening_fill` | Hear a word and type it. |
| Speaking | `speaking_repeat` | Read/repeat the word aloud and self-check. |
| Speaking production | `open_speaking` | Say a short sentence aloud and self-check. |
| Word knowledge | `word_form` | Type a useful form of the word where available. |
| Reading | `reading_comprehension` | Use context/example sentence to choose the word. |

Acceptance checks:

- Levels 1-5 each have 45 new senses.
- Each Level 1-5 new sense has all eight question types in the reviewed package
  or can generate equivalent runtime questions.
- Choice questions have exactly 4 options and 1 correct option.
- Completing practice updates logs, mistakes, mastery/progress, rewards,
  streak, and visible unlock state.

## 4. Level 6-33 Lightweight Slice

Levels 6-33 must be functional, but intentionally lighter than Levels 1-5.
The 1,465 available Band 4 senses are packed into real study-sized levels
instead of being stretched across 54 thin levels.
They should not require extra hand-authored examples, collocations, or word-form
review before they can be practiced.

Allowed active question types:

| User request | Existing type to use | Data required |
|---|---|---|
| Multiple choice with definition | `meaning_choice` | word, English definition, Chinese definition/translation |
| Listening word and match word | `listening_choice` | word/headword |
| Spelling from heard word | `listening_fill` | word/headword |
| Spelling with Chinese definition | closest current type: `sentence_cloze_typing` fallback prompt | word, Chinese definition/translation |
| Speaking/read aloud self-check | `speaking_repeat` | word/headword |

Do not require these for Levels 6-33 in Phase 1:

- `open_speaking`;
- `word_form`;
- `reading_comprehension` based on authored examples;
- collocation-specific tasks;
- polished passage reading.

Acceptance checks:

- Levels 6-33 have new-sense assignments from Band 4.
- A learner can open and complete practice rounds for every unlocked level.
- Rounds for Levels 6-33 only use the lightweight type set above.
- Level completion and unlock logic works through Level 33.

## 5. Band 4 Upgrade Exam

The Band 4 -> 4.5 upgrade exam is now Phase 1 scope.

Assessment model:

- 40 questions per attempt.
- Questions are randomly selected from Band 4 Levels 1-33.
- No duplicate question/sense in an attempt unless the pool is too small; for
  Band 4 it should be large enough to avoid duplicates.
- Use the same lightweight/generated question types as Levels 6-33, plus richer
  Level 1-5 question types when those questions are available.
- Pass threshold: above 90% accuracy.
- For 40 questions, passing requires 37/40 or higher.
- Attempts are unlimited.
- A failed attempt does not remove progress.
- A passed attempt unlocks the first Band 4.5 level and marks Band 4 completion
  for progression, without fabricating word mastery for unstudied words.

Rationale for 40 questions:

- IELTS Academic is a four-skill 2h45 test, and its Listening and Reading
  sections are each 40-question sections.
- SAT and ACT style exams use much larger multi-section batteries, which are
  too heavy for this mobile checkpoint.
- Duolingo-style product behavior favors shorter, repeatable, adaptive-feeling
  attempts.
- 40 questions is enough to sample across the Band 4 vocabulary path while
  keeping the attempt realistic for a prototype.

Required category target:

| Category | Target count |
|---|---:|
| Meaning/definition | 10 |
| Listening | 10 |
| Spelling/writing | 10 |
| Speaking self-check | 10 |

If the pool cannot fill a category, fill from the remaining eligible categories
and record the actual mix. The result screen must show the actual category mix
and must not call the result an official IELTS score.

## 6. Band Exam Backend Tasks

Required schema:

- `band_upgrade_attempts`
- `band_upgrade_attempt_questions`

Required RPCs:

- `start_band_upgrade_exam(target_band numeric)`
- `save_band_upgrade_answer(attempt_id uuid, position integer, answer text,
  response_time_ms integer)`
- `complete_band_upgrade_exam(attempt_id uuid)`

Required server guarantees:

- Authenticated owner-only access.
- Immutable attempt snapshot.
- Server-side grading.
- Idempotent answer saves.
- Completion rejected until all questions are answered.
- `36/40` fails and `37/40` passes.
- Passing unlock transaction is retry-safe.

## 7. Android Tasks

Required screens/state:

- Replace `BandExamPlaceholderScreen` with a real exam flow.
- Add repository methods for the three Band exam RPCs.
- Add a ViewModel for start/resume, answer submission, completion, and retry.
- Reuse existing LevelPractice question rendering where practical.
- Add a result screen showing score, accuracy, pass/fail, category mix, and
  unlocked level.

## 8. Verification

Backend verification:

- Band 4 package import verifier passes.
- Level 1-5 deep verifier passes.
- New SQL test covers 40-question exam creation, uniqueness, grading,
  category mix, `36/40` fail, `37/40` pass, and target unlock.
- Level 6-33 generated rounds use only lightweight question types.
- Band 4 unlock-chain SQL test covers each intra-band boundary from Level 1
  through Level 33, while preserving the Band 4 -> 4.5 exam gate.

Android verification:

- Unit tests cover Band exam ViewModel pass/fail states.
- Existing practice tests still pass.
- Manual fresh-user script covers onboarding, Levels 1-5, at least one
  Level 6+ round, Band 4 exam failure, Band 4 exam pass, and relogin state.

Current local evidence:

- `backend/supabase/tests/202607060029_phase1_practice_logging_evidence_test.sql`
  passes locally and proves one generated round writes session, round, answer,
  attempt, mastery, mistake, reward/streak, and level-progress rows.
- `.\gradlew.bat test` passes after adding
  `BandUpgradeExamViewModelTest.kt`.
- `.\gradlew.bat assembleDebug` passes.

Remaining evidence required:

- Apply migrations `202607060025` through `202607060028` to the target Supabase
  DB.
- Run the new SQL tests against the target DB.
- Run `202607060027_band4_unlock_chain_test.sql` against the target DB.
- Run `202607060029_phase1_practice_logging_evidence_test.sql` against the
  target DB.
- Manually verify the real Android app against the target DB.
