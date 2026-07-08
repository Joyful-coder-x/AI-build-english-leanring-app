# TODO & Legacy Inventory

Status: reconciled on 2026-07-06 against `CLAUDE.md`,
`LEVEL_1_5_FINAL_PROTOTYPE_GOAL.md`, `LEVEL_1_5_IMPLEMENTATION_CHECKLIST.md`,
current Android source, Supabase migrations/tests, and the Level 1-5 content
package.

Use **Current Master TODO** below as the authoritative active backlog. The
older scan sections are preserved after it for history and legacy/deferred
context, but some of their claims are stale.

Scope update: Phase 1 now uses the combo content plan in
`PHASE_1_COMBO_CONTENT_AND_BAND_EXAM_PLAN.md`: Band 4.0 Levels 1-33 are the
canonical demo backend data source; Levels 1-5 must remain the deep eight-type
learning slice; Levels 6-33 use a lightweight generated question set; and the
Band 4 -> 4.5 upgrade exam is active Phase 1 scope rather than deferred scope.

Product fallback rule: when a Phase 1 product or UX decision is unclear, use
Duolingo as the reference model for behavior: short lessons, one obvious next
action, immediate feedback, visible progress/rewards, recoverable mistakes, and
clear locked/unlocked progression. Do not copy Duolingo's brand, monetization,
social features, or full course structure.

Positioning decision: keep IELTS/Band wording visible in Phase 1. The target
learner is a Chinese student preparing for IELTS because a high enough IELTS
score is the practical signal that they can survive college English in the US.
"College survival" is the outcome and demo narrative; IELTS/Band is the
learner-facing path. Avoid unsupported claims such as official IELTS score
prediction, a complete IELTS course, or a finished Band upgrade exam.

Local verification update, 2026-07-06:
`backend/supabase/manual/run_phase1_local_docker_verification.ps1` passes in a
disposable Postgres container with the Band 4 import. It covers the installation
verifier, combo practice selection, Band upgrade exam, Band 4 unlock chain,
Band 4 runtime, conditional context hints, staged cloze grading, spaced-review,
and practice logging evidence. Android unit tests and debug build pass.
Remaining P0 risk is target Supabase import/migration/manual-device evidence,
not local schema or generated package shape.

Legend:

- `P0`: required for the Level 1-5 final prototype.
- `P1`: important after the Level 1-5 loop works.
- `P2`: future scope; do not block the Level 1-5 prototype.
- `Deferred`: intentionally kept out of scope unless explicitly promoted.

## Current Master TODO

### P0 - Required For Level 1-5 Final Prototype

| Item | Location | What is needed | Acceptance check |
|---|---|---|---|
| Verify latest Supabase migrations in target environment | `backend/supabase/manual/run_phase1_target_verification.ps1` | Confirm the target database has all required migrations through `202607060028_due_review_new_word_gate.sql`. Older notes mention only migrations 015/016 or 024, but Phase 1 now goes through 028. | Target environment can run onboarding bootstrap plus `start_practice_round`, `save_practice_answer`, `complete_practice_round`, `get_level_word_statuses`, streak/prop logic, Band exam RPCs, and generated question payloads without missing schema/function errors. |
| Import canonical Band 4 package into target DB | `backend/supabase/manual/run_phase1_target_verification.ps1`, `backend/content-pipeline/constructed_data/band_4_0_v1/supabase_import/` | Local package now validates after compacting the 1,465 Band 4 senses into 45-ish Level 1-33 study units; import it into the target Supabase database with the target verification runner or README order. | Target DB import succeeds and full Band 4 verifier reports READY/PASS for Levels 1-33 row counts and integrity. |
| Preserve deep Level 1-5 coverage inside Band 4 | `levels_001_005`, `band_4_0_v1`, generated practice RPCs | Confirm Band 4 Levels 1-5 still have 45 new senses each and the eight-type reviewed Level 1-5 content remains available or runtime-generatable. | Level 1-5 deep verifier passes: all eight question types, examples where expected, valid option sets. |
| Enforce lightweight Level 6-33 generated practice mix | `backend/supabase/migrations/`, `start_practice_round`, `pick_practice_question_type` | Local SQL now passes for the compact Level 6-33 lightweight type policy. Re-run against target DB after import. | SQL check shows Level 6+ generated rounds do not contain `open_speaking`, `word_form`, or `reading_comprehension`. |
| Verify SQL progression test for compact Band 4 unlock chain on target DB | `backend/supabase/tests/202607060027_band4_unlock_chain_test.sql` | Local SQL passes for Band 4 Level 1 -> 33 unlock boundaries. Re-run against target DB after import. | Completing each required level unlocks the next level through 33; final Band 4 completion still requires Band exam for 4.5. |
| Verify RLS/read policies against the real target DB | Supabase dashboard / SQL tests | Confirm content tables needed by the app are readable through intended role, and user-private tables are owner-isolated. | Two-user check: users cannot see each other's private rows/rounds; app can read `levels`, `words`, `word_senses`, `questions`, and `question_options` as intended. |
| Verify legacy Profile assessment remains quarantined on target device | `MainScreen.kt`, `ProfileScreen.kt`, `AssessmentScreen.kt`, `AssessmentViewModel.kt` | Local app shell no longer routes to `AssessmentScreen`, Profile no longer shows the reassessment button, and onboarding completion is covered by a Home-ready unit test. Keep the legacy code unreachable unless a future informational assessment replaces it. | Manual demo confirms no action can open legacy assessment or change level unlock/progression through `finalize_placement`; first-run onboarding routes to Home. |
| Verify Band 4 -> 4.5 upgrade exam end to end on target DB/device | `BandUpgradeExamScreen.kt`, `BandUpgradeExamViewModel.kt`, `202607060026_band_upgrade_exam_core.sql` | Local SQL and Android unit tests pass. Run against target DB and manually verify the app flow. | `36/40` fails, `37/40` passes, passing unlocks target level, failed attempts do not alter unlock state, restart resumes active attempt. |
| Verify visible Home refresh after practice completion on target device | `MainScreen.kt`, `HomeScreen.kt`, `HomeViewModel.kt`, `HomeViewModelTest.kt` | Local code now has an explicit Home refresh token when returning from practice/result/Band exam paths. Manual target-DB confirmation is still needed after real round completion. | Complete Level N, return Home, and Level N+1 appears unlocked without app restart. |
| Verify Level progress refresh after practice on target device | `LevelProgressViewModel.kt`, `LevelProgressScreen.kt`, `PracticeResultScreen.kt` | Local code now reloads server word statuses when the Level progress route is reopened, and the post-round result screen has clean return/retry actions. | After a real target-DB round, Level progress shows updated started/reviewing/due statuses. |
| Keep Level progress learner labels clean | `LevelProgressViewModel.kt`, `LevelProgressScreen.kt` | Local UI/counting no longer uses corrupted strings. Status helpers accept backend Chinese labels and English test labels. | Level progress counters and labels render cleanly during manual demo. |
| Keep `LevelPracticeViewModel` coverage passing | `app/src/test/java/com/example/firsttest/ui/level/LevelPracticeViewModelTest.kt` | Added tests for load, option answer, keyboard answer, combo reset, near-meaning, hint retry, assisted correct, reveal/remediation, completion, user refresh, completion retry, and refresh-failure tolerance. | `.\gradlew.bat test` passes. |
| Keep `LevelProgressViewModel` unit coverage passing | `app/src/test/java/com/example/firsttest/ui/level/LevelProgressViewModelTest.kt` | Added tests for loading, status counts, error, and retry. | `.\gradlew.bat test` passes. |
| Keep `PracticeResultViewModel` unit coverage passing | `app/src/test/java/com/example/firsttest/ui/practice/PracticeResultViewModelTest.kt` | Added tests for load-once and error retry behavior. | `.\gradlew.bat test` passes. |
| Keep Band upgrade exam ViewModel coverage passing | `app/src/test/java/com/example/firsttest/ui/home/BandUpgradeExamViewModelTest.kt` | Added tests for loading the 40-question exam and all-correct/all-wrong completion against the fake repository. Keep these green while wiring target Supabase. | `.\gradlew.bat test` passes. |
| Keep no-assessment onboarding tests passing | `AppSessionViewModelTest`, `OnboardingViewModelTest` | Local tests now cover retired `ASSESSMENT_PENDING` error and fifth-answer completion to `HOME_READY` Level 1 without `finalizePlacement`. | `.\gradlew.bat test` passes. |
| Verify logging after one real round on target DB/device | `202607060029_phase1_practice_logging_evidence_test.sql`, manual app run | Local SQL now proves session, round, answer, mastery, mistake, reward, streak, and level-progress logging after a generated round. Re-run against target DB and confirm the Android flow produces the same state. | After a test round, query shows rows in `practice_sessions`, `practice_rounds`, `practice_round_questions`, `practice_answers`, `question_attempts`, `user_sense_mastery`, `mistake_senses`, profile reward/streak fields, and `user_level_progress`. |
| Run fresh-user manual demo script | `docs/plans/PHASE_1_MANUAL_DEMO_SCRIPT.md` | The repeatable script now exists; run it against the target Supabase DB and save evidence. | Evidence covers fresh user -> onboarding -> Level 1 -> deep Level 1-5 practice -> Level 6+ lightweight practice -> Band exam fail/pass -> restart -> sign out/in -> state restored. |
| Run Android unit tests | repo root | Local `.\gradlew.bat test --console=plain` passed on 2026-07-07 against the current worktree. Re-run before handoff or after any new code change. | Passing result recorded. |
| Run Android debug build | repo root | Local `.\gradlew.bat assembleDebug --console=plain` passed on 2026-07-07 against the current worktree. Re-run before handoff or after any new code change. | Debug APK path/date recorded. |

### P1 - Important After The Level 1-5 Loop Works

| Item | Location | What is needed | Acceptance check |
|---|---|---|---|
| Real email/password recovery | `ACCOUNT_AND_USER_DATA_PLAN.md`, auth UI, Supabase Auth settings | Phase 1 policy is username/password in the UI with deterministic internal placeholder emails in `SupabaseAuthRepository`. Real email collection and recovery are deferred. | Product decision and implementation for real email auth/recovery. |
| Clean stale `TODO PHASE N` comments for already-done work | `AppRepositories.kt`, `UserRepository.kt`, `FakeUserRepository.kt`, `MistakeRepository.kt`, `FakeMistakeRepository.kt` | These comments say fake repos still need replacement, but real repos are already wired. | Comments removed or rewritten so future scans do not produce false TODOs. |
| Refresh `docs/CODEBASE_INDEX.md` | `docs/CODEBASE_INDEX.md` | It is dated 2026-06-25 and contradicts newer code/docs about fake repo wiring, question types, and out-of-scope features. | Index matches current active/legacy files and repo wiring. |
| Verify `levels` table data in target DB | `levels` table; Level 1-5/full Band import SQL | Older TODO said level rows were missing. Current Level 1-5 import has level rows/upsert SQL; target DB still needs verification. | Home and Level progress show real titles/metadata for Levels 1-5 from Supabase. |
| Verify `word_forms` schema/import compatibility | migration `202606210003_create_ielts_vocabulary_schema.sql`, `06_word_forms.csv`, import SQL | Current schema and Level 1-5 import both use `id, word_id, sense_id, form_type, form_text, source_id, human_review`, but dry-run target DB. | `word_forms` import succeeds and word-form questions can be generated. |
| Verify Profile duck power/streak/props are live | `SupabaseUserRepository.kt`, `ProfileScreen.kt` | Code reads profile counters and `user_props`; confirm hosted rows update after completion. | Completing a round updates Profile after refresh/re-login. |
| Verify Streak screen refresh on target device | `StreakViewModel.kt`, `SupabaseVocabRepository.getPracticeSessionDates` | Local stale TODO is removed and tests cover calendar checks from completed session dates. Target-device evidence is still needed after a real completed round. | Today's calendar state and current streak reflect completed sessions after refresh/re-login. |
| Verify mistake notebook on target device | `SupabaseMistakeRepository.kt`, `pronunciations` table, manual app run | Local repository now reads `pronunciations.ipa_us` for active mistake senses and falls back to blank when missing. | After a real wrong answer, mistake entries appear and show IPA when available. |
| Add real mistake-review launch flow | `MistakesScreen.kt`, `MistakesViewModel.kt`, round RPCs | Mistake list is live, but "start review" is still TODO. | User can launch targeted review from due mistakes, or button is hidden/deferred. |
| Replace legacy daily practice card fake if revived | `SupabasePracticeRepository.kt`, `PracticeViewModel.kt`, `PracticeQuestionScreen.kt` | `getDailyPractice()` still delegates to `FakePracticeRepository`. Active Level 1-5 path does not use it. | Keep legacy flow out of navigation or implement real daily card query before exposing it. |
| Ability radar real non-vocabulary axes | `SupabaseUserRepository.radarFromLevel`, `ProfileScreen`, assessment/attempt tables | Listening/speaking/reading/writing axes are currently `0f`. Decide whether to derive from `question_type_key` accuracy or dedicated assessment. | Radar values come from persisted attempts; new user returns zeros without NaN/divide-by-zero. |

### P2 - Future Prototype Scope

| Item | Location | What is needed before building |
|---|---|---|
| Later Band upgrade exams after 4 -> 4.5 | `BAND_UPGRADE_EXAM_PLAN.md`, future migrations/RPCs | Generalize the Phase 1 Band 4 exam implementation to later Band transitions. |
| Band 4.5 content and later curriculum | `backend/content-pipeline/constructed_data/band_4_5_to_5_0_working_v1/`, pipeline scripts | Complete review, validation, export, import, and runtime verification. |
| Full two-band proof of concept | `MASTER_PROJECT_HANDOFF_PLAN.md` | Requires upgrade exam plus reviewed/imported Band 4.5 content and tests. |
| Pre-generated TTS audio pipeline | content pipeline, storage, `LevelPracticeScreen.kt` | Decide vendor/cost/storage; build `synthesize_audio.py`; upload audio; keep device TTS fallback. |
| Dedicated self-report or objective assessment report | `SELF_ASSESSMENT_20Q_PLAN.md`, `ui/assessment/` | Decide whether legacy assessment is replaced by informational self-report or real objective assessment. Must not gate progression. |
| Account recovery / real email auth | auth docs, Supabase dashboard, Android auth UI | Requires product decision to move away from placeholder-email username auth. |
| Account deletion, feedback, question-error reports, push devices | `ACCOUNT_AND_USER_DATA_PLAN.md` | Implement only when product surfaces are ready. |
| Hilt/Koin or navigation-compose migration | `ENGINEERING_QUALITY_FOLLOW_UP.md` | Add only when manual DI/manual navigation become maintenance problems. |

### Deferred/Legacy Code Kept Intentionally

| File/area | Current status | Rule |
|---|---|---|
| `FakeUserRepository.kt` | Test/offline implementation; not wired live by default. | Keep for tests/previews. |
| `FakeVocabRepository.kt` | Test/offline vocabulary and all 8 question types; behind `USE_REAL_VOCAB`. | Keep for tests/previews. |
| `FakePracticeRepository.kt` | Legacy daily-card fake; still used by `SupabasePracticeRepository.getDailyPractice()`. | Keep unless legacy daily-card flow is deleted or replaced. |
| `FakeMistakeRepository.kt` | Test/offline mistakes. | Keep for tests/previews. |
| `PracticeQuestionScreen.kt` / `PracticeViewModel.kt` | Old card-based practice flow. | Keep as reference unless legacy flow is formally removed. |
| `AssessmentScreen.kt` / `AssessmentViewModel.kt` | Legacy assessment/reassessment implementation. | Quarantine from Level 1-5 demo; future assessment must be informational unless upgrade-exam flow owns progression. |
| `ScratchCardScreen.kt` / `ScratchCardViewModel.kt` | Future reward mechanic candidate. | Deferred. |
| `finalize_placement` migration/RPC | Legacy compatibility artifact. | Do not use for new progression. Remove only after replacement flow is fully verified. |

### Known Stale or Contradictory Notes

- `CLAUDE.md` "Still needed" is partly stale. It mentions applying only
  migrations 015/016, but the repo now has migrations through 028.
- `CLAUDE.md` says StreakScreen needs live Supabase data. Current code reads
  profile streak counters and completed session dates; remaining work is
  verification/refresh cleanup.
- Older docs say `levels` rows are missing. The Level 1-5 import has level
  rows/upsert SQL; target database state still needs verification.
- `docs/CODEBASE_INDEX.md` is older than the current active path and should be
  refreshed before implementation decisions rely on it.
- Several source-policy docs still prefer British IPA, while the current master
  plan says American English is canonical. Resolve before audio or phonetic
  backfill work.

### Execution Order

1. Verify target Supabase migrations and Level 1-5 content import.
2. Quarantine legacy assessment from the claimed demo path and replace the Band
   exam placeholder with the real Band 4 -> 4.5 exam flow.
3. Add Level 1-5 SQL progression and installation checks.
4. Add Level progress/practice/result Android tests.
5. Verify visible refresh after practice completion on target device.
6. Run tests/build.
7. Record manual fresh-user combo demo evidence.
8. Clean stale comments/docs so the next scan stays accurate.

---

## Historical Scan From 2026-07-05

The sections below are retained for context. Prefer **Current Master TODO**
above when they conflict.

Status: living inventory, not final 闁?re-scan and update whenever a phase closes.

This file was built by scanning the whole repo for `TODO`/`FIXME` comments, "still
needed" items, and `Fake*Repository` implementations, then sorting every finding
into one of two buckets:

- **閹? TODO (real work)** 闁?things we actually need to build or fix for the
  product to work. Do these.
- **閹? Unfinished-by-design ("unpurpose")** 闁?things that are *intentionally*
  not built right now because the prototype doesn't need them yet, plus legacy
  code kept only as a future reference. Do **not** implement these unless the
  user explicitly asks 闁?but keep the architecture easy to extend toward them
  (that's why they're recorded here instead of just deleted/forgotten).

Every entry needs re-verification before acting on it 闁?this is a snapshot as of
2026-07-05, and comments/files drift out of date fast in this repo (several
`TODO PHASE N` comments found during this scan were already stale 闁?see 閹?).

---

## 閹? TODO 闁?real, active work needed

### App-level (from `CLAUDE.md` "Still needed", still true as of 2026-07-01)

| Item | Location | What's missing / needed before this is done |
|---|---|---|
| Apply migrations 015 + 016 to hosted Supabase | `backend/supabase/migrations/202606240015_level_round_weighted_scoring.sql`, `202606250016_cloze_question_support.sql` | Migrations are written and tested locally; need to confirm they've been run against the live/hosted Supabase project and that nothing errors. |
| RLS policy audit | Supabase dashboard / `backend/supabase/migrations/` | Verify anonymous (unauthenticated) reads are actually allowed on `words`, `questions`, `question_options` 闁?no migration currently asserts this is tested against a fresh RLS-locked project. |
| Profile duck power / radar / streak backend queries | `app/src/main/java/com/example/firsttest/data/repository/SupabaseUserRepository.kt` | Heatmap is live; duck power, ability radar (see row below), and streak stats on `ProfileScreen` still need to be confirmed reading from real Supabase queries end-to-end, not partially-fake fallback values. |
| Ability radar: listening/speaking/reading/writing axes | `app/src/main/java/com/example/firsttest/data/repository/SupabaseUserRepository.kt:166-171` | Hardcoded to `0f` 闁?comment says "no data source exists yet." Needs a dedicated assessment/scoring source per axis before this can show real numbers. |
| Streak target-device refresh evidence | `app/src/main/java/com/example/firsttest/ui/streak/StreakViewModel.kt`, `SupabaseVocabRepository.getPracticeSessionDates` | Current code has no stale auto-increment TODO. Backend round completion owns streak/reward updates; Streak reads completed session dates. Remaining work is target-device evidence after a real round. |
| `mistake_words`/`mistake_senses` phonetic data | `app/src/main/java/com/example/firsttest/data/repository/SupabaseMistakeRepository.kt` | Current code reads `pronunciations.ipa_us` for active mistake senses and falls back to blank. Target-device evidence still needed after a real wrong answer. |
| `word_forms` table schema/import verification | `backend/supabase/migrations/` + content pipeline import scripts | Confirm current migration schema for `word_forms` matches what the content pipeline exports before the next production import. |
| TTS audio pipeline | `content_pipeline` (or current pipeline dir) `pronunciation_tts_manifest.jsonl` | Manifest exists but `synthesize_audio.py` was never built 闁?no pre-generated audio files exist. Android currently uses on-device `TextToSpeech` as a placeholder (see `LevelPracticeScreen.kt`), not real recorded/synthesized audio. |
| Remaining curriculum content | `backend/content-pipeline/` | Continue the reviewed numbered script workflow (`backend/content-pipeline/README.md`) past Band 4 to fill out remaining IELTS bands. |
| `levels` table data rows | Supabase `levels` table | `LevelProgressScreen` needs real level-info rows (name, word count, etc.) before it can show anything other than placeholder/empty state. |

### Code-comment TODOs still current (not stale)

| Item | Location |
|---|---|
| `getDailyPractice()` still returns a fake card layout inside a "real" repository | `app/src/main/java/com/example/firsttest/data/repository/SupabasePracticeRepository.kt:20-29` 闁?`SupabasePracticeRepository.getDailyPractice()` literally calls `FakePracticeRepository().getDailyPractice()`. **Note:** this only matters if/when the legacy `PracticeViewModel` flow (閹?) gets revived 闁?`HomeViewModel` (active) does not call this method at all, it uses `VocabRepository` instead. Low priority unless legacy flow is un-retired. |

---

## 閹? Unfinished-by-design ("unpurpose") 闁?intentionally deferred / kept for future shape

These are not bugs. They exist so the architecture stays easy to extend later;
don't "fix" them without a product decision to actually build the feature.

### Legacy screens/ViewModels (per `docs/CODEBASE_INDEX.md` Section B)

Deliberately preserved, nothing in the live navigation graph routes to them.
Kept as templates for when/if these mechanics come back:

| File | Why it's kept |
|---|---|
| `ui/practice/PracticeQuestionScreen.kt` | Old card-based drill screen; template for future question-type UI |
| `ui/practice/PracticeViewModel.kt` | Original answer-grading ViewModel; reference for combo-bonus logic |
| `ui/practice/PracticeResultViewModel.kt` | Level word-status query after a session |
| `ui/assessment/AssessmentScreen.kt` | Placement assessment; retained only for the Profile "闂佹彃绉甸弻濠勬嫚閸曨亜寮? (reassessment) overlay, not first-run placement (that's been removed per the 2026-06-24 approved progression change) |
| `ui/assessment/AssessmentViewModel.kt` | Same as above 闁?assessment delivery + `finalize_placement` RPC |
| `ui/scratch/ScratchCardScreen.kt` | 闁告帩鍠栭崺澶愬础?(scratch-card) prop mechanic; not in current navigation, future reward-mechanic candidate |
| `ui/scratch/ScratchCardViewModel.kt` | Scratch state + streak-shield consumption logic |

### Fake repositories (always kept, by `CLAUDE.md` rule 闁?not a gap to fix)

| File | Purpose | Currently wired live? |
|---|---|---|
| `data/repository/FakeUserRepository.kt` | In-memory user state for offline dev/tests | No 闁?`AppRepositories.user` always uses `SupabaseUserRepository` now. Only referenced from unit tests today. |
| `data/repository/FakeMistakeRepository.kt` | In-memory mistake words, 5 Ebbinghaus stages | No 闁?`AppRepositories.mistakes` always uses `SupabaseMistakeRepository` now. Only referenced from unit tests today. |
| `data/repository/FakePracticeRepository.kt` | In-memory daily practice cards | Partially 闁?still the fallback inside `SupabasePracticeRepository.getDailyPractice()` (see 閹?) and behind the `USE_REAL_QUESTIONS` flag in `di/AppRepositories.kt:36`. |
| `data/repository/FakeVocabRepository.kt` | In-memory levels + all 8 question types, for offline dev | Behind `USE_REAL_VOCAB` flag in `di/AppRepositories.kt:63`; real repo used by default. |

### Dead/orphaned code found during this scan (cleanup candidate, not urgent)

| Item | Location | Note |
|---|---|---|
| `getMeaningChoiceQuestionsForLevel` legacy helper | `data/repository/SupabaseVocabRepository.kt` and matching repository interface/fake method | No active ViewModel calls this method; it is retained as a compatibility helper while active practice uses server-created rounds. |

### Stale `TODO PHASE N` comments (already done 闁?doc cleanup only)

These describe work that has since been completed; the comments were never
removed. Not action items, just note-to-self cleanup next time you're in the file:

| Location | Comment says | Actually true now |
|---|---|---|
| `di/AppRepositories.kt:27` | "TODO PHASE 4: swap [user] for SupabaseUserRepository..." | Already swapped 闁?`user = SupabaseUserRepository(Supabase.client)` (line 45). |
| `data/repository/UserRepository.kt:17,36` | "TODO PHASE 4: implement SupabaseUserRepository..." | Already implemented and live. |
| `data/repository/FakeUserRepository.kt:23` | "TODO PHASE 4: replace with SupabaseUserRepository..." | Already replaced in `AppRepositories`; this fake is test-only now. |
| `data/repository/MistakeRepository.kt:9` | "TODO PHASE 3: implement SupabaseMistakeRepository..." | Already implemented and live (`SupabaseMistakeRepository`, wired in `AppRepositories.kt:57`). |
| `data/repository/FakeMistakeRepository.kt:11` | "TODO PHASE 3: replace with SupabaseMistakeRepository." | Same 闁?already done. |

### Product features explicitly out of scope until approved (per `docs/CODEBASE_INDEX.md`)

This list is from a 2026-06-25 snapshot and is **partly stale** 闁?cross-check
before trusting it:

- ~~TTS audio~~ / ~~listening question type~~ / ~~word-form / collocation types~~ 闁?  **these are actually done now** per `CLAUDE.md` (all 8 question types shipped,
  Android TTS added). The index doc just wasn't updated.
- Speed bonus, listening bonus, or combo bonus beyond single-full-correct counting 闁?**still deferred**, no evidence this was built.
- `duck_points`, `near_meaning_count` 闁?**already added** (migration 016). Still stale in the index doc.
- `combo_success`, `mastery_success` columns 闁?status unconfirmed, re-check schema before assuming either way.

**Action item for whoever picks this up next:** `docs/CODEBASE_INDEX.md` itself
needs a refresh pass 闁?it's dated 2026-06-25 and several of its claims (fake
repo wiring, "out of scope" list) are contradicted by the more recent
`CLAUDE.md` status (dated 2026-07-01). Treat `CLAUDE.md` "Done"/"Still needed"
as the source of truth when the two disagree.

### Cross-cutting architecture principles (from `docs/plans/ENGINEERING_QUALITY_FOLLOW_UP.md`)

Not per-feature TODOs 闁?these are standing guidance for *when* to add
structure, intentionally not applied yet because the app is still small:

- Manual DI (`AppRepositories`) 闁?move to Hilt/Koin only once more real repos are added.
- Manual navigation 闁?move to `navigation-compose` only once there are several nested flows, deep links, or multiple independent tab back stacks.
- No use-case/interactor layer 闁?add one only when logic is duplicated or hard to test inside a ViewModel.

---

## 閹? Execution roadmap for 閹? (sequenced rounds)

Ordered by dependency and risk: infra verification first (cheap, unblocks
testing everything else against the hosted instance), then small self-contained
fixes, then the two items that need an explicit product/vendor decision before
any code gets written. Round 7 (content) is independent and can run in
parallel with all the others.

### Round 1 闁?Hosted Supabase foundation
**Research/decide first:** none 闁?this is verification, not design. Just need
access to the hosted Supabase project dashboard/SQL editor.
**Do:**
1. Run `202606240015_level_round_weighted_scoring.sql` and
   `202606250016_cloze_question_support.sql` against the hosted project (in
   order, each is a self-contained transaction per migration convention).
2. Audit RLS: with an anon (unauthenticated) key, attempt `select` on `words`,
   `questions`, `question_options`. Confirm policy allows it (or fix the policy
   in a new forward-fix migration 闁?never edit an applied migration file).
**Test after:**
- Fresh anon-key query against all three tables returns rows, no RLS error.
- Run the Android app against the hosted project (not local/emulator fake) and
  complete one full `LevelPracticeScreen` round end-to-end 闁?confirms both the
  migrations and RLS are actually correct together, not just individually.

### Round 2 闁?`levels` table + `word_forms` schema
**Research/decide first:**
- Read what `LevelProgressScreen` actually renders (level name, word count,
  band) vs. what's already computed client-side (`bandForLevel()` in
  `SupabaseUserRepository.kt`) 闁?decide whether `levels` needs full metadata
  rows or just word counts, so you don't backfill columns nothing reads.
- Diff the `word_forms` migration schema against the content pipeline's export
  columns 闁?decide if the mismatch (if any) is fixed in a new migration or in
  the pipeline export step.
**Do:**
1. Backfill/insert `levels` rows (name, band, word count) for at least the
   Band 4 levels already imported.
2. Patch whichever side (migration or pipeline export) is out of sync for
   `word_forms`.
**Test after:**
- Open `LevelProgressScreen` for 2-3 different levels, confirm real data
  renders (not empty/placeholder state).
- Dry-run a `word_forms` import for one already-validated batch, confirm no
  column mismatch errors.

### Round 3 闁?Mistake-notebook phonetic data
**Research/decide first:** check whether the content pipeline's source data
(ECDICT export) already carries a phonetic transcription per word 闁?if yes,
this is a backfill; if no, decide the transcription source before writing the
migration.
**Do:**
1. New migration: add `phonetic` column to `words` (forward-fix, don't touch
   applied migrations).
2. Backfill from the source data identified above.
3. Update `SupabaseMistakeRepository.kt:47` to read the real column.
**Test after:**
- Open 闂佹寧鐟ㄩ惁婵嬪嫉?for a handful of known mistake words, confirm phonetic displays.
- Confirm a word with no matched phonetic renders blank, not a crash.

### Round 4 - Streak target-device refresh evidence
**Current status:** backend round completion owns streak/reward updates, and
`StreakViewModel` reads completed session dates for the calendar. The stale
auto-increment TODO was removed from code.
**Do:**
1. Run a real target-device practice round against the target Supabase project.
2. Reopen the Streak screen or relogin.
**Test after:**
- Today's calendar state and current streak reflect the completed practice
  session.
- A second same-day completion does not create duplicate calendar cells.
### Round 5 闁?Ability radar (listening/speaking/reading/writing axes)
**Research/decide first (needs your input, not just mine):** all 8 question
types are already graded server-side per `question_type_key`
(`listening_choice`, `listening_fill`, `speaking_repeat`, `open_speaking`,
`reading_comprehension`, etc.). Before building anything, decide: can each
radar axis be *derived* from existing per-type accuracy (e.g. average accuracy
across `listening_choice` + `listening_fill` 闁?listening axis), or do you want
a genuinely separate "dedicated assessment" per axis as the original comment
implies? The derived approach is far less work and reuses data you already
have 闁?flagging this as the recommended default, but it's a product call.
**Do (once decided):**
1. If derived: write a Supabase RPC/view aggregating accuracy by
   `question_type_key` grouped into the four axes.
2. Wire `SupabaseUserRepository`'s `radarFromLevel()` to call it instead of the
   hardcoded `0f` values (`SupabaseUserRepository.kt:166-171`).
**Test after:**
- For a test user with known answer history, manually compute expected
  per-axis accuracy and compare against what the RPC returns.
- Brand-new user with zero history still returns `0f` axes without a
  divide-by-zero/NaN.

### Round 6 闁?TTS audio pipeline
**Research/decide first (needs your input 闁?cost/vendor decision):** decide
whether to keep on-device `TextToSpeech` as the permanent solution for this
phase, or invest in pre-generated audio now. If pre-generating: pick a TTS
vendor (cost per character, voice licensing, IELTS-accent fit), and decide
storage (Supabase Storage bucket vs CDN).
**Do (once decided):**
1. Build `synthesize_audio.py` consuming `pronunciation_tts_manifest.jsonl`.
2. Upload generated audio to the chosen storage location.
3. Update `LevelPracticeScreen` to fetch/play pre-generated audio, falling
   back to device TTS only if a file is missing.
**Test after:**
- Spot-check pronunciation accuracy on a sample of words across a few accents/
  difficulty bands.
- Kill/omit one audio file deliberately, confirm graceful fallback to device
  TTS rather than a crash or silent failure.

### Round 7 闁?Remaining curriculum content (parallel, no blocking decision)
**Research/decide first:** none new 闁?continue the existing numbered
pipeline workflow (`backend/content-pipeline/README.md`) into the next band.
**Do:** run the next numbered scripts for the next IELTS band batch.
**Test after:** existing numbered validation scripts must pass, plus the
standard human-QA pass before marking a batch `production` (per `CLAUDE.md`
content pipeline rules).

---

## 閹? How to keep this file useful

- Re-run this scan (`grep -rn "TODO\|FIXME"` across `.kt`/`.py`/`.sql`, plus a
  glob for `Fake*Repository`) whenever a phase in `CLAUDE.md` closes, since
  comments here rot fast (see the stale-`PHASE N` table above 闁?half the TODOs
  found in this scan were already done).
- When an item in 閹? gets built, move its row here to 閹?'s "already done"
  history or just delete the row 闁?don't let done work linger in the TODO list.
- When a 閹? item becomes an actual near-term goal (user asks for it), promote
  the row to 閹? with a real location/line reference.
