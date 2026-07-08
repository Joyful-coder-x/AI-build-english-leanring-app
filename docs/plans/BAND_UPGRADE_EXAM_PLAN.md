# IELTS Difficulty Upgrade Exam Plan

Status: approved product direction; supersedes the initial placement-assessment
model in the original prototype specifications and older plans.

Implementation status as of 2026-07-06:

- the learner-facing Band exam entry is visible;
- Android now opens `BandUpgradeExamScreen` instead of the placeholder;
- backend core for 40-question attempt creation, persistence, grading, resume,
  and unlock RPCs has been added in
  `backend/supabase/migrations/202607060026_band_upgrade_exam_core.sql`;
- SQL coverage for `36/40` fail and `37/40` pass has been added in
  `backend/supabase/tests/202607060026_band_upgrade_exam_core_test.sql`, but
  must still be run against the target database;
- Band 4 completion correctly does not unlock Band 4.5 directly;
- Band 4.5 content is not yet constructed/imported.

This is the highest-priority unfinished core product flow after hosted
verification of migrations 011–014.

## 1. Product terminology

- Internal code and database terminology remains `band` / `curriculum_band`.
- User-facing Chinese text must use `雅思 # 分难度`, for example:
  - `雅思 4 分难度`
  - `雅思 4.5 分难度`
  - `雅思 5 分难度`
- Do not show the unexplained English word `Band` in learner-facing UI.
- Do not describe the result as an official IELTS score or comprehensive
  listening/speaking/reading/writing assessment.

## 2. New-user starting rule

The old 40-question initial placement assessment is removed from the target
product flow.

After registration and the five onboarding questions:

1. Mark onboarding complete.
2. Unlock Level 1.
3. Start the learner at the first level of `雅思 4 分难度`.
4. Open the main learning path.

No initial score, radar chart, or calculated starting level is required.

## 3. Upgrade exam availability

Every transition from one curriculum difficulty to the next has an upgrade
exam. The exam remains available at all times, even if the learner has not
finished every level in the source difficulty.

Examples:

| Source question pool | Exam unlock target |
|---|---|
| 雅思 4 分难度 | 雅思 4.5 分难度 |
| 雅思 4.5 分难度 | 雅思 5 分难度 |
| 雅思 5 分难度 | 雅思 5.5 分难度 |
| 雅思 5.5 分难度 | 雅思 6 分难度 |
| 雅思 6 分难度 | 雅思 6.5 分难度 |
| 雅思 6.5 分难度 | 雅思 7 分难度 |
| 雅思 7 分难度 | 雅思 7.5 分难度 |
| 雅思 7.5 分难度 | 雅思 8 分难度 |

The first difficulty, `雅思 4 分难度`, is unlocked by default and therefore
does not need an entry exam.

Finishing all levels in a difficulty does not automatically unlock the next
difficulty. The learner must still pass its upgrade exam.

## 4. Exam construction

Each attempt contains exactly 40 questions randomly selected from the source
difficulty.

Requirements:

1. No duplicate question within one attempt.
2. Randomize question order.
3. Randomize option order for choice questions.
4. Draw from all available categories:
   - listening;
   - speaking;
   - reading;
   - writing.
5. Prefer a stratified target of 10 questions per category.
6. If a category does not yet contain 10 eligible questions, fill the shortage
   from the remaining categories and record the actual category mix.
7. Do not claim four-skill coverage unless all four categories are actually
   represented in that attempt.
8. Only active, reviewed, production-approved questions may be selected.
9. A question must belong to a word/sense assigned to the source difficulty.
10. The server should create and persist the attempt/question snapshot so an
    app restart cannot silently replace the exam.

For the prototype, if the content library does not yet support all four
categories, the UI must call it `升级考试` and show the categories actually
included. It must not call it an IELTS comprehensive test.

## 5. Passing rule

- Passing accuracy is strictly greater than 90%.
- For 40 questions, this means at least **37 correct answers**.
- `36/40 = 90%` does not pass.
- `37/40 = 92.5%` passes.
- Attempts are unlimited.
- A failed attempt does not remove progress, lock existing levels, or consume
  a limited item.

## 6. Unlock transaction

Passing an upgrade exam must run as one server-controlled, idempotent
transaction.

For an exam from source difficulty `S` to target difficulty `T`:

1. Mark all levels in `S` and all earlier difficulties as unlocked and
   completed/skipped-by-exam for progression purposes.
2. Preserve existing detailed learning history; do not fabricate question
   mastery for unstudied words.
3. Unlock the first level in `T`.
4. Record the exam attempt and pass result.
5. Return the updated current level and highest unlocked level.

The transaction must be safe to retry. Repeating a successful request must not
create duplicate rewards, progress rows, or unlock events.

Passing an exam does not automatically complete or unlock every level inside
the target difficulty.

## 7. Results and learner-facing report

The result screen should show:

```text
雅思 4.5 分难度升级考试

成绩：37 / 40
正确率：92.5%
结果：通过

已完成雅思 4 分难度的进阶验证，
现已解锁雅思 4.5 分难度。
```

Also show:

- correct/total;
- accuracy;
- pass/fail;
- actual question-category breakdown;
- weak categories based on this attempt;
- unlocked difficulty and first available level.

Required disclaimer:

> 本考试用于确定应用内学习进度，不代表官方雅思成绩。

Do not generate:

- an “IELTS overall score”;
- a listening/speaking/reading/writing ability radar from unsupported data;
- claims of personalized AI recommendations when only templates are used.

## 8. Data model

Recommended dedicated tables:

### `band_upgrade_attempts`

- `id uuid primary key`
- `user_id uuid not null`
- `source_band numeric(2,1) not null`
- `target_band numeric(2,1) not null`
- `status text`: `started`, `completed`, `abandoned`
- `question_count int default 40`
- `correct_count int`
- `accuracy numeric`
- `passed boolean`
- `category_counts jsonb`
- `started_at timestamptz`
- `completed_at timestamptz`
- `attempt_version text`

### `band_upgrade_attempt_questions`

- `attempt_id uuid`
- `position smallint`
- `question_id uuid`
- `category`
- `answer_given`
- `is_correct`
- `response_time_ms`
- `answered_at`

Primary key: `(attempt_id, position)`.

Question ids and order form an immutable attempt snapshot.

## 9. Required backend operations

Recommended RPCs:

- `start_band_upgrade_exam(target_band numeric)`
  - validates the target and preceding source difficulty;
  - creates/resumes one active attempt;
  - selects the 40-question snapshot;
  - returns questions without exposing correctness.

- `save_band_upgrade_answer(attempt_id, position, answer)`
  - validates ownership and question position;
  - saves one answer idempotently;
  - calculates correctness server-side.

- `complete_band_upgrade_exam(attempt_id)`
  - verifies all 40 answers exist;
  - calculates accuracy server-side;
  - applies the `>=37/40` passing rule;
  - performs the unlock transaction;
  - returns the result.

## 10. Required tests

### Unit tests

- User-facing label formats `4.0` as `雅思 4 分难度`.
- Correct answer positions are randomized.
- `36/40` fails and `37/40` passes.
- Result copy does not claim an official IELTS score.
- Category breakdown matches the attempt.

### SQL/RPC tests

- Unauthenticated users cannot start an exam.
- Users cannot access another user's attempt.
- A 40-question attempt has unique questions.
- Question pool belongs to the source difficulty.
- Correctness is calculated server-side.
- Completing with fewer than 40 answers is rejected.
- Failed attempts do not change unlock state.
- Passing completes source-and-earlier progression and unlocks only the first
  target-difficulty level.
- Completion retry is idempotent.
- Existing word mastery/history is preserved.

### End-to-end tests

- New user starts at Level 1 without an initial assessment.
- Upgrade exam is visible before all source levels are finished.
- App restart resumes the same active attempt.
- `36/40` shows failure.
- `37/40` shows success and unlocks the next difficulty.
- Finishing the final source level still requires the exam.

## 11. Migration from the current prototype

The current code and database use:

- a hardcoded 40-question initial assessment;
- `finalize_placement(ielts_band, skip)`;
- `assessment_pending` onboarding state;
- a generated “assessment report” and starting-level mapping.

Required replacement sequence:

1. Change onboarding completion to route directly to Level 1/home.
2. Remove the initial assessment gate from new-user startup.
3. Replace profile “reassessment” with difficulty upgrade-exam entry points.
4. Add dedicated exam persistence and RPCs.
5. Replace `finalize_placement` use with the new-user Level 1 completion RPC
   and upgrade-exam completion RPC.
6. Keep legacy migration objects only as compatibility artifacts until the
   new flow is verified, then mark them obsolete.
