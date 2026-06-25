# KuaKua Duck — Codebase Index

This is the single must-read file for any developer or AI assistant starting work on this project.
Authoritative project rules and phase status live in `CLAUDE.md` at the repo root; this file adds
the file map, architecture context, legacy boundaries, and coding conventions needed to navigate
the codebase without touching the wrong things.

---

## Quick orientation

| Concern | Where to look |
|---|---|
| Project rules & phase status | `CLAUDE.md` |
| Android architecture | `docs/architecture/APP_ARCHITECTURE.md` |
| Database schema & RPC contracts | `backend/supabase/migrations/` (apply in filename order) |
| Level / spaced-review design | `docs/plans/LEVEL_AND_SPACED_REVIEW_FINAL_DESIGN.md` |
| Band upgrade exam design | `docs/plans/BAND_UPGRADE_EXAM_PLAN.md` |
| Content pipeline | `backend/content-pipeline/README.md` |
| Supabase import load order | `backend/content-pipeline/constructed_data/band_4_0_v1/supabase_import/README.md` |
| Product wireframes (Chinese) | `docs/product-prototype-v1/wireframes/` |

---

## File categories

### A — Active production code (route here)

These files are the current, live, routed implementation. When fixing bugs or adding features,
work in these files.

#### Data models — `app/src/main/java/com/example/firsttest/data/model/`

| File | Description |
|---|---|
| `User.kt` | Logged-in user's profile, duck power, streak, props, onboarding status |
| `DuckTitle.kt` | Titles earned at duck-power thresholds (初学鸭 → 传奇鸭) |
| `UserLevel.kt` | IELTS-band-based user level with progress percentage |
| `AbilityRadar.kt` | 5-axis ability scores (current vs previous session) |
| `StreakInfo.kt` | Daily check-in streak with longest/current counts |
| `Prop.kt` | User-owned items: streak shields, challenge keys |
| `Level.kt` | Level structure: band score, unlock/completion status, best star rating |
| `LevelWordStatus.kt` | Per-word status inside a level (new / learning / reviewing) for spaced review |
| `LevelPractice.kt` | **New round system** domain models: `LevelPracticeQuestion`, `LevelPracticeRound`, `LevelPracticeAnswerResult` |
| `PracticeRound.kt` | Generic round models used by legacy ViewModels: `PracticeRound`, `PracticeAnswerResult`, `PracticeRoundResult` |
| `MeaningChoiceOption.kt` | MCQ answer option (optionId, text, isCorrect) |
| `MeaningChoiceQuestion.kt` | Client-assembled MCQ question with 4 shuffled options (used by MeaningChoiceViewModel only) |
| `MistakeWord.kt` | Mistake-notebook entry with Ebbinghaus spaced-repetition stage (0–5) |
| `PracticeCard.kt` | Daily-practice home-screen card (finished / active / locked) |
| `Question.kt` | Server question model used by legacy PracticeViewModel |

#### Remote layer — `data/remote/`

| File | Description |
|---|---|
| `Supabase.kt` | Singleton Supabase client (Auth + Postgrest + Storage) |
| `DbModels.kt` | All `@Serializable` DTO classes for Supabase RPC calls and table reads |

#### Repository interfaces — `data/repository/`

| File | Description |
|---|---|
| `AuthRepository.kt` | Auth state flow (`Restoring / SignedOut / SignedIn`) |
| `OnboardingRepository.kt` | Onboarding flow state; also defines `SessionUserRepository` (refreshCurrentUser) |
| `UserRepository.kt` | User profile flow; `getCurrentUser`, `addDuckPower`, `checkInToday` |
| `VocabRepository.kt` | Levels, `startLevelPracticeRound`, `saveLevelPracticeAnswer`, `completePracticeRound`, word statuses |
| `MistakeRepository.kt` | Mistake-word list (currently fake; Supabase impl pending) |
| `PracticeRepository.kt` | Daily practice cards (currently fake) |

#### Supabase implementations — `data/repository/`

| File | Description |
|---|---|
| `SupabaseAuthRepository.kt` | Real auth via Supabase Email provider |
| `SupabaseOnboardingRepository.kt` | Real onboarding: user bootstrap RPC + onboarding status writes |
| `SupabaseUserRepository.kt` | Real user profile from `profiles` table; implements `SessionUserRepository` |
| `SupabaseVocabRepository.kt` | Live vocab: `startLevelPracticeRound` / `saveLevelPracticeAnswer` / `completePracticeRound` / level word statuses |
| `SupabasePracticeRepository.kt` | Live questions for the legacy `PracticeQuestionScreen`; kept until that screen is retired |

#### Fake implementations — `data/repository/`

| File | Description |
|---|---|
| `FakeUserRepository.kt` | In-memory user state backed by `MutableStateFlow`; used when `USE_REAL_USER = false` |
| `FakeVocabRepository.kt` | In-memory vocab for offline dev and unit tests |
| `FakePracticeRepository.kt` | In-memory daily practice cards mirroring home prototype |
| `FakeMistakeRepository.kt` | In-memory mistake words with 5 Ebbinghaus stages |

#### DI — `di/`

| File | Description |
|---|---|
| `AppRepositories.kt` | Singleton repository instances; toggle flags `USE_REAL_QUESTIONS`, `USE_REAL_VOCAB` |

#### Active UI — `ui/`

| Package | File | Description |
|---|---|---|
| `ui/session/` | `AppSessionViewModel.kt` | Root auth-state flow; chooses live vs fake repos; drives LoginScreen / MainScreen |
| `ui/auth/` | `LoginScreen.kt` | Email login + registration form |
| `ui/auth/` | `LoginViewModel.kt` | Auth state and login/register logic |
| `ui/navigation/` | `MainScreen.kt` | 4-tab shell (Home / 连胜 / 错词本 / 我的); holds `HomeNav` sub-navigation state |
| `ui/home/` | `HomeNav.kt` | Sub-nav sealed interface for the Home tab |
| `ui/home/` | `HomeScreen.kt` | Daily-practice learning path with level cards |
| `ui/home/` | `HomeViewModel.kt` | Level unlock state, card rendering from `VocabRepository` |
| `ui/home/` | `BandExamPlaceholderScreen.kt` | Placeholder shown on band-exam tap (not yet built) |
| `ui/level/` | `LevelPracticeViewModel.kt` | **Official practice ViewModel**: Loading/Answering/Reviewing/Finished/Error; combo on full_correct only |
| `ui/level/` | `LevelPracticeScreen.kt` | **Official practice screen**: MCQ options + cloze `TextField`; review panel shows answerOutcome |
| `ui/onboarding/` | `OnboardingScreen.kt` | New-user questionnaire (exists but not wired to MainScreen yet) |
| `ui/onboarding/` | `OnboardingViewModel.kt` | Bootstrap state, question loading, sense answer persistence |
| `ui/mistakes/` | `MistakesScreen.kt` | 错词本: mistake words with Ebbinghaus badge states |
| `ui/mistakes/` | `MistakesViewModel.kt` | Mistake-word list loading and spaced-review scheduling |
| `ui/streak/` | `StreakScreen.kt` | 连胜: daily streak calendar and check-in |
| `ui/streak/` | `StreakViewModel.kt` | Streak tracking, check-in logic, reward mechanics |
| `ui/profile/` | `ProfileScreen.kt` | 我的: ability radar, level, streak, props, settings |
| `ui/profile/` | `ProfileViewModel.kt` | Profile data from `UserRepository` |
| `ui/profile/` | `AccountViewModel.kt` | Password change, sign-out |
| `ui/practice/` | `PracticeResultScreen.kt` | Round result display (stars, duck power) — shared by new and old flows |

---

### B — Legacy code (keep, do not route to, do not delete)

These files are deliberately preserved as offline-dev references and for unit tests. Nothing in
the active navigation graph routes to them. Do not delete them; do not refactor them to align with
the new system — leave them untouched.

| File | Why kept |
|---|---|
| `ui/practice/PracticeQuestionScreen.kt` | Old card-based drill screen; template for future question types |
| `ui/practice/PracticeViewModel.kt` | Original answer-grading ViewModel; reference for combo logic |
| `ui/practice/PracticeResultViewModel.kt` | Level word-status query after a session |
| `ui/meaning/MeaningChoiceScreen.kt` | Client-assembled MCQ screen; reference for option-list rendering pattern |
| `ui/meaning/MeaningChoiceViewModel.kt` | First ViewModel to call server-side RPCs; reference for round lifecycle |
| `ui/assessment/AssessmentScreen.kt` | Placement assessment screen; superseded by onboarding-to-Level-1 |
| `ui/assessment/AssessmentIntroScreen.kt` | Intro for the old placement flow |
| `ui/assessment/AssessmentViewModel.kt` | Assessment question delivery and `finalize_placement` RPC |
| `ui/scratch/ScratchCardScreen.kt` | Scratch-card prop mechanic; not in current navigation |
| `ui/scratch/ScratchCardViewModel.kt` | Scratch state and streak-shield use |

---

### C — SQL migrations (`backend/supabase/migrations/`)

Apply in filename order (prefix is `YYYYMMDDNNNN`). Supabase runs these sequentially.

| File | What it does |
|---|---|
| `202606210001_create_user_foundation.sql` | `profiles`, `user_level_progress` tables |
| `202606210002_add_profile_username.sql` | `username` column on `profiles` |
| `202606210003_create_ielts_vocabulary_schema.sql` | `words`, `senses`, `levels`, `level_sense_assignments` |
| `202606210004_meaning_choice_answer_rpc.sql` | `save_meaning_choice_answer`, `complete_meaning_choice_session` RPCs |
| `202606220004_questions_import_compatibility.sql` | `questions`, `question_options` import adjustments |
| `202606220005_user_bootstrap_and_onboarding.sql` | `user_sense_mastery`, onboarding bootstrap RPC |
| `202606220006_finalize_placement_rpc.sql` | `finalize_placement` RPC (legacy; to be removed with assessment flow) |
| `202606240007_onboarding_starts_at_level_one.sql` | New users init at Level 1; removes placement dependency |
| `202606240008_fix_level_one_old_sense.sql` | Data fix: incorrect sense assignment on Level 1 |
| `202606240009_spaced_review_practice_rounds.sql` | Core practice-round tables + RPCs: `start_practice_round`, `save_practice_answer`, `complete_practice_round` |
| `202606240011_profile_streak_and_reward_refresh.sql` | Streak counters, duck-power rewards, `refresh_user_profile` RPC |
| `202606240012_conditional_context_hints.sql` | Context-hint eligibility rules on `practice_round_questions` |
| `202606240013_simplify_english_meaning_stems.sql` | English-meaning stem normalization for option question generation |
| `202606240014_level_word_statuses.sql` | `get_level_word_statuses` RPC for level-detail screen |
| `202606240015_level_round_weighted_scoring.sql` | `answer_outcome_enum`; weighted accuracy; 3/2/1/0 stars; duck power formula |
| `202606250016_cloze_question_support.sql` | `question_type_key` on `questions`; cloze grading in `save_practice_answer`; cloze eligibility in `start_practice_round` (40% cap) |

---

### D — Content pipeline (`backend/content-pipeline/`)

| Path | Description |
|---|---|
| `README.md` | **Start here**: numbered script workflow, QA checklist, status definitions |
| `scripts/00_filter_sources.py` … `scripts/13_validate_band45_50_working_package.py` | Numbered pipeline steps; run from project root |
| `constructed_data/` | Human-reviewed intermediate files and Supabase import CSVs |
| `legacy-pilot/` | First 20-word generator — archived, do not use for production |
| `sources/` | Raw source material (ECDICT, IELTS lists, Oxford data) |
| `input/` | Curated input fed into pipeline scripts |
| `reference/` | Reference PDFs stored with the pipeline for traceability |

---

### E — Documentation (`docs/`)

| File / folder | Description |
|---|---|
| `README.md` | Documentation index — start here for docs navigation |
| `MASTER_PROJECT_HANDOFF_PLAN.md` | Full project context for handoff or onboarding |
| `architecture/APP_ARCHITECTURE.md` | Android layer diagram, delivery phases |
| `architecture/DATA_MODEL_AND_CAPACITY.md` | Database schema, volume estimates, table ownership |
| `architecture/CONTENT_DATA_SOURCE_POLICY.md` | Approved content sources, licensing, attribution |
| `content/CONTENT_CONSTRUCTION_BRIEF.md` | Schema and requirements for building learning content |
| `content/WORD_RESEARCH_AND_REVIEW_GUIDE.md` | Human-review workflow for words |
| `plans/BAND_UPGRADE_EXAM_PLAN.md` | Authoritative spec: always-open 40-question upgrade exam, 37/40 pass |
| `plans/LEVEL_AND_SPACED_REVIEW_FINAL_DESIGN.md` | Controlling spec: round composition, spaced review, level completion, mastery |
| `plans/ENGINEERING_QUALITY_FOLLOW_UP.md` | Code-quality follow-up items |
| `product-prototype-v1/` | Original Chinese feature specs + wireframe PNGs |

---

## Architecture rules (summary)

Full rules in `CLAUDE.md`. Key constraints for day-to-day work:

**Layering**
- ViewModels call Repository interfaces only — never Supabase directly.
- Repositories call Supabase via `Supabase.client` — never parse responses in a ViewModel.
- `AppRepositories` is the single DI object — all ViewModels get repositories from it via `factory()`.

**Naming**
- `Fake*Repository` = offline/test implementations; always kept.
- `Supabase*Repository` = live implementations.
- `Db*` prefix = DTO serialization classes in `DbModels.kt`.
- `Ui*` suffix = sealed UI state classes inside ViewModels.

**Practice round system**
- `LevelPracticeViewModel` + `LevelPracticeScreen` (in `ui/level/`) are the **only** officially routed practice flow.
- `MeaningChoiceViewModel` and `PracticeViewModel` remain as legacy references; nothing routes to them.
- Server is the source of truth for correctness — the client never grades its own answers.

**Question types**
- Option (MCQ) questions: `answer_form = 'option'`, `question_type_key = 'option_recognition'`
- Cloze questions: `answer_form = 'keyboard'`, `question_type_key = 'sentence_cloze_typing'`
- Do **not** use `type_code` to distinguish question types — that field is legacy.

**In scope for current work**
- Level practice: grading, mastery updates, round completion, spaced review scheduling.
- Mistake notebook: UI connected to fake data; Supabase impl pending.
- Streak and profile: UI exists; connecting to live Supabase data is the next step.
- Onboarding: screen exists; needs wiring into `AppSessionViewModel` navigation.

**Out of scope until explicitly approved**
- TTS audio.
- Listening question type.
- Word-form / collocation question types.
- Speed bonus, listening bonus, or any combo bonus beyond single-full-correct counting.
- `duck_points`, `near_meaning_count`, `combo_success`, `mastery_success` columns on the DB.

---

## Coding conventions

**Kotlin / Compose**
- State is a sealed interface (`XxxUiState`) defined inside or alongside the ViewModel.
- ViewModel exposes a single `StateFlow<XxxUiState>` collected by the screen with `collectAsState()`.
- Screen composables are stateless: they receive state and callbacks, no side effects inside them.
- Use `viewModelFactory { initializer { ... } }` for ViewModel factories that take constructor args.
- Coroutines: always re-throw `CancellationException`; wrap only at launch sites, not inside helpers.

**File top-comments**
- Every new file that is not obviously self-describing should have a short KDoc comment on the
  primary class explaining *why* it exists and what it owns — not what the code does line by line.
- Example of a good top comment: `/** Source of truth for the current user's spaced-review mastery. Delegates scheduling to the server; never computes next_due_at locally. */`
- Example of a bad top comment: `/** This class gets the user from the database and returns it. */`

**SQL migrations**
- Each migration is a self-contained transaction (`begin; … commit;`).
- `security definer` functions must `set search_path = ''` and use fully-qualified `public.*` names.
- Migration files are never edited after they are applied to a hosted Supabase instance. Fix forward with a new migration.

---

## Current top priorities (as of 2026-06-25)

1. Apply migrations 015 + 016 to hosted Supabase.
2. Verify RLS policies: anonymous reads on `words`, `questions`, `question_options`.
3. Wire `OnboardingScreen` into `AppSessionViewModel` navigation.
4. Connect `MistakesScreen` and `StreakScreen` to live Supabase data (currently using fake repos).
5. Connect `ProfileScreen` to live `SupabaseUserRepository` user stats.
6. Continue Band 4.5 content pipeline (next numbered script in `backend/content-pipeline/`).
