# Level 1-5 Final Prototype Goal

Status: working checkpoint goal, derived from current docs and code on
2026-07-06.

This document defines the near-term "final prototype" checkpoint requested for
the app: prove the real app loop can run across Levels 1-5 with assessment,
logging, level-up logic, and unlock logic. It is intentionally smaller than the
larger two-band proof of concept in `MASTER_PROJECT_HANDOFF_PLAN.md`.

## 1. Done statement

The Level 1-5 final prototype is done when a fresh user can install the app,
register or sign in, complete onboarding, start at Level 1, progress through
Levels 1-5 using real Supabase-backed practice rounds, and close/reopen or
sign out/sign in without losing state.

The demonstrated path must use real runtime data and server-owned state for the
core loop. Fake repositories may remain only for tests, previews, and legacy
screens outside the demonstration path.

## 2. Required user journey

The demonstration journey is:

```text
fresh install
-> register/sign in
-> complete onboarding
-> land on Home with Level 1 unlocked
-> open Level 1 progress
-> start a server-created practice round
-> answer every question
-> complete the round
-> persist answer/session/progress/reward/streak/mistake state
-> unlock the next level when completion rules are satisfied
-> repeat until Levels 1-5 can each be opened and practiced
-> restart app
-> verify the same unlocked levels, progress, logs, mistakes, and profile state
-> sign out and sign back in
-> verify the same state again
```

## 3. Scope

In scope:

- Username/password auth against Supabase.
- Resume-safe onboarding that unlocks Level 1 and does not route through the
  retired initial placement assessment.
- Real Levels 1-5 content, level metadata, and level progress rows.
- Server-created immutable practice rounds.
- Server-side answer grading.
- Persisted practice logging:
  - round/session rows;
  - per-question answer rows;
  - question-attempt rows where used by the generated question flow;
  - mastery/progress updates;
  - active mistake index updates;
  - reward/streak/check-in updates.
- Level-up and unlock logic from Level 1 through Level 5.
- Informational assessment/report entry that does not gate progression, or a
  clearly labeled placeholder if the owner keeps it out of this checkpoint.
- Automated tests and one manual end-to-end evidence pass.

Out of scope for this checkpoint:

- Full Band 4.0 to 4.5 upgrade exam persistence and unlock.
- Full two-band content completion.
- Public launch, app-store release, paid services, production monitoring, and
  legal/commercial operation.
- Pre-generated TTS audio if Android device TTS is acceptable for the demo.

## 4. Acceptance criteria

### App flow

- Signed-out startup shows auth, not Home.
- New user registration creates profile/settings/bootstrap rows.
- Onboarding saves each answer and completing the fifth answer unlocks Level 1.
- Existing onboarded users bypass onboarding after app restart.
- The retired initial assessment is not part of first-run startup.
- Profile assessment/report UI is either informational only or hidden/labeled as
  incomplete.

### Levels 1-5

- Home shows Levels 1-5 from Supabase data, not hardcoded fake content.
- Locked levels cannot be practiced.
- Completing the required persisted practice for a level unlocks the next
  level idempotently.
- Repeating a completed level creates or resumes valid server rounds without
  duplicating rewards or unlock events.
- Level 5 can be opened and practiced after progressing through Levels 1-4.

### Practice and logging

- `start_practice_round(level)` creates or resumes an owned round for Levels
  1-5.
- Rounds contain no duplicate `sense_id` values.
- `save_practice_answer(round, position, answer, response_time_ms)` calculates
  correctness server-side and writes the answer log.
- Wrong answers update the active mistake index.
- Correct answers update mastery/review state according to the Level plan.
- `complete_practice_round(round)` is idempotent and updates profile reward,
  streak/check-in, level progress, and next-level unlock state.
- Client code does not trust itself for correctness, level completion, rewards,
  or unlocks.

### Persistence and recovery

- App restart preserves auth session and current app state.
- Sign-out clears in-memory state.
- Sign-in restores profile, level progress, mistakes, streak/reward state, and
  any started round.
- Network/load failures show retryable error states instead of fake data.

### Test evidence

- Android unit tests cover session routing, onboarding route, practice
  completion UI state, and Level 1-5 unlock-visible behavior.
- SQL tests cover onboarding Level 1 unlock, practice logging, round completion
  idempotency, and next-level unlock through Level 5.
- `.\gradlew.bat test` passes.
- `.\gradlew.bat assembleDebug` passes.
- Supabase verification SQL passes against the chosen environment.
- A manual fresh-user script is recorded with the tested APK/build and backend
  migration state.

## 5. Current baseline from repository scan

Already present:

- Supabase auth/user/onboarding repositories are wired by default.
- Session bootstrap routes onboarding-complete users to the main app.
- Retired `ASSESSMENT_PENDING` startup state now shows an error instead of
  silently continuing the old flow.
- Home, Level progress, Level practice, result, mistakes, streak, and profile
  screens exist.
- Supabase practice RPCs exist for starting rounds, saving answers, and
  completing rounds.
- Migrations and SQL tests exist for onboarding, spaced review, Band 4 content,
  context hints, and generated practice rounds.

Known gaps to close or verify:

- The Profile reassessment overlay has been removed from the active shell; legacy
  assessment code remains only as retained future/reference code.
- Band exam entry now opens the real `BandUpgradeExamScreen`.
- `SupabasePracticeRepository.getDailyPractice()` still delegates the legacy
  daily card layout to `FakePracticeRepository`; keep it out of the demo path
  or replace it.
- Level metadata/content for Levels 1-5 must be verified in the target
  Supabase environment.
- Hosted migration state and RLS behavior must be verified, not assumed.
- Test coverage needs to assert Level 1-5 progression, not just Level 1.

## 6. Implementation sequence

1. Verify backend state for Levels 1-5:
   migrations applied, content imported, level rows present, RLS correct, and
   SQL tests passing.
2. Keep app navigation tight for this checkpoint:
   first-run assessment stays removed; profile assessment remains hidden; band
   exam routes to the real Phase 1 upgrade-exam flow.
3. Verify and patch Level 1-5 progress UI:
   each level opens, locked state is honored, and real level metadata renders.
4. Verify and patch practice logging:
   start, answer, complete, result, mistakes, reward, streak, and repeat-round
   behavior all round-trip through Supabase.
5. Add focused tests for Level 1-5 progression and idempotent completion.
6. Run the final evidence pass:
   unit tests, debug build, Supabase verification, and a manual fresh-user
   progression script.

## 7. Non-negotiable boundary

Do not mark this prototype done because screens exist. It is done only when the
fresh-user Level 1-5 path runs against real Supabase state, persists its logs
and progression, survives restart/re-login, and has recorded build/test
evidence.
