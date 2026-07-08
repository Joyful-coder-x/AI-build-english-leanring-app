# 夸夸鸭关卡与间隔复习最终设计

Document status: approved controlling product and data design  
Approved: 2026-06-24  
Implementation status: V1.0 implemented and locally verified; V1.1 deferred

## 0. Implementation status

Implemented in migrations 009 and 011–014 plus the Android repository/UI:

- immutable server-created rounds of at most 20 questions;
- server-side grading and answer persistence;
- `user_sense_mastery` scheduling and `mistake_senses` display indexing;
- 10-minute delayed review and configurable 90% Level completion;
- idempotent round completion, rewards, and Level unlocking;
- daily streak and duck-power persistence;
- conditional contextual hints:
  - immediately for explicitly marked multiple-meaning senses;
  - after `wrong_count >= 3` for an individual learner;
- Level word/status list through `get_level_word_statuses`;
- result-screen repeat action that requests a newly assembled round;
- Android integration with no client-trusted correctness.

Still deferred:

- active-recall keyboard questions as production practice;
- the learner-facing `已掌握` state and 30-day mastery qualification;
- Band upgrade exams and Band 4.5 content.

This document is the source of truth for level completion, sense learning
state, spaced review, mistake-notebook behavior, and V1.0 practice-round
assembly. Where an older plan describes simple cumulative accuracy,
mistake-owned scheduling, fixed 80-new-word levels, or one-session mastery,
this document supersedes it.

## 1. Core principle and level composition

> 夸夸鸭不把单轮正确率当作掌握率。单词掌握由多次、间隔、不同题型的成功回忆决定；关卡通关只代表可以继续下一关，不代表该关全部词汇已经长期掌握。

A level contains approximately 80 **learning slots**, not 80 entirely new
words:

- `new_sense_target`: target new senses, configurable per level;
- `collocation_target`: form/collocation reinforcement slots;
- `review_target`: previous-sense review and contextual reuse slots.

The three targets total approximately 80. Levels 1–5 retain their reviewed
composition of 45 new senses, 5 form/collocation slots, and 30 review slots.
Later levels use their configured targets and must not add weak content merely
to reach 45 new senses.

Only senses assigned to the level as target new senses participate in level
completion. Collocation and review slots never enter the completion
denominator.

## 2. Sense states and review stages

Learner-facing sense states use simple Chinese:

- `未学习`
- `学习中`
- `复习中`
- `已掌握`

Internal state values are:

- `new`
- `learning`
- `reviewing`
- `mastered`

`review_stage` has one exact interpretation:

```text
0 = learning
1 = ten_minute
2 = one_day
3 = seven_day
4 = thirty_day
5 = mastered_maintenance
```

Successful formal answers advance scheduling as follows:

```text
first correct answer        -> stage 1, due after 10 minutes
stage 1 correct when due    -> stage 2, due after 1 day
stage 2 correct when due    -> stage 3, due after 7 days
stage 3 correct when due    -> stage 4, due after 30 days
stage 4 correct when due    -> mastered, maintenance due after 75 days
stage 5 correct when due    -> maintenance due after another 75 days
```

An answer only counts as a delayed success when it occurs at or after the
stored `next_due_at`. Repeating a question early does not advance
`review_stage` or `spaced_success_count`.

Every formal wrong answer:

```text
consecutive_correct_count = 0
wrong_count += 1
next_due_at = now() + interval '10 minutes'
```

The stage regression is deliberately limited:

| Current stage | Stage after a wrong answer |
|---|---|
| `learning` | `learning` |
| `ten_minute` | `learning` |
| `one_day` | `ten_minute` |
| `seven_day` | `one_day` |
| `thirty_day` | `seven_day` |
| `mastered_maintenance` | `seven_day`, state becomes `reviewing` |

Historical correct counts, answer rows, and completed review evidence are
never deleted by regression.

`recent_results` contains exactly the latest six formal answer results as a
boolean array or JSON array. When a seventh formal result is added, the oldest
entry is removed. Rescue or explanatory attempts may be stored in
`practice_answers`, but they do not enter `recent_results`.

## 3. Level states and completion

Learner-facing level states are:

- `未解锁`
- `待开始`
- `学习中`
- `巩固中`
- `已通关`
- `已掌握`

Their meanings are:

- `未解锁`: practice cannot start.
- `待开始`: unlocked and no target new sense has been formally attempted.
- `学习中`: at least one target new sense has been attempted, but some target
  new senses have not yet appeared.
- `巩固中`: all target new senses have appeared, but the completion threshold
  has not been reached.
- `已通关`: the next level may be unlocked.
- `已掌握`: all target new senses satisfy long-term mastery. This state is
  disabled in V1.0.

For a level:

```text
required_count = ceil(new_sense_target * 0.90)
```

The level becomes `已通关` only when all conditions are true:

1. Every target new sense has appeared in a formal question at least once.
2. At least `required_count` target new senses have at least one correct
   formal answer.
3. At least `required_count` target new senses have a second correct formal
   answer at least 10 minutes after their first correct answer.
4. Those qualifying senses are currently `reviewing` or `mastered`.

Examples:

| Target new senses | Required for completion |
|---:|---:|
| 45 | 41 |
| 35 | 32 |
| 30 | 27 |
| 28 | 26 |

Completion does not require waiting for the one-day review. Remaining weak
senses stay in the global review queue after the next level unlocks.

`user_level_progress.is_completed` means `已通关`; it does not mean all senses
are mastered. Upgrade-exam progression may mark a level complete or skipped
without creating fabricated sense history.

V1.0 supports level states through `已通关` only and must not display
`已掌握`. V1.1 enables `已掌握` after active-recall question types are live.

## 4. Long-term mastery and question skills

Question skills are classified as:

```text
recognition   = choice and meaning-recognition questions
active_recall = spelling, word-form, and translation-completion input
listening     = listening recognition
speaking      = spoken production or repetition
```

Only a correct `active_recall` answer can set
`has_active_recall_success = true`.

V1.0 contains meaning-choice recognition practice. A sense may advance through
review scheduling, but its highest state is `reviewing`; V1.0 must not set
`mastered_at`.

Beginning in V1.1, a sense may become `mastered` only when all conditions hold:

- the 10-minute, 1-day, 7-day, and 30-day reviews were completed when due;
- the latest three formal results are correct;
- at least five of the latest six formal results are correct;
- at least one active-recall question was answered correctly.

## 5. Fixed 20-question practice rounds

V1.0 uses server-created, immutable rounds of at most 20 questions. The server
does not insert new positions into an active round after it starts. A sense
answered incorrectly in the current round becomes highest priority for the
next round.

Initial round assembly order:

1. Senses answered incorrectly in the previous round and now eligible.
2. Overdue mistake/review senses.
3. Unseen target new senses from the selected level.
4. Seen target senses approaching `next_due_at`.
5. Low-progress target senses from the selected level to fill remaining
   capacity.

Constraints:

- overdue review always outranks new content;
- new content never displaces an overdue item;
- if more than 20 reviews are due, the round contains no new senses;
- when any reviews are due, new senses occupy at most 60% of the round;
- a round contains at most one question for each `sense_id`;
- the same sense may use different question types across different rounds;
- answering a previous-round mistake correctly before its real
  `next_due_at` does not count as the 10-minute delayed success;
- the next round is rebuilt from current persisted state.

## 6. Data ownership

`user_sense_mastery` is the single source of truth for spaced-review
scheduling. Its planned V1 fields are:

- `user_id`, `sense_id`;
- `learning_state`;
- `review_stage`;
- `seen_count`, `correct_count`, `wrong_count`;
- `consecutive_correct_count`;
- `recent_results`;
- `spaced_success_count`;
- `has_active_recall_success`;
- `difficulty_level integer default 0`;
- `first_seen_at`, `last_seen_at`, `last_correct_at`;
- `next_due_at`, `mastered_at`, `updated_at`.

`difficulty_level` is internal-only and may influence candidate ordering; it
does not create a separate learner-facing state.

`mistake_senses` is only the mistake-notebook display index. Its planned fields
are:

- `user_id`, `sense_id`;
- `first_wrong_at`, `last_wrong_at`;
- `wrong_count`;
- `is_active`;
- `resolved_at`;
- timestamps required for auditing.

A wrong answer inserts or reactivates the index. Recovery sets
`is_active = false` and `resolved_at`, while retaining history. Scheduling and
`next_due_at` are always read from `user_sense_mastery`.

## 7. Planned backend interfaces

Implemented backend interfaces:

- `start_practice_round(level_number)` creates/resumes an owned immutable round
  of no more than 20 questions and does not expose correctness.
- `save_practice_answer(round_id, position, answer, response_time_ms)` grades
  server-side and atomically updates answer history, mastery, and mistake index.
- `complete_practice_round(round_id)` validates completion, recalculates level
  progress, and idempotently unlocks the next level.
- `get_level_learning_status(level_number)` returns target, seen, first-correct,
  delayed-success, reviewing, mastered, and due-review counts.
- `get_level_word_statuses(level_number)` returns the Level target-word list,
  Chinese definition, learner state, wrong count, and due status.

The client is never the trusted source of correctness, completion counts,
mastery transitions, unlocks, or rewards.

## 8. Acceptance tests

The implementation task must include automated coverage for:

1. A second correct answer before 10 minutes does not count as delayed review.
2. A correct answer at or after 10 minutes enters `reviewing`.
3. A 45-new-sense level requires 41 delayed-success senses.
4. Completion does not require the one-day review.
5. Collocation and historical review slots do not enter the completion
   denominator.
6. A wrong answer at `thirty_day` regresses only to `seven_day`.
7. A mastered sense answered incorrectly returns to `reviewing` without losing
   historical counts.
8. `recent_results` contains at most the latest six formal results.
9. Recognition-only V1.0 practice cannot create `mastered`.
10. Only correct `active_recall` answers set `has_active_recall_success`.
11. A resolved mistake becomes active again after another wrong answer.
12. A round contains no duplicate `sense_id`.
13. More than 20 overdue reviews suppresses all new content.
14. Retried completion does not duplicate unlocks or rewards.
15. Upgrade-exam progression does not fabricate sense mastery.

## 9. Implementation status and next sequence

Completed:

```text
meaning choice
-> 未学习 / 学习中 / 复习中
-> 10-minute delayed review
-> 已通关
```

Next:

1. Confirm hosted Supabase through migration 014.
2. Add result-screen and repeat-round Android tests.
3. Implement Band 4→4.5 upgrade exam.
4. Deliver V1.1 active-recall questions and then enable `已掌握`.
