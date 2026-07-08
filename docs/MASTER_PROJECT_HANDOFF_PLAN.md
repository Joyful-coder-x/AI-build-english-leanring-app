# KuaKua Duck — Master Project and Handoff Plan

Document status: repository-derived working baseline with owner decisions  
Prepared: 2026-06-24  
Last status update: 2026-06-24, after Band 4 runtime and result-screen work  
Repository root: `D:\project`  
Intended reader: a product manager, Android engineer, backend engineer, content
lead, QA engineer, or replacement team taking full ownership of the project

## 1. How to use this document

This is the controlling handoff document for the project. It consolidates the
current product specifications, wireframes, Android implementation, Supabase
migrations, content pipeline, tests, and open implementation plans.

Repository code and migrations remain the source of truth for behavior that is
already implemented. This plan is the source of truth for:

- the intended product outcome;
- the verified project status as of 2026-06-24;
- the remaining work and its recommended order;
- dependencies and acceptance criteria;
- decisions that still require the owner;
- the materials required for a complete handoff.

Status labels used throughout:

- **Implemented:** present in current application or migration code.
- **Partial:** a usable portion exists, but the end-to-end requirement is not complete.
- **Specified:** documented or designed but not implemented.
- **Candidate data:** generated data that still requires review or enrichment.
- **TBD:** no reliable answer exists in the repository; the owner must decide.

Do not mark a feature complete because a screen exists. A feature is complete
only when its UI, backend behavior, persistence, error states, tests,
documentation, and acceptance checks are complete.

## 2. Executive summary

### 2.0 Current implementation status

The repository currently provides a testable Band 4 prototype path:

```text
username/password authentication
-> onboarding to Level 1
-> Band 4 Level 1–54 learning path
-> server-created 20-question rounds
-> server-side grading and persisted answer history
-> mistakes and spaced-review scheduling
-> result, Level word-status list, and repeat-round action
-> persisted rewards and daily streak
```

Repository implementation status:

| Area | Status |
|---|---|
| Complete Band 4 content | Implemented: 54 Levels, 1,465 senses, 4,395 questions |
| Hosted Band 4 import | Verified `READY`, 151 checks passed, 0 warnings/failures before migrations 011–014 |
| Fixed practice rounds | Implemented by migration 009 and Android integration |
| Conditional context hints | Implemented by migration 012; used for explicit multiple meanings or after 3 wrong answers |
| Simplified English meaning display | Implemented by migration 013 |
| Duck power and daily streak | Implemented by migration 011 and Android profile refresh |
| Result word list/status | Implemented by migration 014 and Android result UI |
| Repeat 20-question round | Implemented; starts a new server-computed round |
| Level/band display names | Implemented: e.g. `雅思4分难度：Daily Life`, `People and family (1)` |
| Band 4.5 upgrade exam | Not implemented; current screen is a placeholder |
| Band 4.5 learning content | Not constructed/imported |
| Long-term `已掌握` | Deferred to V1.1 active-recall question types |

Hosted Supabase must be confirmed through migration 014. Apply migrations in
filename order and rerun `backend/supabase/tests/verify_project_installation.sql`.

### 2.1 Product

KuaKua Duck (夸夸鸭AI) is a gamified Android vocabulary-learning application
for Chinese learners preparing for Academic IELTS. The application combines:

- a level-based IELTS vocabulary curriculum;
- daily practice and adaptive review;
- always-open difficulty upgrade exams;
- mistake review using spaced-review concepts;
- streaks, duck-power experience, titles, props, and scratch-card rewards;
- a companion duck that provides contextual encouragement;
- profile, progress, and upgrade-exam reporting.

The current repository is a functioning Android prototype connected to
Supabase. It is not yet a production-complete application.

### 2.2 Confirmed technical direction

| Area | Current decision |
|---|---|
| Client | Android only |
| Language | Kotlin |
| UI | Jetpack Compose |
| Architecture | MVVM plus Repository |
| Backend | Supabase Auth, Postgres/PostgREST, RPCs, and Storage |
| Async/state | Kotlin coroutines and Flow |
| Minimum Android version | API 24 |
| Target/compile SDK | 36 |
| Primary IDE | Android Studio |
| Content construction | Python pipeline plus human review |
| Runtime content | Supabase |
| Initial scale assumption | Up to approximately 5,000 active/registered users |

### 2.3 Current delivery condition

Verified on 2026-06-24:

- `.\gradlew.bat assembleDebug` succeeds.
- The production Android source compiles and a debug APK can be assembled.
- Latest recorded debug APK:
  `app/build/outputs/apk/debug/app-debug.apk`, SHA-256
  `B61D6312C3D5866A3C1B3730DF04F30E624AD204D707EB477B8EEF51434A3041`.
- `.\gradlew.bat test` succeeds with 72 unit tests.
- Android onboarding now routes directly to Level 1/home after the fifth
  answer; migration `202606240007_onboarding_starts_at_level_one.sql` must be
  applied to Supabase for the server behavior to match.
- The working tree contains a large uncommitted reorganization and feature
  implementation. It must be stabilized and committed before another person
  can safely continue.
- Real Supabase authentication, user bootstrap, onboarding persistence,
  legacy placement RPCs, vocabulary reads, and meaning-choice persistence code
  exist.
- Several visible features still use fake or in-memory state.
- The reviewed five-level content package contains 225 words/senses and 675
  questions.
- A complete Band 4.0 engineering package now exists for Levels 1–54 with
  1,465 unique senses, 2,930 examples, 4,395 questions, and 11,720 choice
  options. Levels 1–5 preserve the reviewed package; Levels 6–54 are
  deterministic source-backed prototype content suitable for engineering and
  product testing, with public-release human editorial review still pending.
- The result screen now exposes the current Level word list and authoritative
  learner state (`未学习`, `学习中`, `复习中`, `已掌握`), due status, and wrong
  count through `get_level_word_statuses(level_number)`.
- The result screen has `再练一轮（重新组题）`; it creates a new immutable
  server round from updated due reviews, mistakes, difficulty, and new-word
  priorities.
- Contextual Chinese-definition questions are reserved hints. They are
  preferred for explicitly marked multiple-meaning senses, or after the same
  learner has recorded at least three wrong answers for that sense.
- Duck power is persisted server-side and refreshed after completion. Daily
  streak fields and idempotent once-per-calendar-day streak updates are in
  migration 011.
- A 10,000-headword, 240-level candidate curriculum exists, but 8,732 rows are
  flagged for human review and it is not production-ready.

### 2.4 Approved delivery target

The approved and final target is an **industry-standard Android prototype**.
It must demonstrate that the owner can design and build a complete, running
application with a real Android client, authentication, database, persisted
user state, content pipeline, testing, documentation, and maintainable
architecture.

The final proof of concept must include **two fully functional IELTS curriculum
bands: 4.0 and 4.5**. “Fully functional” means the content is reviewed,
validated, imported, playable, persisted, and covered by the required
application, database, and pipeline tests.

The project intentionally stops at prototype level. It is not intended to be
published, commercially operated, or treated as a live public service.

The proof-of-concept milestone must prove this complete loop across the
available levels in both bands:

```text
Install app
  -> register/sign in
  -> resume-safe onboarding
  -> begin at Level 1 in 雅思 4 分难度
  -> load an unlocked level
  -> complete persisted practice
  -> take an always-open 40-question upgrade exam
  -> pass with at least 37/40 and unlock the next difficulty
  -> update progress, duck power, streak, and mistakes atomically
  -> close and reopen app
  -> observe the same persisted state
  -> sign out and sign back in
```

The architecture and data model must follow conventions appropriate to a
future real-world application: separation of concerns, repository boundaries,
database migrations, access control, transactional persistence, tests,
reproducible setup, and clear documentation. This is an engineering-quality
standard, not a commitment to implement real-world operations.

Do not add requirements solely for public deployment, commercial operation,
legal rollout, customer support, paid scaling, app-store publication, or
production incident management.

## 3. Product objectives and boundaries

### 3.1 Primary objective

Provide Chinese Academic IELTS learners with a structured, motivating way to
learn and retain vocabulary through level-based practice, feedback, and
review.

### 3.2 Proof-of-concept outcomes

The MVP must allow a learner to:

1. Create and access an account.
2. Complete onboarding and begin at Level 1 in 雅思 4 分难度.
3. See the current IELTS curriculum position and unlocked learning level.
4. Complete at least one real, server-backed practice flow.
5. Receive a deterministic score, star rating, and duck-power reward.
6. Have answers, progress, mistakes, and daily check-in survive app restarts.
7. Review due mistakes.
8. View basic profile, level, streak, and progress information.
9. Sign out and later restore the same account state.

### 3.3 Explicit prototype exclusions

Defer features that do not materially improve the proof that the core
application works:

- iOS;
- web client;
- WeChat, QQ, Apple, phone/SMS, and multi-provider account linking;
- public social/community features;
- subscriptions and payments;
- the full set of challenge modes;
- advanced runtime AI explanations;
- production push-notification campaigns;
- custom avatar upload;
- an administrator web console;
- General Training IELTS curriculum;
- all 14 proposed question types;
- the complete 10,000–12,530-word curriculum.
- public app-store deployment;
- commercial operation and payments;
- production customer-support processes;
- paid infrastructure scaling;
- formal legal or independent security review;
- production service-level agreements and incident rotations.

These exclusions create a finishable and demonstrable prototype. The original
specifications remain design references, not commitments for implementation.

### 3.4 Success measurements

Product targets are not defined in the repository. Use the following as
measurement categories and have the owner provide target values:

| Metric | Required owner input |
|---|---|
| Registration completion | TBD target percentage |
| Onboarding completion | TBD target percentage |
| First practice completion | TBD target percentage |
| Day-1 and Day-7 retention | TBD target percentages |
| Average practice sessions per active learner | TBD |
| Practice completion/error rate | TBD |
| Content-error report rate | TBD |
| Crash-free sessions | Recommended beta threshold: at least 99% |
| API/RPC failure rate | TBD |
| Data-loss incidents | Target: zero |

## 4. Users and stakeholders

### 4.1 Primary user

Chinese-speaking learners preparing for Academic IELTS who need:

- a guided vocabulary path;
- Chinese support for meaning and examples;
- practice across recognition and production skills;
- visible progress and motivational feedback;
- review of weak or forgotten words.

The content specification spans learners approximately from IELTS band 4.0
through band 8.0.

### 4.2 Secondary users

- Content reviewers validating English, Chinese, IELTS relevance, sources, and
  question quality.
- Project operators investigating feedback, content errors, and account issues.
- Developers maintaining Android, Supabase, and the content pipeline.

### 4.3 Required ownership assignments

The repository contains no reliable ownership/contact list. Fill this before
handoff.

| Responsibility | Named owner | Backup | Approval authority |
|---|---|---|---|
| Product scope and priorities | TBD | TBD | TBD |
| Product acceptance | TBD | TBD | TBD |
| Android engineering | TBD | TBD | TBD |
| Supabase/database | TBD | TBD | TBD |
| Content pipeline | TBD | TBD | TBD |
| English content review | TBD | TBD | TBD |
| Chinese translation review | TBD | TBD | TBD |
| UX/UI design | TBD | TBD | TBD |
| Security/privacy | TBD | TBD | TBD |
| Release and store account | TBD | TBD | TBD |
| Production incidents | TBD | TBD | TBD |

## 5. Source materials and precedence

### 5.1 Main repository sources

- `README.md`: repository map and common commands.
- `CLAUDE.md`: engineering constraints and an older status summary.
- `docs/product-prototype-v1/feature-specifications/`: original product
  requirements in Word documents.
- `docs/product-prototype-v1/wireframes/`: product flows and screen references.
- `docs/architecture/APP_ARCHITECTURE.md`: original architecture and phase plan.
- `docs/architecture/DATA_MODEL_AND_CAPACITY.md`: shared content model and scale.
- `docs/architecture/CONTENT_DATA_SOURCE_POLICY.md`: earlier source policy.
- `backend/content-pipeline/DATA_CONSTRUCTION_SPEC.md`: current curriculum
  construction direction.
- `docs/content/CONTENT_CONSTRUCTION_BRIEF.md`: detailed content/schema brief.
- `docs/content/WORD_RESEARCH_AND_REVIEW_GUIDE.md`: content review workflow.
- `docs/plans/`: active implementation plans with non-overlapping ownership;
  start with `docs/plans/README.md`.
- `backend/supabase/migrations/`: actual database definition and RPC behavior.
- `app/src/main/`: actual Android behavior.
- `app/src/test/`: intended unit coverage.

### 5.2 Conflict precedence

When sources disagree:

1. Current migrations win for database behavior.
2. Current Android code wins for implemented client behavior.
3. `DATA_CONSTRUCTION_SPEC.md` wins for the newest content-construction
   direction, subject to the unresolved policy conflicts in Section 14.
4. Product specifications define desired behavior not superseded by an
   explicit product decision.
5. Old phase checklists and TODO comments are evidence, not current truth.

## 6. Verified implementation inventory

### 6.1 Android foundation — Implemented

- Single Android application module.
- Kotlin and Jetpack Compose.
- Material 3 theme.
- MVVM-style ViewModels and repository interfaces.
- Manual dependency injection through `AppRepositories`.
- Supabase SDK integration for Auth, PostgREST, and Storage.
- Internet permission and an auth deep-link intent for
  `kuakuaduck://auth`.
- Four main tabs: Home, Streak, Mistakes, and Profile.
- Debug APK build.

### 6.2 Authentication and app bootstrap — Partial

Implemented:

- Username normalization.
- Username/password registration and sign-in through Supabase Auth.
- Supabase-compatible deterministic placeholder email generated from username.
- Session observation and restore state.
- Sign-out.
- Password-change repository method.
- Real `SupabaseUserRepository`.
- Root session state machine.
- Server-backed bootstrap state.
- Profile load retry after signup.
- Login/registration Compose screen and ViewModel.

Not complete:

- No real user email is collected.
- No password recovery is possible with placeholder `.invalid` emails.
- No email confirmation.
- No phone/SMS or social provider login.
- No verified production error-message matrix.
- No account deletion workflow.
- No provider linking.
- No production legal-document screens.
- `docs/plans/ACCOUNT_AND_USER_DATA_PLAN.md` is the current account/auth
  planning document; reconcile backend README auth details against it as the
  production auth policy is finalized.

### 6.3 Onboarding and upgrade exams — Onboarding implemented; exam pending

Implemented:

- Five-question onboarding UI.
- Stable answer codes.
- Server RPC to save one ordered answer at a time.
- Resume/bootstrap state with current question index.
- New-user onboarding now finalizes directly to Level 1/home.
- A legacy initial-assessment screen/RPC remains as compatibility code.
- The Band upgrade-exam entry is visible, but its screen is a placeholder.

Approved target:

- New users do not take an initial placement assessment.
- Completing onboarding starts the learner at Level 1 in `雅思 4 分难度`.
- Every transition to the next difficulty uses an always-open 40-question
  upgrade exam built from the preceding difficulty.
- Strictly greater than 90% is required: at least 37/40.
- Passing completes/unlocks the source and earlier progression and unlocks the
  first level of the target difficulty.
- Failure has no progression penalty and attempts are unlimited.
- The full canonical rules are in
  `plans/BAND_UPGRADE_EXAM_PLAN.md`.

Still required:

- Remove the legacy initial-assessment gate and generated IELTS-score report.
- Replace profile reassessment with upgrade-exam entry points.
- Replace hard-coded placement mapping with server-owned upgrade-exam
  completion.

### 6.4 Home and learning path — Band 4 implemented

Implemented:

- Home screen and level cards.
- Level list read from Supabase.
- Level click launches meaning-choice practice.
- Home sub-navigation for practice, result, and scratch card.
- Real per-user unlocking/progress from `user_level_progress`.
- Band 4 Levels 1–54, grouped topic labels, completion/session statistics.
- Completed Levels can be reopened for a fresh review round.

Still partial/fake:

- Daily practice card layout is returned by `FakePracticeRepository`.
- The separate generic daily-practice card layout remains fake.
- Multiple learning-path card types are prototypes rather than persisted
  activities.

### 6.5 Practice — Core Band 4 flow implemented

Implemented:

- Keyboard and multiple-choice practice UI.
- Meaning-choice flow built from level sense assignments.
- Correct/incorrect state, response timing, combo, star calculation, result
  screen, and duck-power display.
- RPC clients for meaning-choice answer saving and session completion.
- Backend migrations defining meaning-choice persistence RPCs.
- Immutable server-created rounds with no duplicate senses.
- Server-side correctness, mastery transitions, mistakes, rewards, and
  idempotent completion.
- Conditional context hints for multiple meanings or three recorded wrong
  answers.
- Result-screen Level word list/status and repeat-round action.

Not complete:

- The older generic practice flow does not persist sessions, answers, progress,
  mistakes, or rewards.
- Scoring behavior exists in more than one flow and needs one authoritative
  rules implementation.
- Hosted verification is required after applying migrations 011–014.
- Only a subset of proposed question types is implemented.
- Audio, voice input, AI explanation, detailed word cards, and report-error
  workflows are incomplete.

### 6.6 Mistake and review scheduling — Backend implemented, notebook UI partial

Implemented:

- Mistake list screen, sorting/state presentation, badges, and empty state.
- Database table `mistake_senses` exists.
- Meaning-choice answer RPC can add/update a wrong sense.
- Due reviews and mistakes participate in server round assembly.

Missing:

- The standalone mistake-list UI still uses a fake repository.
- Real Supabase mistake repository.
- Word-detail navigation.
- Persistent list refresh after a wrong answer.

Implemented learning rules:

- The exact sense states, review stages, due intervals, limited regression,
  level-completion rule, and V1.0/V1.1 mastery boundary are defined in
  `docs/plans/LEVEL_AND_SPACED_REVIEW_FINAL_DESIGN.md`.
- `user_sense_mastery` owns scheduling; `mistake_senses` is an active/history
  display index and must not maintain a second algorithm.

### 6.7 Streaks and rewards — Core counters implemented

Implemented:

- Streak/calendar screen.
- Duck-title thresholds.
- Scratch-card UI and reward generation.
- Server-owned duck power and once-per-calendar-day streak persistence.
- Android profile refresh after round completion.

Missing:

- Props and a general reward ledger.
- Maximum prop rules.
- Missed-day and protection-item behavior.
- Goal selection and goal progression.
- Persistent scratch-card eligibility and reward history.

### 6.8 Profile and settings — Partial

Implemented:

- Profile screen.
- Basic profile data from Supabase.
- Sign-out entry.
- Legacy reassessment entry, to be replaced by upgrade-exam access.
- Real duck-power and streak counters.
- Transitional zero/default data remains for radar and props.

Missing:

- Real aggregated learning state.
- Profile editing.
- Avatar selection/unlocks.
- Notification, sound, haptics, and privacy settings.
- Feedback submission.
- Password-change UI completion/verification.
- Account deletion.
- Terms, privacy, about, acknowledgements, and version/update pages.
- Upgrade-exam attempt history and results.

### 6.9 Companion content — Partial

The original specification defines time-, return-, and achievement-sensitive
duck messages. Current home behavior contains companion presentation, but the
complete priority and randomization rules have not been verified as
implemented or persisted. Treat this as polish after the core learning loop.

### 6.10 Backend schema — Band 4 substantial and testable

Current migrations define:

- profiles;
- user settings and consent;
- onboarding profiles;
- bands, topic clusters, and levels;
- content sources;
- words and senses;
- level assignments;
- word forms and pronunciations;
- examples, collocations, lexical relations, and usage evidence;
- question types, questions, and options;
- user level progress;
- practice sessions and answers;
- sense mastery and skill progress;
- mistake senses;
- onboarding/bootstrap RPCs;
- legacy placement RPC, to be superseded by upgrade-exam RPCs;
- meaning-choice answer/session RPCs;
- immutable practice rounds and round-question snapshots;
- spaced-review state transitions and conditional context hints;
- profile streak fields and Level word-status RPC;
- Row Level Security enablement and policies.

Still required:

- Apply and verify all migrations against the actual target Supabase project.
- Record the exact production project/reference and migration state.
- Execute two-user and anonymous RLS tests.
- Add upgrade-exam structures and the remaining settings/feedback/deletion
  structures selected for MVP.
- Add operational backups and recovery instructions.
- Establish migration rollback/repair procedure.
- Keep `docs/plans/` limited to active, non-overlapping plans; delete or merge
  stale SQL plans when implementation makes them obsolete.

### 6.11 Content — Band 4 engineering package complete

Production-style reviewed slice:

| Artifact | Count |
|---|---:|
| Content sources | 6 |
| Topic clusters | 62 |
| Levels metadata | 240 |
| Words | 225 |
| Word senses | 225 |
| Word forms | 322 |
| Pronunciations rows | 224 |
| Level assignments | 225 |
| Usage-evidence rows | 189 |
| Original bilingual examples | 450 |
| Collocations | 34 |
| Questions | 675 |
| Question options | 1,800 |

This corresponds to five levels with 45 new sense-level words per level.

Complete Band 4 engineering package:

| Artifact | Count |
|---|---:|
| Levels | 54 |
| Unique words/senses | 1,465 |
| Word forms | 1,747 |
| Pronunciation rows | 1,453 |
| Assignments | 1,465 |
| Usage-evidence rows | 1,429 |
| Examples | 2,930 |
| Questions | 4,395 |
| Choice options | 11,720 |

This package is suitable for prototype engineering tests. Levels 6–54 still
require human editorial review before any public-release claim.

The approved curriculum interpretation is **approximately 80 learning slots
per level, not 80 entirely new words**. Levels 1–5 use 45 new senses, 5
form/collocation slots, and 30 review/context slots. Later levels use the
configured `new_sense_target`, `collocation_target`, and `review_target`;
content must not be padded with weak words to force a fixed new-word count.

The controlling progression and review specification is
`docs/plans/LEVEL_AND_SPACED_REVIEW_FINAL_DESIGN.md`. Its core invariant is
that a single-round accuracy is not a mastery score: level completion permits
progression, while long-term mastery requires successful spaced recall across
time and, beginning in V1.1, active recall.

Candidate full curriculum:

- 10,000 unique headwords;
- 240 levels;
- 62 topic clusters;
- 1,268 automatically accepted placements;
- 8,732 human-review rows;
- definitions, sense selection, examples, translations, collocations, audio,
  and questions are not complete for the full candidate set.

The 10,000-headword candidate must not be presented as finished production
content.

Complete Band 4.0 engineering package:

| Artifact | Count |
|---|---:|
| Levels | 54 |
| Unique words/senses | 1,465 |
| Word forms | 1,747 |
| Pronunciation rows | 1,453 |
| Original/prototype bilingual examples | 2,930 |
| Questions | 4,395 |
| Choice options | 11,720 |

The package is generated by
`backend/content-pipeline/scripts/10_build_band4_content.py`, validated by
`11_validate_band4_content.py`, and exported under
`constructed_data/band_4_0_v1/supabase_import/`.

Levels 1–5 remain the stronger editorial baseline. Levels 6–54 use ECDICT
definitions/translations, Oxford POS guidance, deterministic original
prototype examples, and explicit bilingual fallback definitions when no
trustworthy same-POS English definition exists. These later levels are ready
for end-to-end application testing but must not be represented as having
completed an independent human editorial review.

## 7. Target MVP functional requirements

### 7.1 Account

`AUTH-001` A new user can register with a unique username and password.  
`AUTH-002` A registered user can sign in after an app restart.  
`AUTH-003` Invalid credentials and duplicate usernames produce actionable
messages without exposing private account data.  
`AUTH-004` A signed-in user can sign out and cached private data is cleared.  
`AUTH-005` The prototype clearly documents that password recovery is not
available under the placeholder-email username implementation.  
`AUTH-006` Terms/privacy acceptance is versioned and recorded.  

### 7.2 Onboarding and difficulty progression

`ONB-001` The five answers are saved incrementally with stable codes.  
`ONB-002` Closing the app resumes at the correct onboarding question.  
`ONB-003` Completing onboarding atomically unlocks Level 1 and routes home.  
`ONB-004` New users are not assigned an official or estimated IELTS score.  
`ONB-005` Learner-facing difficulty labels use `雅思 # 分难度`; internal code
may continue to use `band`.  

### 7.3 Upgrade exams

`EXAM-001` Every difficulty transition has a permanently available upgrade
exam.  
`EXAM-002` The exam contains 40 unique randomized questions from the preceding
difficulty.  
`EXAM-003` Question and option order are randomized.  
`EXAM-004` Selection uses all available listening, speaking, reading, and
writing categories and reports the actual mix.  
`EXAM-005` At least 37/40 is required; 36/40 fails.  
`EXAM-006` Failed attempts do not remove progress and attempts are unlimited.  
`EXAM-007` Passing marks source-and-earlier levels complete for progression and
unlocks only the first level of the target difficulty.  
`EXAM-008` Finishing all source levels still requires the upgrade exam.  
`EXAM-009` Attempts, answers, results, and unlock changes persist server-side
and completion is idempotent.  
`EXAM-010` Results state that the exam controls app learning progress and is
not an official IELTS score.  

### 7.4 Learning path

`PATH-001` The app loads the learner's unlocked/current levels from the server.  
`PATH-002` Locked levels cannot start practice.  
`PATH-003` A level displays its title, status, and progress from persisted data.  
`PATH-004` A level's completion denominator contains only its target new
senses, never collocation or historical-review slots.  
`PATH-005` The completion threshold is
`ceil(new_sense_target * 0.90)` target senses with a correct delayed review at
least 10 minutes after first correctness, after every target sense has
appeared.  
`PATH-006` Completing the unlock condition exposes the correct next level
without declaring every sense mastered.  
`PATH-007` Learner-facing states use `未解锁`, `待开始`, `学习中`, `巩固中`,
and `已通关`; V1.0 does not display `已掌握`.  

### 7.5 Practice and persistence

`PRAC-001` Practice questions are scoped to the selected level/activity.  
`PRAC-002` Each answer records target, selected answer, correctness, and
response time.  
`PRAC-003` Session completion records totals, stars, rewards, and progress in
one server-controlled transaction.  
`PRAC-004` Retrying a timed-out completion request does not duplicate rewards.  
`PRAC-005` Wrong answers update the mistake notebook.  
`PRAC-006` V1.0 uses server-created immutable rounds of at most 20 questions.  
`PRAC-007` Overdue reviews outrank new senses; new senses occupy at most 60%
when reviews are due and are omitted when more than 20 reviews are overdue.  
`PRAC-008` A round contains no duplicate `sense_id`; a current-round mistake
becomes highest priority for the next round rather than changing the active
round snapshot.  
`PRAC-009` Correct review updates `user_sense_mastery` and scheduling only when
the stored due time has been reached.  
`PRAC-010` Recognition-only V1.0 practice can reach `复习中` but cannot create
long-term mastery.  
`PRAC-011` The app handles empty content, network loss, expired session, and
server rejection.  

### 7.6 Progress and rewards

`PROG-001` Duck power is persisted and cannot be directly forged by the client.  
`PROG-002` A qualifying session creates at most one check-in per day.  
`PROG-003` Streak and longest streak use a declared timezone policy.  
`PROG-004` Props and scratch-card rewards use an auditable transaction ledger.  
`PROG-005` Title changes are derived deterministically from duck power.  

### 7.7 Mistake review

`MIST-001` Wrong senses appear after refresh/restart.  
`MIST-002` Due mistakes can launch a targeted review session.  
`MIST-003` `user_sense_mastery` is the only source of review stage and due
time; `mistake_senses` is an active/history display index.  
`MIST-004` A resolved mistake remains in history and reactivates after another
wrong answer.  
`MIST-005` Review scheduling, limited stage regression, and mastery rules are
documented and tested.  

### 7.8 Profile

`PROF-001` Profile displays real account and progress data.  
`PROF-002` User can change supported profile fields.  
`PROF-003` Current difficulty, level, and upgrade-exam history match backend
state.  
`PROF-004` User can sign out.  
`PROF-005` Required privacy/support links are accessible.  

## 8. Architecture and engineering plan

### 8.1 Keep

- Kotlin, Compose, MVVM, and Repository.
- Fake repositories for tests and previews.
- Supabase RPCs for transactional or protected mutations.
- Supabase read-only table/view access for safe public/shared content.
- Stable domain models separated from database DTOs.

### 8.2 Change before feature expansion

1. Replace constant runtime fake/real switches with an explicit debug/demo
   configuration or build variant.
2. Introduce Navigation Compose before adding more nested flows or deep links.
3. Separate profile/account data from learning progress and rewards.
4. Move duck-power, streak, and prop mutation out of `UserRepository`.
5. Centralize scoring rules so generic practice and meaning-choice practice
   cannot diverge.
6. Add one server transaction for session completion and rewards.
7. Add environment validation for missing Supabase configuration.
8. Ensure UI text/source files are consistently UTF-8.

### 8.3 Recommended repository boundaries

- `AuthRepository`: session and identity operations.
- `ProfileRepository`: profile and account-visible fields.
- `OnboardingRepository`: onboarding/bootstrap and Level-1 initialization.
- `CurriculumRepository`: bands, levels, assignments, content.
- `PracticeRepository`: create session, fetch questions, save/complete session.
- `ProgressRepository`: read level progress, mastery, and upgrade-exam results.
- `UpgradeExamRepository`: start/resume attempts, save answers, complete exams,
  and read attempt history.
- `MistakeRepository`: due mistakes and review state.
- `RewardRepository`: streaks, check-ins, props, reward ledger.
- `SettingsRepository`: user preferences and device registration.

Do not split these immediately if it produces a large refactor without
delivery value. Split them as each real backend path is implemented.

### 8.4 Environment model

Define three environments:

| Environment | Purpose | Data |
|---|---|---|
| Local/demo | UI development and unit tests | Fake repositories |
| Staging | Integration, RLS, migration, and beta QA | Non-production Supabase |
| Production | Approved release | Production Supabase |

TBD: identify the existing Supabase project as staging or production. Do not
assume a project containing prototype accounts is safe for production.

## 9. Database and backend completion plan

### Backend Phase A — stabilize existing migrations

1. Inventory the actual Supabase migration state.
2. Back up the project.
3. Apply migrations in filename order to a clean staging project.
4. Load the five-level import package.
5. Run SQL tests and two-user RLS checks.
6. Test registration trigger, bootstrap, ordered onboarding, Level-1
   initialization, answer save, and session completion.
7. Record expected grants and policies.

Acceptance:

- A clean database can be recreated from repository files.
- User A cannot read or mutate User B's private records.
- Anonymous users can access only intentionally public content.
- RPCs reject unauthenticated calls.

### Backend Phase B — one authoritative practice transaction

Reconcile generic practice and meaning-choice persistence. The final
completion operation must:

- verify the authenticated user;
- create or resolve a session idempotently;
- validate submitted questions/senses;
- store answers;
- calculate or validate score/reward server-side;
- update mastery;
- update mistakes;
- update level progress/unlocks;
- add one check-in if eligible;
- grant reward transactions;
- return the resulting user/session state.

Do not trust client-supplied duck power as authoritative.

### Backend Phase C — missing MVP user state

Add or finalize:

- streaks/check-ins;
- props and reward transactions;
- upgrade-exam attempts, answers, and unlock transactions;
- required settings;
- feedback/content-error reports if included in beta;
- account deletion if required for the release channel.

### Backend Phase D — operational readiness

- Scheduled backups and restore test.
- Error/slow-query monitoring.
- Migration ownership and release process.
- Secrets and key-rotation procedure.
- Storage bucket policies.
- Data retention and deletion behavior.
- Incident contact and escalation.

## 10. Android completion plan

### Android Phase A — restore a trustworthy baseline

1. Keep the repaired `finalizePlacement` test fakes passing until the legacy
   placement interface is removed.
2. Run all unit tests.
3. Fix failures rather than lowering assertions.
4. Run `assembleDebug`.
5. Manually execute registration through persisted practice on staging.
6. Commit the repository reorganization and current feature set in reviewable
   commits.
7. Update stale architecture/status documentation.

Exit criteria:

- Clean build.
- All current unit tests pass.
- No accidental credential files are tracked.
- Another developer can clone and build using the documented setup.

### Android Phase B — complete account/onboarding loop

- Keep username/password authentication for the proof of concept.
- Complete login/registration validation and messages.
- Document that password recovery is unavailable in the proof of concept.
- Verify deep-link behavior if used.
- Remove the initial assessment gate.
- Complete onboarding directly into Level 1/home.
- Add integration tests for bootstrap routing.

### Android Phase C — implement upgrade exams

- Add upgrade-exam entry to each difficulty section.
- Keep every upgrade exam available regardless of level completion.
- Start/resume the server-created 40-question attempt.
- Render the actual category mix and learner-friendly difficulty labels.
- Persist answers and complete the attempt through protected RPCs.
- Apply `37/40` pass behavior and refresh unlocked progression.
- Replace the profile reassessment action with exam history/entry.
- Remove official IELTS-score and unsupported ability-radar claims.

### Android Phase D — real learning path and practice

- Read per-user level state.
- Scope question queries by level/activity.
- Use server session ids.
- Persist answers and completion.
- Refresh profile/progress after completion.
- Handle retry and offline/error states.
- Remove fake card state from the beta path.

### Android Phase E — mistakes, streak, and rewards

- Implement `SupabaseMistakeRepository`.
- Build due-review session.
- Replace local streak/prop mutations with RPC-backed state.
- Persist scratch-card eligibility/reward.
- Verify reward idempotency.

### Android Phase F — profile and prototype polish

- Real progress aggregate.
- Profile editing if included.
- Basic settings.
- Privacy/support links.
- Loading, empty, network, and error states.
- Accessibility and font scaling.
- Back-navigation and process-recreation tests.
- Consistent Chinese copy and visual review against wireframes.

## 11. Content production plan

### 11.1 Freeze policy before scaling

Resolve Section 14 decisions first, especially:

- American versus British canonical English/audio;
- public versus private-study use;
- curriculum size and level/band mapping;
- required human-review rate;
- directly reused versus original examples.

### 11.2 Band 4 engineering gate — completed

Completed evidence:

1. Run all active pipeline stages.
2. Confirm stages 03 and 07 pass.
3. Load the export into a clean staging database.
4. Runtime SQL opened a valid round for every Level 1–54.
5. Review every visible definition, translation, option, example, and
   pronunciation in a representative device test.
6. Correct source data and regenerate; never patch exported CSVs directly.
7. Record reviewer identities and approval.

### 11.3 Curriculum scaling gates

Scale in batches, not all 10,000 at once. Suggested gates:

- Gate 1: levels 1–5, fully reviewed and playable.
- Gate 2: first complete band segment, with review throughput measured.
- Gate 3: 25% curriculum, with automated quality/error reports.
- Gate 4: 50% curriculum and retention/review feedback.
- Gate 5: complete release curriculum.

Each batch requires:

- source/provenance completeness;
- sense and part-of-speech review;
- level/topic review;
- Chinese review;
- original/reusable example review;
- distractor validation;
- question validation;
- audio verification;
- import validation;
- in-app spot check;
- approval record.

### 11.4 Content launch minimum

Approved content direction:

- June 26 engineering checkpoint: **5 complete, reviewed, playable levels**.
- Final proof-of-concept target: **2 complete IELTS curriculum bands**,
  interpreted as bands **4.0 and 4.5**.
- Public release: TBD after production throughput and review quality are
  measured across those two bands.

Under the current candidate curriculum, bands 4.0 and 4.5 contain:

| Band | Candidate headwords | Levels |
|---:|---:|---:|
| 4.0 | 1,512 | 54 |
| 4.5 | 864 | 27 |
| Total | 2,376 | 81 |

The two-band target means production-complete content, not merely candidate
headwords. At the current content ratio, the target is approximately:

| Artifact | Approximate target |
|---|---:|
| Levels | 81 |
| Candidate headwords/senses | 2,376 |
| Bilingual practice examples | 4,752 |
| Questions | 7,128 |
| Choice options | Approximately 19,000 |

Every included sense requires approved definitions, translations, examples,
level assignment, questions, provenance, validation, and required human
review.

Completing 81 production levels is not part of the three-day engineering
sprint. The three-day sprint is the first checkpoint, not final project
completion. At that checkpoint:

- the first 5 levels must be fully functional and real;
- the app may display the wider two-band curriculum structure;
- incomplete levels must remain locked or clearly marked unavailable;
- candidate rows must never be presented as reviewed production content.

After the June 26 checkpoint, measure review time for one complete level and
use that result to schedule the remaining 76 levels. Do not set the final date
until this measured throughput exists.

### 11.5 Definition of a production-complete content level

A level counts toward the two-band target only when all of the following pass:

1. Every new word is represented by an approved lemma, part of speech, and
   unambiguous selected sense.
2. American English spelling and pronunciation policy is followed.
3. English and Chinese definitions are reviewed.
4. At least two usable bilingual examples exist per new sense.
5. Required word forms, collocations, and aliases are reviewed.
6. Source provenance and copyright status are recorded.
7. Questions and distractors are unambiguous and level-appropriate.
8. Automated pipeline validation passes.
9. Human review status is recorded for every required row.
10. Supabase import succeeds without referential-integrity errors.
11. The Android app can load and complete practice for the level.
12. Answer, progress, mastery, and mistake persistence work.
13. Level completion and next-level unlocking work.
14. Unit, SQL/RPC, and relevant integration tests pass.
15. A device/emulator spot check finds no release-blocking content or UI issue.

Generated content that has not completed these gates does not count.

### 11.6 Capacity reality

AI can accelerate source joining, drafting, validation, and issue detection,
but it cannot make unreviewed content production-approved.

Even an unrealistically low average of three minutes of final human review per
headword/sense would require about 119 hours for 2,376 items, before separate
question, example, import, and application review. At the normal availability
of 15 hours per week, the two-band target therefore requires multiple weeks,
not three days.

The project should estimate its final date from measured throughput after one
additional complete level. A preliminary planning range is **12–24 weeks at
15 hours per week**, depending on automation quality, issue rate, and the depth
of review. This is a planning range, not a commitment.

## 12. Testing and quality plan

### 12.1 Required automated checks

- Unit tests for scoring, titles, upgrade-exam thresholds, validation, and
  ViewModels.
- Unit/SQL tests for the exact review-stage transitions, six-result history,
  10-minute delayed-review boundary, and V1.0 mastery ceiling.
- SQL/RPC tests for fixed-round uniqueness and priority, configurable level
  targets, 90% completion, mistake reactivation, and idempotent unlocking.
- Repository mapper tests.
- Supabase SQL/RPC tests.
- Two-user RLS tests.
- Content pipeline validation.
- Import referential-integrity checks.
- Debug and release builds.

### 12.2 Required end-to-end scenarios

1. Fresh install and registration.
2. Existing user sign-in and session restore.
3. Onboarding interruption after every question.
4. New user begins at Level 1 without an initial assessment.
5. Upgrade-exam interruption and restart resumes the same question snapshot.
6. `36/40` fails without changing unlock state.
7. `37/40` passes and unlocks the first level of the next difficulty.
8. Completing all source levels still requires the upgrade exam.
9. Complete correct practice session.
10. Complete partially correct practice session.
11. Wrong answer appears in mistakes.
12. Network loss during answer save.
13. Network loss during session/exam completion and safe retry.
14. Multiple sessions in one day create one check-in.
15. App restart preserves all state.
16. User A cannot see User B data or exam attempts.
17. Sign-out clears visible private state.
18. Missing/empty level or exam content displays an actionable state.
19. A correct answer before the 10-minute due time does not advance review.
20. A 45-new-sense level unlocks at 41 qualifying delayed reviews, without
    waiting one day.
21. Collocation and historical-review slots do not enter the level-completion
    denominator.
22. A 30-day-stage mistake regresses only to the 7-day stage.
23. Recognition-only V1.0 practice never displays or persists `已掌握`.
24. A resolved mistake reactivates after a later wrong answer.

### 12.3 Device and platform matrix

TBD: supported device list.

Minimum beta matrix:

- API 24 or representative low-end supported emulator/device;
- one current mid-range Android device;
- latest target API emulator;
- small and large phone layouts;
- Chinese system language;
- English system language;
- font scaling at 100% and at least one enlarged setting;
- light and dark mode if both are intended to ship.

### 12.4 Release blockers

Any of the following blocks beta:

- build or test failure;
- known cross-user data access;
- duplicate rewards/progress after retry;
- onboarding cannot resume;
- persisted practice state is lost;
- migration cannot recreate staging;
- unresolved critical content-rights issue;
- secrets committed to Git;
- crash in the core user loop.

## 13. Delivery roadmap and dependencies

No budget, staffing level, or deadline exists in the repository. Therefore this
is a dependency-based roadmap, not a calendar promise.

### 13.1 Three-day engineering-foundation sprint — current result

Target window: **June 24–26, 2026**  
Owner: project owner, supported by AI coding assistants  
Playable content delivered: complete Band 4 engineering package  
Final curriculum target after the sprint: fully functional IELTS bands 4.0 and 4.5  

This sprint is an exception to the normal availability of 15 hours per week.
It assumes approximately **30 focused working hours over three days**. If only
15 total hours are available, the sprint must stop after the persistent
account-to-practice demonstration and defer mistake review and presentation
polish.

The sprint established the application and content-production foundation. It
does not complete the final two-band proof of concept. The current real-data
path is:

```text
register/sign in
  -> onboarding
  -> Level 1 in 雅思 4 分难度
  -> load a real Supabase level
  -> answer and complete a real practice session
  -> see the always-open upgrade-exam entry (placeholder only)
  -> persist progress and mistakes
  -> restart/re-login
  -> see the same state
```

The following remain outside the completed foundation:

- app-store release;
- production completion of all 81 levels in bands 4.0 and 4.5;
- all 240 levels or the full 10,000-headword candidate curriculum;
- phone, email recovery, or social login;
- all proposed question types;
- production notifications;
- complete streak-protection and scratch-card economy;
- custom avatars and account linking;
- administrator dashboard;
- final legal, security, and content-rights approval;
- production monitoring and customer support operations.

The detailed Day 1–3 tables below are retained as historical execution notes;
the current authoritative status is Section 2.0 and Section 17.

#### Day 1 — Wednesday, June 24: establish a trustworthy baseline

Goal: produce a passing repository and reproducible staging backend.

| Block | Work | Required result |
|---|---|---|
| 1, 1 hour | Preserve and review the current working tree | No project work is lost; unrelated changes are identified |
| 2, 2 hours | Verify the repaired legacy placement test fakes and full unit suite | `.\gradlew.bat test` passes |
| 3, 1 hour | Run debug build and inspect configuration/secrets | `.\gradlew.bat assembleDebug` passes; no secrets are tracked |
| 4, 3 hours | Recreate or verify staging Supabase from migrations, then load the five-level package | Schema, RPCs, and five levels are available |
| 5, 2 hours | Test registration, sign-in, bootstrap, onboarding answer persistence, and Level-1 initialization | Account reaches home-ready state and Level 1 is unlocked |
| 6, 1 hour | Commit or checkpoint the stabilized state and record failures | Recoverable Day-1 baseline |

Day-1 exit gate:

- tests pass;
- debug APK builds;
- staging is reachable;
- a user can register, resume onboarding, and reach the home screen;
- no unresolved blocker prevents real practice on Day 2.

If the Day-1 gate fails, do not add new UI features. Spend the remaining sprint
on completing and documenting the core vertical slice.

#### Day 2 — Thursday, June 25: complete real learning persistence

Goal: remove fake state from the demonstrated learning path.

| Block | Work | Required result |
|---|---|---|
| 1, 2 hours | Make level unlocking/current-level reads use `user_level_progress` | Home displays server-owned level state |
| 2, 2 hours | Verify/fix meaning-choice question loading for the selected level | Level 1 returns valid real questions and distractors |
| 3, 3 hours | Verify/fix answer and session-completion RPC calls, retries, scoring, and returned state | Answers and completion persist without duplicate rewards |
| 4, 2 hours | Implement the minimum real mistake query/repository | A wrong answer appears after refresh/restart |
| 5, 1 hour | Refresh profile/home state after session completion | Visible progress matches Supabase |
| 6, 1 hour | Add focused unit/SQL tests for the changed paths | Critical persistence rules are covered |

Day-2 exit gate:

- no fake repository is used in the demonstrated account, onboarding, level,
  question, session, progress, or mistake path;
- completion survives process restart and sign-in;
- retrying completion does not visibly duplicate progress;
- the five-level content package can be browsed or queried from the app.

The generic legacy practice-card flow, streak economy, and scratch card may
remain outside the demonstrated path. Hide or clearly label incomplete entries
rather than presenting fake behavior as finished.

#### Day 3 — Friday, June 26: harden, demonstrate, and hand off

Goal: make the proof of concept repeatable and understandable by another
person.

| Block | Work | Required result |
|---|---|---|
| 1, 2 hours | Run the complete manual end-to-end scenario with a fresh user | Core journey succeeds without database intervention |
| 2, 2 hours | Test interruption, restart, wrong answer, sign-out, sign-in, empty data, and network failure | Major failure states are handled or documented |
| 3, 2 hours | Fix only release-blocking bugs and visibly broken copy/layout | Stable demonstration build |
| 4, 1 hour | Run all unit tests, SQL checks, pipeline validation, and debug build | Final evidence is recorded |
| 5, 1 hour | Update README, this plan, setup instructions, and known issues | A new developer can continue |
| 6, 1 hour | Produce final APK and demonstration script | Installable artifact and repeatable presentation |
| 7, 1 hour | Create final checkpoint/tag and inventory deferred work | Clean handoff boundary |

Day-3 exit gate:

- the five-level engineering checkpoint passes;
- all failures and deferred features are explicitly listed;
- the install/build/test procedure has been executed from the documented steps;
- the project can be demonstrated without claiming public-production readiness.

### 13.2 AI-assisted working model

The owner remains accountable for product decisions and final acceptance. AI
assistants accelerate implementation but are not independent project owners.

Recommended responsibilities:

| Tool | Primary use |
|---|---|
| Codex | Repository inspection, implementation, tests, build verification, and plan maintenance |
| Claude Code | Independent code review, edge-case review, and alternative implementation critique |
| VS Code Chat | Small local explanations and editor-scoped assistance when needed |
| DeepSeek | Second opinion on algorithms, SQL, or content-processing logic |

Coordination rules:

1. Use one assistant as the active implementer for a task.
2. Do not let two assistants edit the same files simultaneously.
3. Give reviewers the exact diff and acceptance criteria.
4. Do not accept generated code until tests/builds run locally.
5. Never paste service-role keys, passwords, signing keys, or private user data
   into an AI prompt.
6. Record important decisions in this plan rather than leaving them only in a
   chat transcript.
7. End each work block with a build/test result and a Git checkpoint when safe.

### 13.3 Three-day priority order

When time is short, use this order:

1. Build and test health.
2. Authentication and resumable onboarding.
3. Real level and question data.
4. Transactional answer/session persistence.
5. Persisted mistakes and visible progress.
6. Restart/re-login verification.
7. Documentation and demonstration artifact.
8. Visual polish.
9. Additional features.

Never sacrifice data integrity or access control to add more visible features.

### 13.4 Approved proof-of-concept budget

The minimum required new cash budget for the current three-day proof of concept
is **US$0**, assuming the owner already has a computer, Android device or
emulator, internet access, and access to the listed AI assistants.

| Category | Current budget | Proof-of-concept approach |
|---|---:|---|
| Development labor | $0 cash | Owner develops with AI assistance |
| Supabase hosting | $0 | Stay within the Supabase Free plan limits |
| AI/API usage | $0 additional | Use existing subscriptions or free quotas; do not add runtime AI calls |
| Text-to-speech audio | $0 | Defer generated audio or use Android device TTS for demonstration |
| Content licensing | $0 | Use only the existing approved/reviewed slice and do not claim public distribution rights |
| Human translation/review | $0 cash | Owner review for proof of concept; professional review remains required before public release |
| Design assets | $0 | Reuse existing wireframes, app assets, and Compose UI |
| Google Play account | Not applicable | Install the APK directly |
| Security review | $0 cash | Run repository tests, RLS checks, and manual review; independent review is deferred |
| Legal review | Not applicable | Outside the prototype scope |

Budget guardrails:

- Do not activate paid Supabase, TTS, AI API, asset, or publishing services
  during the sprint without an explicit owner decision.
- Runtime AI functionality must be mocked, deterministic, or deferred.
- Do not buy content to increase the curriculum beyond the existing five-level
  proof-of-concept slice.
- The $0 budget applies to the defined prototype and its direct APK
  demonstration.

### Milestone 0 — repository stabilization

Deliverables:

- passing test suite;
- successful debug build;
- current uncommitted work reviewed and committed;
- setup documentation validated;
- stale status documents corrected.

Depends on: nothing.  
Blocks: every later handoff milestone.

### Milestone 1 — reproducible staging backend — substantially complete

Deliverables:

- clean migration application;
- complete Band 4 import;
- SQL/RLS test evidence;
- environment record;
- backup/restore instructions.

Depends on: Milestone 0.

### Milestone 2 — persistent account-to-practice vertical slice — complete

Deliverables:

- final prototype auth decision;
- working onboarding and Level-1 initialization;
- real level progress;
- one persisted practice type;
- upgrade-exam entry only; exam persistence remains in Milestone 3;
- persisted reward/progress/mistake result;
- state restoration.

Depends on: Milestones 0–1.

### Milestone 3 — upgrade exam and remaining closed-beta loop — in progress

Deliverables:

- Band 4→4.5 upgrade-exam persistence and unlock;
- standalone real mistake-notebook repository/UI;
- props/reward ledger if retained;
- remaining profile aggregates;
- complete error states;
- end-to-end test report.

Depends on: Milestone 2.

### Milestone 4 — final prototype demonstration

Deliverables:

- installable demonstration build;
- demonstration instructions;
- reproducible setup and test evidence;
- known-issues list;
- final prototype acceptance.

Depends on: Milestone 3 and approved five-level content.

### Milestone 5 — two-band prototype completion

Deliverables:

- all 81 levels in bands 4.0 and 4.5 reviewed and validated;
- full two-band import and application verification;
- complete test evidence;
- maintainable handoff documentation;
- final prototype demonstration.

Depends on: the engineering foundation and measured content-review throughput.

## 14. Decisions and contradictions requiring owner resolution

These cannot be safely invented by the next implementer.

### DEC-001 — Authentication strategy — Resolved

Decision: keep username/password authentication for the proof of concept,
using the current Supabase-compatible internal placeholder-email mechanism.

Consequence: password recovery is unavailable and must be documented. A future
public release must migrate to a recoverable identity strategy such as real
email, phone, or an approved identity provider.

### DEC-002 — New-user assessment — Superseded

The earlier assessment/skip decision is replaced by
`plans/BAND_UPGRADE_EXAM_PLAN.md`.

Decision: new users do not take an initial placement assessment. After
onboarding they start at Level 1 in `雅思 4 分难度`.

### DEC-003 — Difficulty progression — Resolved

The hard-coded placement mapping is obsolete. Progression between actual
curriculum difficulties uses upgrade exams and derives source/target level
ranges from `bands` and `levels`.

### DEC-004 — English standard and audio — Resolved

Decision: American English is canonical for spelling, definitions,
pronunciation, examples, answers, and generated audio. British variants may be
stored as recognition/search aliases but are not the primary taught form.

Required follow-up: update the older source-policy document and any validators
or TTS instructions that still require British English.

### DEC-005 — Curriculum launch size

The repository contains:

- a detailed model that once assumed approximately 19,200 placements;
- a current target near 12,530 approved words/senses;
- a 10,000-headword candidate curriculum;
- only 225 production-style reviewed senses.

Set the beta and public-launch content targets.

### DEC-006 — Distribution boundary — Resolved

Decision: the final target is a personal, portfolio-grade,
industry-standard prototype that demonstrates the ability to build a complete
running application.

The architecture should resemble a maintainable real-world application, but
the plan must not require public distribution, production operations, legal
launch work, or commercial readiness. Private-study-only source evidence must
not be represented as publicly licensed.

### DEC-007 — Feature boundary — Resolved

Decision: implement the smallest end-to-end feature set that credibly proves
the complete application architecture and user journey. Additional original
features are included only when they materially strengthen the demonstration
and do not prevent finishing the core proof of concept. Section 3.3 exclusions
are approved for the current phase.

### DEC-008 — Product identity

Resolved:

- English name: **KuaKua Duck**
- Chinese name: **夸夸鸭AI**

Still to confirm:

- Android application id/package;
- store developer entity;
- logo/icon ownership;
- domain and support email.

The current package `com.example.firsttest` is not production-ready.

### DEC-009 — Assessment method — Resolved

The initial assessment is removed. The approved model is an always-open
40-question upgrade exam for each difficulty transition. It uses questions
from the preceding difficulty, requires at least 37/40, and controls only
in-app learning progression. See `plans/BAND_UPGRADE_EXAM_PLAN.md`.

### DEC-010 — Prototype resources and deadline

Provide:

- target engineering-checkpoint date;
- target final prototype date;
- monthly infrastructure budget;
- content-review budget;
- available roles and weekly capacity;

Only then should task durations and staffing assignments be converted into a
calendar plan.

## 15. Risks and responses

| Risk | Probability | Impact | Response |
|---|---|---|---|
| Large uncommitted working tree is lost or becomes unreviewable | High | High | Stabilize, test, and commit immediately |
| Documentation reports obsolete status | High | Medium | Regenerate status from code/migrations and maintain this file |
| Client-local rewards diverge from server state | High | High | Move mutations to transactional RPCs |
| Upgrade exam selects questions outside the source difficulty | Medium | High | Server-side pool validation and SQL tests |
| Upgrade retry duplicates unlock state | Medium | High | Idempotent completion RPC |
| Full curriculum review effort is underestimated | High | High | Batch gates and measured reviewer throughput |
| Content licensing prevents public release | Medium–High | High | Export only approved original/reusable app content |
| Placeholder-email auth prevents recovery | High | Medium–High | Resolve auth decision before wider beta |
| Fake and real repositories mix silently | High | Medium | Explicit environment/build configuration |
| Network retries duplicate rewards | Medium | High | Idempotency keys and server transactions |
| Prototype failures are difficult to diagnose | Medium | Medium | Keep useful logs and reproducible test steps |
| Broad original scope prevents finishing | High | High | Enforce approved MVP exclusions |
| Chinese/English text encoding becomes corrupted | Medium | Medium | UTF-8 checks and device review |

## 16. Handoff package

A handoff is complete only when the receiving person has all of the following.

### 16.1 Repository

- Git remote URL and access.
- Clean or intentionally documented working tree.
- Branch strategy.
- Latest passing commit/tag.
- Known local-only files.
- Build and test commands.
- Android Studio/JDK requirements.

### 16.2 Backend

- Supabase organization/project access.
- Environment classification.
- Migration state.
- Backup location and restoration procedure.
- Anon/publishable key delivery method.
- Service-role key owner; never commit the key.
- Auth provider configuration.
- Redirect/deep-link configuration.
- Storage bucket and policy inventory.
- Test-user procedure.

### 16.3 Android release

- Application id decision.
- Signing keystore owner and secure transfer.
- Versioning policy.
- Play Console access if applicable.
- Store listing and privacy-policy URLs.
- Build/release checklist.
- Rollback plan.

### 16.4 Product/design

- Approved MVP scope.
- Editable design source, not only PNG exports.
- Final copy deck.
- Brand assets and usage rights.
- Screen-state inventory.
- Acceptance owner.

### 16.5 Content

- Source repository/data access.
- Reviewer roster.
- Review rubric.
- Pipeline environment/dependencies.
- Approved batch list.
- Provenance and license log.
- Rejected/known-problem records.
- TTS account/configuration if audio is included.

### 16.6 Operations

- Monitoring dashboards.
- Crash reporting.
- Support contact.
- Incident severity definitions.
- Data-deletion procedure.
- User feedback workflow.
- Content correction/republication procedure.
- Monthly cost review.

Credentials must be transferred through a password manager or the provider's
access-control system, never inside this document.

## 17. First actions for the next owner

Perform in this exact order:

1. Preserve and commit the current working tree.
2. Apply hosted Supabase migrations 011–014 in filename order if not already
   applied.
3. Rerun `verify_project_installation.sql`; require `READY`, 0 warnings, and
   0 failures.
4. Install the latest debug APK and manually verify:
   - duck power and streak refresh;
   - updated Band/Level names;
   - repeat-round navigation;
   - 45-word Level 1 status list;
   - conditional context hints after three wrong answers.
5. Add automated Android tests for the result word-list and repeat actions.
6. Implement the Band 4 to 4.5 upgrade exam end to end.
7. Construct, review, import, and validate Band 4.5 content.
8. Run two-user RLS/RPC tests and full prototype acceptance scenarios.

## 18. Definition of done

### 18.1 Engineering-foundation checkpoint done

The June 26, 2026 engineering-foundation checkpoint is complete when:

- all approved MVP requirements pass;
- debug build succeeds and an installable demonstration build is available;
- automated tests pass;
- staging can be rebuilt from the repository;
- core state survives restart and re-login;
- RLS isolation is verified;
- retries cannot duplicate progress/rewards;
- all 54 Band 4 Levels are importable and runtime-testable;
- a new user starts at Level 1 without an initial assessment;
- one 40-question upgrade exam persists and resumes correctly;
- 36/40 fails and 37/40 passes;
- passing unlocks the next difficulty idempotently;
- known limitations are documented;
- known production gaps are documented;
- the owner can demonstrate the full user journey without manual database
  repair or fake state in the core path.

### 18.2 Two-band proof-of-concept done

The final proof of concept is complete when:

- every checkpoint requirement in Section 18.1 remains satisfied;
- all 81 levels in IELTS bands 4.0 and 4.5 meet Section 11.5;
- all required rows have recorded review status and provenance;
- all two-band imports and validation reports pass;
- learners can progress through both bands using persisted server-owned state;
- the `雅思 4 分难度` to `雅思 4.5 分难度` upgrade exam uses the approved
  source pool and unlock transaction;
- finishing the source difficulty does not bypass its upgrade exam;
- completion and unlock boundaries are tested across the full two-band range;
- automated tests and representative device checks pass;
- no candidate/unreviewed content is presented as production-complete;
- the handoff package identifies how the same process scales to later bands.

### 18.3 Final project boundary

The project ends when the two-band prototype definition in Section 18.2 is
complete. Public launch, commercial operation, app-store submission, legal
release work, paid scaling, and production support are outside this project.

The repository should document obvious future extension points, but no work is
required solely because a hypothetical public deployment might need it.

## 19. Owner input form

Fill this section and keep the answers in this file.

```text
Product owner:
Technical owner:
Content owner:
Final Chinese product name: 夸夸鸭AI
Final English product name: KuaKua Duck
Android application ID: TBD; current `com.example.firsttest` is temporary
Distribution: personal portfolio-grade industry-standard prototype; no public deployment
MVP auth strategy: username and password
Initial assessment: removed; onboarding starts the user at Level 1
Difficulty progression: always-open 40-question upgrade exam; 37/40 passes
Canonical English: American
Engineering-foundation checkpoint date: June 26, 2026
Final two-band proof-of-concept date: TBD after measured per-level review throughput
Team: owner supported by Claude Code, VS Code Chat, Codex, and DeepSeek
Normal availability: 15 hours per week
Three-day sprint capacity assumption: approximately 30 focused hours
Engineering-checkpoint content target: 5 complete levels using the existing reviewed slice
Final proof-of-concept content target: fully reviewed and functional IELTS bands
4.0 and 4.5; 81 levels and approximately 2,376 headwords/senses
Project content target: fully functional IELTS bands 4.0 and 4.5
Approved MVP exclusions: Section 3.3; additional features only when useful to
the proof of concept
Public/beta release dates: not applicable
Monthly infrastructure budget:
Proof-of-concept new cash budget: US$0
Monthly infrastructure budget: US$0 while within Supabase Free plan limits
AI/API budget: US$0 additional; existing access/free quotas only
Text-to-speech budget: US$0; defer or use device TTS
Content licensing budget: US$0 for proof of concept
Content/review budget: US$0 cash; owner review only for proof of concept
Design budget: US$0; existing designs only
Google Play budget: not applicable
Security/legal review budget: not applicable to the prototype
Expected team and weekly capacity: one owner/developer plus AI assistance; 15 hours per week after the sprint
Staging Supabase project:
Production Supabase project:
Support contact:
Privacy/legal owner:
Final acceptance authority:
```
