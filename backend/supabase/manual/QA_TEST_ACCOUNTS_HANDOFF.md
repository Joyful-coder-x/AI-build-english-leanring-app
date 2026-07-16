# QA test accounts — handoff

## Status: script fixed, validated locally, ready to paste into production

## Goal (final result)

Two real, password-loginable accounts on the **production** Supabase project
(`skcwvrxktdqdjcqcagsc`), usable directly in the Android app, so a human can
eyeball two specific states:

1. **`qa_level1_near_up`** — a Level 1 user who is one successful spaced
   review away from completing Level 1 and unlocking Level 2.
2. **`qa_streak_5day`** — a user with a 5-day practice streak, to check the
   streak counters and the Profile heatmap (which reads distinct practice
   dates from `practice_sessions`).

## Already done

- Both accounts **already exist on production**, created through the same
  `POST /auth/v1/signup` call the app's own `register()` flow uses (see
  `SupabaseAuthRepository.kt`), so they are fully real accounts — not a raw
  `auth.users` insert:
  - `qa_level1_near_up` / `QaLevelUp2026!` → id `0fb80de3-87f3-47bf-8ad2-9337711bcdbd`
  - `qa_streak_5day` / `QaStreak2026!` → id `59825550-bcbe-4624-a9a2-64303f03e010`
  - Right now these are just bare freshly-registered accounts — onboarding
    is not completed and no practice history exists yet.
- The seeding script **`backend/supabase/manual/create_qa_test_accounts.sql`**
  has been rewritten, run against a disposable local Docker Postgres copy
  (all 45 migrations applied, Band 4 content imported), and confirmed clean.
  Two rounds of bugs were found and fixed in this pass:
  1. **Type-inference errors in the `UNION ALL` insert** for
     `user_sense_mastery` — bare literals (`'uuid-string'`, `'reviewing'`,
     `null`) resolved to `text` instead of the target column types
     (`uuid`, `sense_learning_state_enum`, `timestamptz`) once combined
     across the two `select` branches. Fixed with explicit casts
     (`::uuid`, `::sense_learning_state_enum`, `null::timestamptz`).
  2. **The onboarding-completion step didn't actually unlock anything.**
     Setting `profiles.onboarding_status = 'completed'` directly is not
     what the app's real onboarding flow does. Per
     `202606240007_onboarding_starts_at_level_one.sql`,
     `save_onboarding_answer()` only unlocks Level 1 when it flips
     `onboarding_profiles.flow_state` to `'home_ready'` on the 5th answer,
     and separately inserts a `user_level_progress` row
     (`is_unlocked=true`). The old script skipped both, so
     `get_user_bootstrap_state()` kept returning
     `flow_state: "questionnaire_pending"`, `highest_unlocked_level: null`
     — the app would have routed these accounts straight back to the
     onboarding questionnaire instead of showing Level 1. Fixed by having
     the script insert directly into `onboarding_profiles`
     (`flow_state='home_ready'`, 5 synthetic answers, `current_question_index=5`)
     and `user_level_progress` (level 1, `is_unlocked=true`), mirroring
     what the migration and RPC do for real users.
  - The script's final sanity-check query was also widened to join
    `onboarding_profiles` and `user_level_progress` so a stale
    `flow_state`/unlock gap like this would show up immediately instead of
    silently passing (the old check only looked at `profiles` columns).
- **Locally verified end-to-end** (container has since been removed): both
  accounts came out with `flow_state: "home_ready"`,
  `highest_unlocked_level: 1`, `current_level: 1`. `qa_level1_near_up` has
  exactly 45 `user_sense_mastery` rows (40 qualifying, 5 due now),
  `user_level_progress.is_completed = false`, `progress = 0.50` — i.e.
  correctly *near* completion, not accidentally completed.
  `qa_streak_5day` has `current_streak_days=5, longest_streak_days=5,
  login_count=3, last_practice_date=today`.
- No production writes have been made. No local container is running
  anymore (removed after validation passed) — nothing to clean up.

## To resume

1. Open the Supabase SQL Editor for the production project
   (`skcwvrxktdqdjcqcagsc`).
2. Paste and run the full contents of
   `backend/supabase/manual/create_qa_test_accounts.sql` (already fixed —
   no further edits needed).
3. Check the final `select` output at the bottom of the script:
   - `qa_level1_near_up`: `onboarding_status=completed`,
     `flow_state=home_ready`, `level1_unlocked=t`, `level1_completed=f`,
     `level1_progress=0.50`.
   - `qa_streak_5day`: `onboarding_status=completed`,
     `flow_state=home_ready`, `level1_unlocked=t`, `current_streak_days=5`,
     `longest_streak_days=5`, `login_count=3`.
4. Log into the app as each user and confirm:
   - `qa_level1_near_up` lands on Home (not the onboarding questionnaire),
     Level 1 shows as in-progress, and answering one of the 5 pending
     spaced-review senses correctly completes Level 1.
   - `qa_streak_5day` lands on Home, shows a 5-day streak, and the Profile
     heatmap shows 5 consecutive filled days ending today.

## Gotcha (unrelated, now resolved — no action needed)

- `backend/supabase/migrations/202607150045_word_form_stem_names_the_form.sql`
  was flagged earlier in this working session as broken. It has since been
  fixed (in a different task, in the same session) and verified against a
  clean local Postgres container — `word_form` question stems now name the
  actual requested form (e.g. `Type the plural form of "cousin"...`)
  instead of a vague placeholder, and it applies cleanly with the other 44
  migrations. No longer something to work around.
- `backend/supabase/tests/` → `backend/supabase/migrations/tests/` is still
  an uncommitted move sitting in the working tree from unrelated
  in-progress work (parallel to uncommitted app changes in `Level.kt`,
  `SupabaseVocabRepository.kt`, `HomeScreen.kt`, `HomeViewModelTest.kt`,
  `backend/supabase/README.md`). `run_phase1_local_docker_verification.ps1`
  still points at the old path and will fail until that script's
  `$testDir` is updated — still not this task's responsibility to fix.
