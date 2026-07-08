# Phase 1 Target Evidence Template

Status: fill this file after running against the hosted Supabase target and a
real Android debug install.

Do not mark Phase 1 complete until every required field below is filled with
actual command output, screenshots/notes, or explicit PASS/FAIL evidence.

## 1. Target Backend

- Date:
- Operator:
- Supabase project reference:
- Database connection source:
  - `DATABASE_URL` set locally: yes/no
  - connection string stored in repo: no
- Backup completed before destructive import: yes/no/not applicable
- Migrations verified through:
  - expected latest: `202607060028_due_review_new_word_gate.sql`
  - observed latest:
- Content package:
  - expected: `backend/content-pipeline/constructed_data/band_4_0_v1/supabase_import/`
  - imported: yes/no
  - import mode: fresh/reset/non-mutating verification

## 2. Target Verification Command

Command used:

```powershell
$env:DATABASE_URL = "<redacted>"
powershell -ExecutionPolicy Bypass -File backend/supabase/manual/run_phase1_target_verification.ps1
```

If applying migrations/importing content, record the exact command:

```powershell
powershell -ExecutionPolicy Bypass -File backend/supabase/manual/run_phase1_target_verification.ps1 -ApplyMigrations -ResetVocabulary -ImportBand4
```

Result:

- `verify_project_installation.sql`: PASS/FAIL
- `202606220005_user_bootstrap_and_onboarding_test.sql`: PASS/FAIL
- `202606240007_onboarding_starts_at_level_one_test.sql`: PASS/FAIL
- `202606240009_spaced_review_practice_rounds_test.sql`: PASS/FAIL
- `202606240010_band4_content_runtime_test.sql`: PASS/FAIL
- `202606240012_conditional_context_hints_test.sql`: PASS/FAIL
- `202606250016_sentence_cloze_level_rounds_test.sql`: PASS/FAIL
- `202607060025_combo_scope_practice_type_selection_test.sql`: PASS/FAIL
- `202607060026_band_upgrade_exam_core_test.sql`: PASS/FAIL
- `202607060027_band4_unlock_chain_test.sql`: PASS/FAIL
- `202607060029_phase1_practice_logging_evidence_test.sql`: PASS/FAIL

Paste or attach command output summary:

```text

```

## 3. Android Build

- Command: `.\gradlew.bat test --console=plain`
- Result:
- Command: `.\gradlew.bat assembleDebug`
- Result:
- APK installed from:
  - expected: `app/build/outputs/apk/debug/app-debug.apk`
  - actual:
- Device/emulator:
- App build date/time:

## 4. Fresh User Manual Flow

Test account:

- username:
- created fresh: yes/no

Onboarding:

- completed all questions: PASS/FAIL
- Home opened without assessment: PASS/FAIL
- Level 1 unlocked and later levels locked: PASS/FAIL

Deep Levels 1-5:

- Level 1 round opens and completes: PASS/FAIL
- Level 2 unlocks after Level 1: PASS/FAIL
- Level 3 unlocks after Level 2: PASS/FAIL
- Level 4 unlocks after Level 3: PASS/FAIL
- Level 5 unlocks after Level 4: PASS/FAIL
- Observed question types across Levels 1-5:
  - `meaning_choice`:
  - `sentence_cloze_typing`:
  - `listening_choice`:
  - `listening_fill`:
  - `speaking_repeat`:
  - `open_speaking`:
  - `word_form`:
  - `reading_comprehension`:

Lightweight Levels 6-33:

- Level 6 round opens and completes: PASS/FAIL
- Later Band 4 level tested:
- Later level round opens and completes: PASS/FAIL
- Disallowed Level 6+ types absent (`open_speaking`, `word_form`,
  `reading_comprehension`): PASS/FAIL

Band 4 -> 4.5 Exam:

- 40 questions created: PASS/FAIL
- 36/40 attempt fails: PASS/FAIL
- failed attempt does not unlock Band 4.5: PASS/FAIL
- 37/40 or higher attempt passes: PASS/FAIL
- passing unlocks first Band 4.5 level: PASS/FAIL
- active attempt resumes after restart: PASS/FAIL

Logging and persistence:

- wrong answer creates mistake notebook entry: PASS/FAIL
- IPA displays when available and blank fallback is safe: PASS/FAIL
- practice session/round/answer rows exist: PASS/FAIL
- `user_sense_mastery` updates: PASS/FAIL
- `user_level_progress` updates: PASS/FAIL
- streak/profile counters update after completion: PASS/FAIL
- force-close/reopen restores state: PASS/FAIL
- sign out/sign in restores state: PASS/FAIL

## 5. Known Limitations For Demo

Record any observed limitation that does not block Phase 1:

- Device TTS is prototype audio; pre-generated audio is Phase 2.
- Mistake review launch flow is deferred; mistake list evidence is Phase 1.
- Real email/password recovery is deferred; Phase 1 uses username/password with
  internal placeholder email mapping.
- Band 4.5 curriculum content beyond the unlock gate is not Phase 1 unless
  separately imported and verified.

Additional notes:

```text

```
